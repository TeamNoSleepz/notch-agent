#!/bin/bash
set -e

INSTALL_DIR="$HOME/.notch-agent"
REPO_URL="https://github.com/TeamNoSleepz/notch-agent.git"

echo "=== NotchAgent Installer ==="
echo ""

# Check for Xcode Command Line Tools
if ! xcode-select -p &>/dev/null; then
    echo "Xcode Command Line Tools not found."
    echo "Run: xcode-select --install"
    echo "Then re-run this installer."
    exit 1
fi

# Clone or update repo
if [ -d "$INSTALL_DIR/.git" ]; then
    echo "Updating existing install at $INSTALL_DIR..."
    git -C "$INSTALL_DIR" pull --ff-only
else
    echo "Cloning to $INSTALL_DIR..."
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

echo ""

# Run setup from the cloned repo
"$INSTALL_DIR/setup.sh"
