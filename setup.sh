#!/bin/bash
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$REPO_DIR/hooks/vibe-notch-hook.sh"
SETTINGS="$HOME/.claude/settings.json"

echo "=== VibeNotch Setup ==="
echo ""

# 1. Install the app
echo "Step 1: Building and installing VibeNotch.app..."
"$REPO_DIR/scripts/install.sh"
echo ""

# 2. Wire up Claude Code hooks
echo "Step 2: Installing Claude Code hooks..."

mkdir -p "$HOME/.claude"

python3 - "$SETTINGS" "$HOOK" << 'PYEOF'
import sys, json, os

settings_path = sys.argv[1]
hook_path = sys.argv[2]

if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
else:
    settings = {}

hooks = settings.setdefault("hooks", {})

events = {
    "UserPromptSubmit": "user-prompt",
    "PreToolUse":       "pre-tool",
    "PostToolUse":      "post-tool",
    "Stop":             "stop",
    "SessionStart":     "session-start",
}

added = []
for event, arg in events.items():
    command = f"{hook_path} {arg}"
    entries = hooks.setdefault(event, [])
    already = any(
        h.get("command") == command
        for entry in entries
        for h in entry.get("hooks", [])
    )
    if not already:
        entries.append({"matcher": "*", "hooks": [{"type": "command", "command": command}]})
        added.append(event)

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)

if added:
    print(f"  Added hooks for: {', '.join(added)}")
else:
    print("  Hooks already installed — nothing to do.")
PYEOF

echo ""
echo "=== Done! ==="
echo ""
echo "Open /Applications/VibeNotch.app to start."
echo "You'll see a ● dot in your menu bar tracking Claude's state."
echo "Click it to enable 'Launch at Login'."
