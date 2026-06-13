#!/bin/bash
set -e

VERSION="$1"
if [ -z "$VERSION" ]; then
    echo "Usage: ./scripts/release.sh <version>"
    echo "Example: ./scripts/release.sh 0.9"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SIGN_UPDATE="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update"

cd "$PROJECT_DIR"

echo "=== NotchAgent Release v$VERSION ==="
echo ""

# 1. Bump version in bundle.sh
echo "Step 1: Bumping version to $VERSION..."
sed -i '' "s/<string>[0-9]*\.[0-9]*<\/string>  *<!-- CFBundleVersion -->/<string>$VERSION<\/string>  <!-- CFBundleVersion -->/" scripts/bundle.sh 2>/dev/null || true
# Replace both CFBundleVersion and CFBundleShortVersionString in bundle.sh
perl -i '' -0pe "s|(<key>CFBundleVersion</key>\s*<string>)[^<]*(</string>)|\${1}${VERSION}\${2}|g" scripts/bundle.sh
perl -i '' -0pe "s|(<key>CFBundleShortVersionString</key>\s*<string>)[^<]*(</string>)|\${1}${VERSION}\${2}|g" scripts/bundle.sh

# 2. Build and install
echo "Step 2: Building..."
"$SCRIPT_DIR/bundle.sh"

# 3. Zip the app
echo ""
echo "Step 3: Zipping..."
rm -f "$PROJECT_DIR/NotchAgent.zip"
ditto -c -k --sequesterRsrc --keepParent "$PROJECT_DIR/NotchAgent.app" "$PROJECT_DIR/NotchAgent.zip"

# 4. Sign with Sparkle
echo "Step 4: Signing..."
if [ ! -f "$SIGN_UPDATE" ]; then
    echo "Error: sign_update not found. Run 'swift package resolve' first."
    exit 1
fi
SIGN_OUTPUT=$("$SIGN_UPDATE" "$PROJECT_DIR/NotchAgent.zip" 2>&1)
echo "  $SIGN_OUTPUT"
ED_SIG=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(echo "$SIGN_OUTPUT" | grep -o 'length="[^"]*"' | cut -d'"' -f2)

if [ -z "$ED_SIG" ] || [ -z "$LENGTH" ]; then
    echo "Error: Failed to extract signature from sign_update output."
    exit 1
fi

# 5. Update appcast.xml — prepend new item before existing items
echo "Step 5: Updating appcast.xml..."
PUBDATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
NEW_ITEM="
        <item>
            <title>Version $VERSION</title>
            <sparkle:version>$VERSION</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <pubDate>$PUBDATE</pubDate>
            <enclosure
                url=\"https://github.com/TeamNoSleepz/notch-agent/releases/download/v${VERSION}/NotchAgent.zip\"
                sparkle:version=\"$VERSION\"
                sparkle:edSignature=\"$ED_SIG\"
                length=\"$LENGTH\"
                type=\"application/octet-stream\"/>
        </item>
"
# Insert new item after <language> line
perl -i '' -0pe "s|(<language>en</language>)|\$1${NEW_ITEM}|" appcast.xml

# 6. Commit and push
echo "Step 6: Committing..."
git add scripts/bundle.sh appcast.xml
git commit -m "Release v$VERSION"
git push origin main

# 7. Create GitHub release
echo "Step 7: Creating GitHub release..."
gh release create "v$VERSION" "$PROJECT_DIR/NotchAgent.zip" \
    --title "v$VERSION" \
    --notes "See [appcast.xml](https://github.com/TeamNoSleepz/notch-agent/blob/main/appcast.xml) for details."

echo ""
echo "=== Done! v$VERSION released ==="
echo "Existing users will be notified automatically by Sparkle within 24h."
