#!/bin/bash
# The one way to build Clerk.
#
#   ./tools/build.sh            build and install to /Applications
#   ./tools/build.sh --no-install
#
# The Xcode project is GENERATED: safari-web-extension-converter reads
# `extension/` and writes `app/`, then tools/fix_project.py turns the AppKit
# skeleton it insists on making into the SwiftUI menu-bar app. So the project is
# thrown away and rebuilt every time, and `extension/` plus `app/Clerk/
# Clerk/{ClerkApp,SettingsView,Core}` are the only sources that matter.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFT="$ROOT/app/Clerk/Clerk"
KEEP="$(mktemp -d)"
cd "$ROOT"

# hold the hand-written Swift while the project is regenerated
cp -R "$SWIFT/Core" "$KEEP/Core"
cp "$SWIFT/ClerkApp.swift" "$SWIFT/SettingsView.swift" "$SWIFT/ShortcutRecorder.swift" "$KEEP/"
cp -R "$SWIFT/Assets.xcassets" "$KEEP/Assets.xcassets"

rm -rf app
xcrun safari-web-extension-converter extension \
  --project-location app --app-name "Clerk" \
  --bundle-identifier com.DNZ.clerk --macos-only --no-open --no-prompt --force \
  2>&1 | grep -vE "^(App|Platform|Language|Xcode|Warning|\t)" || true

cp -R "$KEEP/Core" "$SWIFT/Core"
cp "$KEEP/ClerkApp.swift" "$KEEP/SettingsView.swift" "$KEEP/ShortcutRecorder.swift" "$SWIFT/"
rm -rf "$SWIFT/Assets.xcassets" && cp -R "$KEEP/Assets.xcassets" "$SWIFT/Assets.xcassets"
rm -f "$SWIFT/AppDelegate.swift" "$SWIFT/ViewController.swift"
rm -rf "$SWIFT/Base.lproj" "$SWIFT/Resources"
rm -rf "$KEEP"

python3 tools/fix_project.py

xcodebuild -project app/Clerk/Clerk.xcodeproj -scheme Clerk \
  -configuration Release -derivedDataPath app/build \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=VWR39LZW5M build \
  2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | grep -v "^ " | sort -u

APP="app/build/Build/Products/Release/Clerk.app"

# Xcode leaves `get-task-allow` in the entitlements even with a Developer ID
# certificate, and notarisation refuses a build that has it. Re-sign both parts
# without it, innermost first. (Dropping it through
# CODE_SIGN_INJECT_BASE_ENTITLEMENTS deletes the whole entitlements file, sandbox
# and network access included, so it has to be done this way.)
ID="Developer ID Application: Summit Electronics LLC (VWR39LZW5M)"

# Sparkle ships PRE-SIGNED helpers inside its framework - Updater.app, Autoupdate
# and two XPC services, all signed by Sparkle's own team and without a secure
# timestamp. Notarisation rejects every one of them ("not signed with a valid
# Developer ID certificate"), so re-sign them with ours, innermost first. The
# framework bundle itself is signed last. Verified 2026-09-22: the first 0.0.1
# submission came back Invalid with exactly these paths.
SP="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SP" ]; then
  for part in \
    "$SP/Versions/B/XPCServices/Downloader.xpc" \
    "$SP/Versions/B/XPCServices/Installer.xpc" \
    "$SP/Versions/B/Updater.app/Contents/MacOS/Autoupdate" \
    "$SP/Versions/B/Updater.app" \
    "$SP/Versions/B/Autoupdate" \
    "$SP/Versions/B" ; do
    [ -e "$part" ] || continue
    # --preserve-metadata keeps each helper's own entitlements; they need them.
    codesign --force --options runtime --timestamp \
      --preserve-metadata=entitlements \
      --sign "$ID" "$part" 2>&1 | grep -v "replacing existing signature" || true
  done
fi

for part in "$APP/Contents/PlugIns/Clerk Extension.appex" "$APP"; do
  ENT="${TMPDIR:-/tmp}/clerk-ent-$$.plist"
  codesign -d --entitlements "$ENT" --xml "$part" 2>/dev/null
  /usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$ENT" 2>/dev/null || true
  codesign --force --options runtime --timestamp \
    --sign "$ID" --entitlements "$ENT" "$part" 2>&1 | grep -v "replacing existing signature" || true
  rm -f "$ENT"
done
codesign --verify --deep --strict "$APP" && echo "signature verifies"

# ALWAYS notarise before installing. An unnotarised build is refused by
# Gatekeeper, and Safari then drops the extension from its list without a word -
# which cost an evening on 2026-09-22. --no-install skips it.
if [ "${1:-}" != "--no-install" ]; then
  echo "notarising…"
  ZIP="${TMPDIR:-/tmp}/Clerk-notarize.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" \
    --key /Users/moshe/.private_keys/AuthKey_8YRH4XJ54M.p8 \
    --key-id 8YRH4XJ54M \
    --issuer 42d2ca38-3644-4d1e-8f77-dea9c6605306 \
    --wait
  xcrun stapler staple "$APP"
fi

if [ "${1:-}" != "--no-install" ]; then
  pkill -x Clerk 2>/dev/null || true
  sleep 1
  # Update the bundle IN PLACE. Deleting and re-copying gives it a new identity
  # every build, and Safari loses track of the extension - it vanished from the
  # Extensions list entirely on 2026-09-22 because of this.
  # ditto over the top, rather than delete-and-copy: a fresh bundle each build
  # gives Safari a new identity and the extension vanished from its Extensions
  # list entirely on 2026-09-22 because of that. ditto also keeps the stapled
  # notarisation ticket, which rsync drops.
  ditto app/build/Build/Products/Release/Clerk.app /Applications/Clerk.app
  # Do NOT `pluginkit -r` here. It hands the extension a new UUID, Safari treats
  # it as a different extension, and it drops out of the Extensions list - which
  # looked exactly like the extension breaking, twice. macOS picks up an updated
  # appex on its own. Only re-register by hand if it is genuinely missing:
  #   pluginkit -mA -p com.apple.Safari.web-extension | grep clerk

  # Safari lists ONE extension per copy of the app macOS has seen, so the build
  # output shows up beside the installed app and there appear to be two. Drop the
  # build copy from Launch Services; only /Applications should be known.
  LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$LSR" -u "$ROOT/app/build/Build/Products/Release/Clerk.app" 2>/dev/null || true

  # Never leave it down: a dead helper looks exactly like a broken extension.
  for i in 1 2 3; do
    open -a /Applications/Clerk.app
    sleep 2
    nc -z 127.0.0.1 8771 2>/dev/null && break
  done
  if nc -z 127.0.0.1 8771 2>/dev/null; then
    echo "installed and running"
  else
    echo "installed, but the helper will NOT start - open the app and check Setup"
    exit 1
  fi
fi
