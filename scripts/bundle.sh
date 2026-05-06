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
    <string>0.3</string>
    <key>CFBundleShortVersionString</key>
    <string>0.3</string>
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
</dict>
</plist>
EOF

# Ad-hoc codesign so macOS will launch it
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || true

echo "✓ Bundle created: $BUNDLE"

# Install to /Applications
rm -rf /Applications/NotchAgent.app
cp -r "$BUNDLE" /Applications/NotchAgent.app
echo "✓ Installed to /Applications/NotchAgent.app"
