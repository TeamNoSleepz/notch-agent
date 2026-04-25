# NotchAgent

A lightweight macOS menu bar app that turns your MacBook's notch into a live Claude Code status indicator.

While Claude is thinking, running tools, or waiting for input, a 3×3 pixel grid animates inside your notch so you always know what's happening — without switching to the terminal.

---

## What it looks like

A slim panel sits flush inside the physical notch. Three states:

| State | Animation | Color |
|---|---|---|
| **Idle** | Slow animated trail (same pattern as Working) | Grey |
| **Working** | Animated trail (randomized pattern) with glow | Cream with orange glow |
| **Awaiting input** | Trail cycling down center column | Red |

The right side of the notch shows a live count of running `claude` processes. The menu bar item opens status and settings.

---

## Install

**Requirements:** macOS 13+, Xcode Command Line Tools

```bash
xcode-select --install  # skip if already installed
```

```bash
git clone https://github.com/TeamNoSleepz/notch-agent
cd notch-agent
./setup.sh
```

Open `/Applications/NotchAgent.app`, then click the menu bar icon and enable **Launch at Login**.

### What `setup.sh` does

1. Builds a release binary with `swift build -c release`, wraps it into `NotchAgent.app`, and installs it to `/Applications`
2. Injects Claude Code hooks into `~/.claude/settings.json` — 8 events pointing at `hooks/notch-agent-hook.py`

---

## How it works

```
Claude Code
    │  hook fires on every event (PreToolUse, Stop, etc.)
    ▼
hooks/notch-agent-hook.py
    │  sends JSON payload to /tmp/notch-agent.sock
    │  fire-and-forget, exits immediately
    ▼
NotchAgent.app
    │  Unix socket server reads event → maps to state
    ▼
Notch panel + menu bar icon
```

**Hook events → states:**

| Event | State |
|---|---|
| `PreToolUse`, `UserPromptSubmit`, `PostToolUse`, `PostToolUseFailure`, `SubagentStart`, `SubagentStop`, `PreCompact`, `PostCompact` | Working |
| `Stop`, `StopFailure`, `SessionStart`, `PermissionRequest`, `Notification` (idle) | Awaiting input |
| `SessionEnd`, `Notification` (other) | Idle |

**Notch panel** — an `NSPanel` at `mainMenu + 3` window level, sized to the physical notch using `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. Mouse events pass through.

**Indicator** — 3×3 grid of 5×5pt cells. Five animation patterns (snake, single horizontal, single vertical, staggering horizontal, staggering vertical) — one picked randomly each time Claude starts working.

---

## Settings

Click the menu bar icon → **Settings** to configure:

- **Color palette** — Default (cream/red/grey)
- **Sounds** — optional chime when Claude interrupts you or finishes a task (uses system sounds, routed through AVAudioPlayer for Bluetooth compatibility)

Click **Submit Feedback** to open a GitHub issue.

---

## Uninstall

```bash
./uninstall.sh
```

Removes hooks from `~/.claude/settings.json`, deletes `/Applications/NotchAgent.app`, and cleans up `/tmp/notch-agent*`.

> Run `uninstall.sh` before deleting the repo. If you delete the repo first, the dead hook paths in `~/.claude/settings.json` will cause errors on every Claude session. Fix by removing the `notch-agent-hook` entries manually from that file.

---

## Development

```bash
swift build && .build/debug/NotchAgent
```

Auto-rebuild on file changes:

```bash
./dev.sh
```

Build the `.app` bundle without installing:

```bash
./scripts/bundle.sh
```

---

## Project structure

```
notch-agent/
├── Sources/NotchAgent/
│   ├── main.swift                      # NSPanel, NSStatusItem, IndicatorView, AppDelegate
│   ├── StateWatcher.swift              # ClaudeState — Unix socket server + agent counter
│   ├── SettingsWindowController.swift  # Settings UI, AppPreferences, color palettes
│   └── Resources/                      # App icon, status bar icon
├── hooks/
│   ├── notch-agent-hook.py             # Claude Code hook — sends events via Unix socket
│   ├── notch-agent-hook.sh             # Shell wrapper for the hook
│   └── watch.sh                        # File watcher for dev rebuilds
├── scripts/
│   ├── bundle.sh                       # Creates NotchAgent.app bundle
│   └── install.sh                      # bundle.sh + copy to /Applications
├── docs/
├── setup.sh                            # One-command install + hook wiring
├── uninstall.sh                        # Full cleanup
├── dev.sh                              # Auto-rebuild on file changes
└── Package.swift
```

---

## Requirements

- macOS 13 Ventura or later
- Claude Code CLI
- Xcode Command Line Tools
