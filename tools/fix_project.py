#!/usr/bin/env python3
"""Turns the converter's AppKit skeleton into the SwiftUI menu-bar app.

`safari-web-extension-converter` always regenerates a storyboard app, so this
runs after it and is safe to run again. It edits `project.pbxproj` by whole
objects - an earlier version deleted single LINES and left an unbalanced brace
that Xcode would not open at all.
"""
import os
import re
import sys
import uuid

PROJ = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "app/Clerk/Clerk.xcodeproj/project.pbxproj")

# the files the converter makes that the SwiftUI app does not want
DROP = ["AppDelegate.swift", "ViewController.swift", "Main.storyboard", "Main.html",
        "Icon.png", "Style.css", "Script.js"]

ADD = ["ClerkApp.swift", "SettingsView.swift", "ShortcutRecorder.swift",
       "Core/Fields.swift", "Core/Store.swift", "Core/Match.swift",
       "Core/Jev.swift", "Core/Server.swift", "Core/Importer.swift"]


def oid():
    return uuid.uuid4().hex[:24].upper()


def drop_objects(s, names):
    """Remove every top-level object whose comment names one of `names`, and
    every reference to those object ids."""
    ids = set()
    for name in names:
        for m in re.finditer(r"\t\t([0-9A-F]{24}) /\* " + re.escape(name) + r"[ *]", s):
            ids.add(m.group(1))
    # a file's PBXBuildFile points at its PBXFileReference, so sweep those too
    for oid_ in list(ids):
        for m in re.finditer(r"\t\t([0-9A-F]{24}) /\* [^*]* \*/ = \{isa = PBXBuildFile; "
                             r"fileRef = " + oid_, s):
            ids.add(m.group(1))
    # Walk the lines. A one-line object ends on its own line; a block object runs
    # to the next line that is exactly "\t\t};". Doing this with one regex ate
    # everything between a one-line object and the next block's closing brace.
    out, skipping = [], False
    for line in s.split("\n"):
        if skipping:
            if line == "\t\t};":
                skipping = False
            continue
        m = re.match(r"\t\t([0-9A-F]{24}) /\*", line)
        if m and m.group(1) in ids:
            if not line.rstrip().endswith("};"):
                skipping = True
            continue
        # a list entry pointing at a dropped object
        m = re.match(r"\t+([0-9A-F]{24}) /\*.*\*/,$", line)
        if m and m.group(1) in ids:
            continue
        out.append(line)
    return "\n".join(out)


INFO = os.path.join(os.path.dirname(PROJ), "..", "Clerk", "Info.plist")
BUILD = open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "build_number")).read().strip()

# Sparkle. Only the PUBLIC half of the ed25519 key lives here; the private half
# is tools/sparkle/eddsa_private.pem and is never put in the keychain, so nothing
# ever prompts for a password to sign a release.
SPARKLE_KEYS = """	<key>SUFeedURL</key>
	<string>https://dancykier.com/clerk/appcast.xml</string>
	<key>SUPublicEDKey</key>
	<string>5oQ5ZKJha6WUKKnFHdfjS6/Kq74AkLgCtz5wVoLyyA0=</string>
	<key>SUEnableAutomaticChecks</key>
	<true/>
	<key>SUScheduledCheckInterval</key>
	<integer>86400</integer>
"""

URL_TYPES = """	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>
			<string>com.DNZ.clerk</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>clerk</string>
			</array>
		</dict>
	</array>
"""


def fix_info_plist():
    """`open clerk://settings` is how the window is opened from a script or a
    keyboard shortcut. The converter rewrites Info.plist, so put it back."""
    path = os.path.normpath(INFO)
    text = open(path).read()
    add = ""
    if "CFBundleURLTypes" not in text:
        add += URL_TYPES
    if "SUFeedURL" not in text:
        add += SPARKLE_KEYS
    if not add:
        return
    open(path, "w").write(text.replace("</dict>\n</plist>", add + "</dict>\n</plist>"))


