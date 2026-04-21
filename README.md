# VibeNotch

A lightweight macOS app that turns your MacBook's notch and menu bar into a live Claude Code status indicator.

While Claude is thinking or running tools, a colored dot glows in your notch and menu bar so you always know what it's doing — without looking at the terminal.

---

## How it looks

**Notch overlay** — a slim panel sits inside the physical notch, invisible at rest:

| State | Notch dot | Menu bar dot |
|-------|-----------|--------------|
| Idle | dim grey `●` | dim grey `●` |
| Working (tool call) | orange `●` | orange `●` |
| Awaiting your input | red `●` | red `●` |

The notch panel also shows a small agent counter (number of `claude` processes running).

---

## How it works

```
Claude Code
    │
    │  hooks fire on every event
    ▼
hooks/vibe-notch-hook.sh
    │
    │  writes one word to /tmp/vibe-notch
    │  e.g. "thinking" | "tool" | "awaiting" | "idle"
    ▼
VibeNotch.app
    │
    │  polls /tmp/vibe-notch every 300ms
    │  updates SwiftUI state → repaints dot
    ▼
Notch overlay + Menu bar dot
```

### The hook

`setup.sh` installs five Claude Code hooks into `~/.claude/settings.json`:

| Hook event | Written to `/tmp/vibe-notch` |
|------------|------------------------------|
| `UserPromptSubmit` | `thinking` |
| `PreToolUse` | `tool` |
| `PostToolUse` | `thinking` |
| `Stop` | `awaiting` (if output ends with a question), else `idle` |
| `SessionStart` | `idle` |

### The app

- **Notch panel** — an `NSPanel` sitting at `mainMenu + 3` window level, sized and centered over the physical notch. Passes all mouse events through so it never interferes with clicks.
- **Menu bar item** — an `NSStatusItem` whose `●` title is re-colored via `NSAttributedString` whenever the state changes (using a Combine publisher).
- **Agent counter** — `pgrep -x claude` runs every 2 seconds on a background thread to count running Claude processes.
- **Launch at Login** — uses `SMAppService` (macOS 13+), available from the menu bar menu once installed as a `.app` bundle.

---

## Install

**Requirements:** macOS 13+, Xcode Command Line Tools

```bash
xcode-select --install   # skip if already installed
```

```bash
git clone https://github.com/TeamNoSleepz/vibe-notch
cd vibe-notch
./setup.sh
```

Then open `/Applications/VibeNotch.app`. Click the `●` in the menu bar and enable **Launch at Login** so it starts automatically.

### What `setup.sh` does

1. Runs `scripts/install.sh` — builds a release binary with `swift build -c release`, wraps it into `VibeNotch.app` with a proper `Info.plist` and ad-hoc codesign, copies it to `/Applications`.
2. Patches `~/.claude/settings.json` — injects the five Claude Code hooks pointing at `hooks/vibe-notch-hook.sh`. Idempotent; safe to re-run.

---

## Manual hook setup

If you'd rather wire the hooks yourself, add these to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [{"matcher": "*", "hooks": [{"type": "command", "command": "/path/to/vibe-notch/hooks/vibe-notch-hook.sh user-prompt"}]}],
    "PreToolUse":       [{"matcher": "*", "hooks": [{"type": "command", "command": "/path/to/vibe-notch/hooks/vibe-notch-hook.sh pre-tool"}]}],
    "PostToolUse":      [{"matcher": "*", "hooks": [{"type": "command", "command": "/path/to/vibe-notch/hooks/vibe-notch-hook.sh post-tool"}]}],
    "Stop":             [{"matcher": "*", "hooks": [{"type": "command", "command": "/path/to/vibe-notch/hooks/vibe-notch-hook.sh stop"}]}],
    "SessionStart":     [{"matcher": "*", "hooks": [{"type": "command", "command": "/path/to/vibe-notch/hooks/vibe-notch-hook.sh session-start"}]}]
  }
}
```

Replace `/path/to/vibe-notch` with the actual clone path.

---

## Development

```bash
swift build && .build/debug/VibeNotch
```

Or use the dev script for auto-rebuild on file changes:

```bash
./dev.sh
```

To rebuild the `.app` bundle without installing:

```bash
./scripts/bundle.sh
```

---

## Project structure

```
vibe-notch/
├── Sources/VibeNotch/
│   ├── main.swift          # NSPanel, NSStatusItem, AppDelegate
│   └── StateWatcher.swift  # ClaudeState — polls /tmp/vibe-notch
├── hooks/
│   └── vibe-notch-hook.sh  # Claude Code hook script
├── scripts/
│   ├── bundle.sh           # Creates VibeNotch.app
│   └── install.sh          # bundle.sh + copy to /Applications
├── setup.sh                # One-command install + hook wiring
└── Package.swift
```
