# Sound Support Design

**Date:** 2026-04-23

## Overview

Play a sound when Claude interrupts (needs input) and when Claude finishes work. Each event has an independent on/off toggle and a sound picker. Volume follows system volume — no in-app control.

## Triggers

| Event | State transition | Default sound |
|-------|-----------------|---------------|
| Interrupt | any → `.awaiting` | Ping |
| Finish | `.working` or `.awaiting` → `.idle` | Glass |

## Data Model

Four new `@Published` properties added to `AppPreferences`, persisted via UserDefaults:

```swift
@Published var interruptSoundEnabled: Bool   // key: vibenotch.interruptSoundEnabled, default: true
@Published var interruptSoundName: String    // key: vibenotch.interruptSoundName, default: "Ping"
@Published var finishSoundEnabled: Bool      // key: vibenotch.finishSoundEnabled, default: true
@Published var finishSoundName: String       // key: vibenotch.finishSoundName, default: "Glass"

static let systemSounds = [
    "Basso","Blow","Bottle","Frog","Funk","Glass",
    "Hero","Morse","Ping","Pop","Purr","Sosumi","Submarine","Tink"
]
```

## Playback Logic

In `ClaudeState`, detect transition old → new in the existing `DispatchQueue.main.async` block where `pattern` is assigned:

```swift
private func playSound(for old: IndicatorPattern, to new: IndicatorPattern) {
    let prefs = AppPreferences.shared
    switch (old, new) {
    case (_, .awaiting):
        guard prefs.interruptSoundEnabled else return
        NSSound(named: NSSound.Name(prefs.interruptSoundName))?.play()
    case (.working, .idle), (.awaiting, .idle):
        guard prefs.finishSoundEnabled else return
        NSSound(named: NSSound.Name(prefs.finishSoundName))?.play()
    default:
        break
    }
}
```

No new imports — `NSSound` is in AppKit, already imported.

## Settings UI

New sound section added to `GeneralSettingsView` (no new tab). Each event row: label + `Toggle` + `Picker` (inline style). Picker is disabled when toggle is off. Selecting a sound plays it immediately as a preview.

```
[ Sound ]
──────────────────────────────────────
Interrupt   ●  [Ping   ▾]
Finish      ●  [Glass  ▾]
```

Window height bumped from 260pt to ~340pt to accommodate the new section.

## Files Changed

| File | Change |
|------|--------|
| `SettingsWindowController.swift` | Add 4 prefs to `AppPreferences`; add sound UI section to `GeneralSettingsView`; increase window height |
| `StateWatcher.swift` | Add `playSound(for:to:)` method; call on pattern transition |
