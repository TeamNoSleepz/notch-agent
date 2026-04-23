# VibeNotch

A lightweight macOS menu bar app that turns your MacBook's notch into a live Claude Code status indicator.

While Claude is thinking, running tools, or waiting for input, a 3×3 pixel grid animates inside your notch so you always know what's happening — without switching to the terminal.

---

## What it looks like

A slim panel sits flush inside the physical notch. Three states:

| State | Animation | Color |
|---|---|---|
| **Idle** | Single center dot | Grey |
| **Working** | Animated trail (randomized pattern) | Amber/cream with glow |
| **Awaiting input** | Pulsing corner cells | Red |

The right side of the notch shows a live count of running `claude` processes. The menu bar item uses a grid icon that opens status and settings.

---

## Install

**Requirements:** macOS 13+, Xcode Command Line Tools

```bash
xcode-select --install  # skip if already installed
```

```bash
git clone https://github.com/TeamNoSleepz/vibe-notch
cd vibe-notch
./setup.sh
```

Open `/Applications/VibeNotch.app`, then click the menu bar icon and enable **Launch at Login**.

### What `setup.sh` does

1. Builds a release binary with `swift build -c release`, wraps it into `VibeNotch.app`, and installs it to `/Applications`
2. Injects Claude Code hooks into `~/.claude/settings.json` — 8 events pointing at `hooks/vibe-notch-hook.py`

---

## How it works

```
Claude Code
    │  hook fires on every event (PreToolUse, Stop, etc.)
    ▼
hooks/vibe-notch-hook.py
    │  sends JSON payload to /tmp/vibe-notch.sock
    │  fire-and-forget, exits immediately
    ▼
VibeNotch.app
    │  Unix socket server reads event → maps to state
    ▼
Notch panel + menu bar icon
```

**Hook events → states:**

| Event | State |
|---|---|
| `PreToolUse`, `UserPromptSubmit`, `PostToolUse` | Working |
| `Stop`, `SessionStart`, `SessionEnd`, `PermissionRequest` | Awaiting input |

**Notch panel** — an `NSPanel` at `mainMenu + 3` window level, sized to the physical notch using `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. Mouse events pass through.

**Indicator** — 3×3 grid of 5×5pt cells. Five animation patterns (snake, single horizontal, single vertical, staggering horizontal, staggering vertical) — one picked randomly each time Claude starts working.

---

## Preferences

Click the menu bar icon → **Preferences** to configure:

- **Color palette** — Default (amber), Neon (green/blue), Pastel
- **Sounds** — optional chime when Claude interrupts you or finishes a task (uses system sounds, routed through AVAudioPlayer for Bluetooth compatibility)

---

## Uninstall

```bash
./uninstall.sh
```

Removes hooks from `~/.claude/settings.json`, deletes `/Applications/VibeNotch.app`, and cleans up `/tmp/vibe-notch*`.

> Run `uninstall.sh` before deleting the repo. If you delete the repo first, the dead hook paths in `~/.claude/settings.json` will cause errors on every Claude session. Fix by removing the `vibe-notch-hook` entries manually from that file.

---

## Development

```bash
swift build && .build/debug/VibeNotch
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
vibe-notch/
├── Sources/VibeNotch/
│   ├── main.swift                      # NSPanel, NSStatusItem, IndicatorView, AppDelegate
│   ├── StateWatcher.swift              # ClaudeState — Unix socket server + agent counter
│   └── SettingsWindowController.swift  # Preferences UI, AppPreferences, color palettes
├── hooks/
│   └── vibe-notch-hook.py              # Claude Code hook — sends events via Unix socket
├── scripts/
│   ├── bundle.sh                       # Creates VibeNotch.app bundle
│   └── install.sh                      # bundle.sh + copy to /Applications
├── setup.sh                            # One-command install + hook wiring
├── uninstall.sh                        # Full cleanup
└── Package.swift
```

---

## Requirements

- macOS 13 Ventura or later
- Claude Code CLI
- Xcode Command Line Tools
