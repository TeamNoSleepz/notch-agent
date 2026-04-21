#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="VibeNotch"
BUNDLE="$PROJECT_DIR/$APP_NAME.app"

echo "Building $APP_NAME..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp ".build/release/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.vibenotch.app</string>
    <key>CFBundleName</key>
    <string>VibeNotch</string>
    <key>CFBundleDisplayName</key>
    <string>VibeNotch</string>
    <key>CFBundleExecutable</key>
    <string>VibeNotch</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
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
</dict>
</plist>
EOF

# Ad-hoc codesign so macOS will launch it
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || true

echo "✓ Bundle created: $BUNDLE"