def developer_id(b):
    """Sign with the Developer ID certificate, not the development one.

    Safari refuses a development-signed extension unless "Allow Unsigned
    Extensions" is ticked, and that resets every time Safari quits. A Developer
    ID signature plus notarisation makes it stick.

    Do NOT add CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO to drop `get-task-allow`:
    it drops the WHOLE entitlements file with it, including the sandbox and the
    network access the extension needs, and the extension then silently cannot
    reach the helper. A Developer ID signature leaves get-task-allow out anyway.
    """
    b = b.replace("\t\t\t\tCODE_SIGN_STYLE = Automatic;",
                  "\t\t\t\tCODE_SIGN_IDENTITY = \"Developer ID Application\";\n"
                  "\t\t\t\tCODE_SIGN_STYLE = Manual;\n"
                  "\t\t\t\tOTHER_CODE_SIGN_FLAGS = \"--timestamp\";")
    if "ENABLE_HARDENED_RUNTIME" not in b:
        b = b.replace("\t\t\t\tENABLE_APP_SANDBOX",
                      "\t\t\t\tENABLE_HARDENED_RUNTIME = YES;\n\t\t\t\tENABLE_APP_SANDBOX")
    return b


SPARKLE_URL = "https://github.com/sparkle-project/Sparkle"
SPARKLE_MIN = "2.6.0"


def add_sparkle(s):
    """Add Sparkle as a Swift package to the APP target.

    The project is regenerated on every build, so this has to be re-applied each
    time. SPM rather than an embedded xcframework: Xcode then handles signing and
    embedding the framework itself, which is the fiddliest part by hand.
    """
    if "XCRemoteSwiftPackageReference" in s:
        return s
    pkg, prod, build = oid(), oid(), oid()

    s = s.replace("/* End PBXBuildFile section */",
                  f"\t\t{build} /* Sparkle in Frameworks */ = {{isa = PBXBuildFile; "
                  f"productRef = {prod} /* Sparkle */; }};\n/* End PBXBuildFile section */")

    # the app target's Frameworks phase is the first one
    s = re.sub(r"(/\* Begin PBXFrameworksBuildPhase section \*/\n\t\t[0-9A-F]{24} /\* Frameworks \*/ = \{"
               r"\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = \d+;\n\t\t\tfiles = \(\n)",
               r"\1" + f"\t\t\t\t{build} /* Sparkle in Frameworks */,\n", s, count=1)

    s = s.replace('\t\t\tproductType = "com.apple.product-type.application";',
                  f"\t\t\tpackageProductDependencies = (\n\t\t\t\t{prod} /* Sparkle */,\n\t\t\t);\n"
                  '\t\t\tproductType = "com.apple.product-type.application";')

    s = re.sub(r"(\n\t\t\tprojectDirPath = \"\";)",
               f"\n\t\t\tpackageReferences = (\n\t\t\t\t{pkg} /* XCRemoteSwiftPackageReference \"Sparkle\" */,\n\t\t\t);"
               + r"\1", s, count=1)

    s = s.replace("/* End PBXProject section */", "/* End PBXProject section */\n"
        "\n/* Begin XCRemoteSwiftPackageReference section */\n"
        f'\t\t{pkg} /* XCRemoteSwiftPackageReference "Sparkle" */ = {{\n'
        "\t\t\tisa = XCRemoteSwiftPackageReference;\n"
        f'\t\t\trepositoryURL = "{SPARKLE_URL}";\n'
        "\t\t\trequirement = {\n"
        f'\t\t\t\tkind = upToNextMajorVersion;\n\t\t\t\tminimumVersion = {SPARKLE_MIN};\n'
        "\t\t\t};\n\t\t};\n"
        "/* End XCRemoteSwiftPackageReference section */\n"
        "\n/* Begin XCSwiftPackageProductDependency section */\n"
        f"\t\t{prod} /* Sparkle */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n"
        f'\t\t\tpackage = {pkg} /* XCRemoteSwiftPackageReference "Sparkle" */;\n'
        "\t\t\tproductName = Sparkle;\n\t\t};\n"
        "/* End XCSwiftPackageProductDependency section */")
    return s


