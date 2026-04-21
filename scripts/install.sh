#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="VibeNotch"
BUNDLE="$PROJECT_DIR/$APP_NAME.app"

"$SCRIPT_DIR/bundle.sh"

echo "Installing to /Applications..."
rm -rf "/Applications/$APP_NAME.app"
cp -r "$BUNDLE" "/Applications/$APP_NAME.app"

echo "✓ Installed to /Applications/$APP_NAME.app"
echo ""
echo "Launch it once, then enable 'Launch at Login' from the menu bar icon."
