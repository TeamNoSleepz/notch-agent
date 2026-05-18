#!/bin/bash
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$REPO_DIR/hooks/notch-agent-hook"
SETTINGS="$HOME/.claude/settings.json"

echo "=== NotchAgent Uninstall ==="
echo ""

# 1. Remove hooks from ~/.claude/settings.json
if [ -f "$SETTINGS" ]; then
    echo "Removing Claude Code hooks..."
    python3 - "$SETTINGS" "$HOOK" << 'PYEOF'
import sys, json

settings_path = sys.argv[1]
hook_path = sys.argv[2]

with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.get("hooks", {})
removed = []

for event, entries in hooks.items():
    before = len(entries)
    hooks[event] = [
        entry for entry in entries
        if not any(hook_path in h.get("command", "") for h in entry.get("hooks", []))
    ]
    if len(hooks[event]) < before:
        removed.append(event)

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)

if removed:
    print(f"  Removed hooks for: {', '.join(removed)}")
else:
    print("  No NotchAgent hooks found.")
PYEOF
else
    echo "  No ~/.claude/settings.json found — nothing to do."
fi

# 2. Remove the app
if [ -d "/Applications/NotchAgent.app" ]; then
    echo "Removing /Applications/NotchAgent.app..."
    rm -rf "/Applications/NotchAgent.app"
    echo "  Done."
else
    echo "  NotchAgent.app not found in /Applications."
fi

# 3. Remove Launch at Login if registered
if python3 -c "import subprocess; subprocess.run(['osascript', '-e', ''], check=True)" 2>/dev/null; then
    :
fi

# 4. Clean up tmp files
rm -f /tmp/notch-agent /tmp/notch-agent-log

# 5. Remove install dir (curl installs only)
if [ -d "$HOME/.notch-agent" ]; then
    echo "Removing $HOME/.notch-agent..."
    rm -rf "$HOME/.notch-agent"
    echo "  Done."
fi

echo ""
echo "=== Done. NotchAgent has been removed. ==="
