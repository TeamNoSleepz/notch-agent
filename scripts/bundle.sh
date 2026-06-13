#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="NotchAgent"
BUNDLE="$PROJECT_DIR/$APP_NAME.app"

echo "Building $APP_NAME..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp ".build/release/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"

# Copy icons
cp "$PROJECT_DIR/Sources/NotchAgent/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Sources/NotchAgent/Resources/StatusBarIconTemplate.png" "$BUNDLE/Contents/Resources/StatusBarIconTemplate.png"

# Embed Sparkle.framework
mkdir -p "$BUNDLE/Contents/Frameworks"
SPARKLE_FW=$(find "$PROJECT_DIR/.build/artifacts" -name "Sparkle.framework" -not -path "*/dSYM/*" 2>/dev/null | head -1)
if [ -z "$SPARKLE_FW" ]; then
    echo "Error: Sparkle.framework not found. Run 'swift package resolve' first."
    exit 1
fi
cp -r "$SPARKLE_FW" "$BUNDLE/Contents/Frameworks/Sparkle.framework"

# Fix rpath so binary finds the embedded framework
install_name_tool -add_rpath "@executable_path/../Frameworks" "$BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true

cat > "$BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.notchagent.app</string>
    <key>CFBundleName</key>
    <string>NotchAgent</string>
    <key>CFBundleDisplayName</key>
    <string>NotchAgent</string>
    <key>CFBundleExecutable</key>
    <string>NotchAgent</string>
    <key>CFBundleVersion</key>
    <string>0.8</string>
    <key>CFBundleShortVersionString</key>
    <string>0.8</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/TeamNoSleepz/notch-agent/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>VpISw7UE9PCdwAARSJaHy3JuiW9pP1sOC91dAN5W8Qs=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
</dict>
</plist>
EOF

# Codesign — Sparkle's Autoupdate helper must share the same identity
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || true

echo "✓ Bundle created: $BUNDLE"
