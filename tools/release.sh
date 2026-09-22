#!/bin/bash
# Publish a build for Sparkle to pick up.
#
#   ./tools/release.sh            # build, notarise, sign, write the appcast, deploy
#   ./tools/release.sh --local    # everything except the Cloudflare deploy
#
# Sparkle checks https://dancykier.com/clerk/appcast.xml once a day. The site
# is the `dancykier` Cloudflare Pages project; its source is Apps/Web/apps-hub.
#
# The signature is made with openssl, NOT with Sparkle's own sign_update. That
# tool rejects a valid 64-byte key with a self-contradictory error ("must be 64
# bytes or 96 bytes … Instead it is 64 bytes decoded"), and generate_keys hangs
# on a keychain dialog. openssl signs the same ed25519 key and Sparkle accepts
# the result.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE=/Users/moshe/Apps/Web/apps-hub
OUT="$SITE/clerk"
KEY="$ROOT/tools/sparkle/eddsa_private.pem"
FEED="https://dancykier.com/clerk"

cd "$ROOT"
# Raise the build number every release. Sparkle compares CFBundleVersion, so an
# installed copy only updates when this goes up. MARKETING_VERSION is never
# touched here - that is Moshe's call.
N=$(cat tools/build_number)
echo $((N + 1)) > tools/build_number
echo "build $((N + 1))"
"$ROOT/tools/build.sh"          # builds, signs, notarises, staples, installs

APP=/Applications/Clerk.app
PLIST="$APP/Contents/Info.plist"
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
ZIP="$OUT/Clerk-$VER.zip"

mkdir -p "$OUT"
rm -f "$ZIP"
# --sequesterRsrc --keepParent is what Sparkle expects of an app zip.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
SIZE=$(stat -f%z "$ZIP")

SIG=$(openssl pkeyutl -sign -inkey "$KEY" -rawin -in "$ZIP" | base64)
echo "signed $ZIP ($SIZE bytes)"

DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
NOTES="$OUT/notes-$VER.html"
[ -f "$NOTES" ] || cat > "$NOTES" <<HTML
<html><body>
<h2>Clerk $VER</h2>
<p>Fills forms from your own details, on this Mac.</p>
</body></html>
HTML

cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Clerk</title>
    <link>$FEED/appcast.xml</link>
    <description>Clerk updates</description>
    <language>en</language>
    <item>
      <title>Version $VER</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VER</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>$FEED/notes-$VER.html</sparkle:releaseNotesLink>
      <enclosure url="$FEED/Clerk-$VER.zip"
                 length="$SIZE"
                 type="application/octet-stream"
                 sparkle:edSignature="$SIG" />
    </item>
  </channel>
</rss>
XML
echo "wrote $OUT/appcast.xml"

if [ "${1:-}" = "--local" ]; then
  echo "local only - not deployed"
  exit 0
fi

export CLOUDFLARE_API_TOKEN=$(security find-generic-password -s cloudflare_api_token -w)
export CLOUDFLARE_ACCOUNT_ID=28b22d2560f6428a26cd8220fc5a4393
cd "$SITE"
# A git push publishes nothing - these are direct-upload Pages projects.
npx -y wrangler@latest pages deploy . --project-name dancykier \
  --branch main --commit-dirty=true
echo "live: $FEED/appcast.xml"