def main():
    fix_info_plist()
    s = open(PROJ).read()

    # The app's own Resources group is left in place, just empty. Dropping by
    # name would also take the EXTENSION's Resources group, which holds the
    # whole web extension.
    s = drop_objects(s, DROP)

    refs, builds, app_children, core_children, sources = [], [], [], [], []
    for path in ADD:
        fid, bid = oid(), oid()
        base = os.path.basename(path)
        refs.append(f'\t\t{fid} /* {base} */ = {{isa = PBXFileReference; '
                    f'lastKnownFileType = sourcecode.swift; path = {base}; sourceTree = "<group>"; }};')
        builds.append(f'\t\t{bid} /* {base} in Sources */ = {{isa = PBXBuildFile; '
                      f'fileRef = {fid} /* {base} */; }};')
        (core_children if path.startswith("Core/") else app_children).append(
            f"\t\t\t\t{fid} /* {base} */,")
        sources.append(f"\t\t\t\t{bid} /* {base} in Sources */,")

    s = s.replace("/* End PBXBuildFile section */",
                  "\n".join(builds) + "\n/* End PBXBuildFile section */")
    s = s.replace("/* End PBXFileReference section */",
                  "\n".join(refs) + "\n/* End PBXFileReference section */")

    core_gid = oid()
    s = s.replace("/* End PBXGroup section */",
                  f"\t\t{core_gid} /* Core */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
                  + "\n".join(core_children)
                  + '\n\t\t\t);\n\t\t\tpath = Core;\n\t\t\tsourceTree = "<group>";\n\t\t};\n'
                  + "/* End PBXGroup section */")

    anchor = re.search(r"\t\t\t\t([0-9A-F]{24}) /\* Assets\.xcassets \*/,\n", s)
    s = s[:anchor.start()] + "\n".join(app_children) + f"\n\t\t\t\t{core_gid} /* Core */,\n" \
        + s[anchor.start():]

    # the app target's Sources phase is the first one, and it is empty now
    s = re.sub(r"(/\* Begin PBXSourcesBuildPhase section \*/\n\t\t[0-9A-F]{24} /\* Sources \*/ = \{"
               r"\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tfiles = \(\n)",
               r"\1" + "\n".join(sources) + "\n", s, count=1)

    # build settings: menu-bar only, and no sandbox so the app reads the same
    # login keychain the CLI writes to
    def settings(m):
        b = m.group(0)
        b = b.replace("ENABLE_APP_SANDBOX = YES;", "ENABLE_APP_SANDBOX = NO;")
        b = b.replace("\t\t\t\tINFOPLIST_KEY_NSMainStoryboardFile = Main;\n",
                      "")   # NOT LSUIElement: Clerk is a real app with a Dock icon
        # The converter capitalises the app's id but not the extension's, and
        # then the appex id is not prefixed by the app's - which fails the build.
        b = b.replace("PRODUCT_BUNDLE_IDENTIFIER = com.DNZ.Clerk;",
                      "PRODUCT_BUNDLE_IDENTIFIER = com.DNZ.clerk;")
        b = re.sub(r"MARKETING_VERSION = [^;]+;", "MARKETING_VERSION = 0.0.1;", b)
        # Sparkle compares CFBundleVersion, so the build number is what decides
        # whether an installed copy updates. tools/release.sh raises it.
        b = re.sub(r"CURRENT_PROJECT_VERSION = [^;]+;",
                   f"CURRENT_PROJECT_VERSION = {BUILD};", b)
        return developer_id(b)

    s, n = re.subn(r'/\* (?:Debug|Release) configuration for PBXNativeTarget "Clerk" \*/ '
                   r"= \{.*?\n\t\t\};", settings, s, flags=re.S)
    if n != 2:
        sys.exit(f"expected 2 app build configurations, found {n}")

    # The extension is sandboxed, and the converter does NOT give it outgoing
    # network access. Its fetch to 127.0.0.1 then fails with no useful error and
    # the page just says the helper is not running. It is.
    def ext_settings(m):
        b = m.group(0)
        if "ENABLE_OUTGOING_NETWORK_CONNECTIONS" not in b:
            b = b.replace("\t\t\t\tENABLE_HARDENED_RUNTIME = YES;",
                          "\t\t\t\tENABLE_HARDENED_RUNTIME = YES;\n"
                          "\t\t\t\tENABLE_OUTGOING_NETWORK_CONNECTIONS = YES;")
        return developer_id(b)

    s, n = re.subn(r'/\* (?:Debug|Release) configuration for PBXNativeTarget '
                   r'"Clerk Extension" \*/ = \{.*?\n\t\t\};', ext_settings, s, flags=re.S)
    if n != 2:
        sys.exit(f"expected 2 extension build configurations, found {n}")

    s = add_sparkle(s)

    if s.count("{") != s.count("}"):
        sys.exit(f"braces unbalanced: {s.count('{')} vs {s.count('}')} - not written")

    open(PROJ, "w").write(s)
    print(f"project fixed: {len(ADD)} sources added, sandbox off, Dock icon on")


if __name__ == "__main__":
    main()
