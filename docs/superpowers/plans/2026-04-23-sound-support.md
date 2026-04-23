# Sound Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Play a configurable system sound when Claude interrupts (→ awaiting) and when Claude finishes (→ idle), with per-event on/off toggles and sound pickers in Preferences.

**Architecture:** Add 4 new UserDefaults-backed properties to `AppPreferences`. Detect state transitions in `ClaudeState.acceptConnection` and play `NSSound`. Add a sound section to `GeneralSettingsView`.

**Tech Stack:** Swift, AppKit (`NSSound`), SwiftUI, UserDefaults

---

### Task 1: Add sound preferences to AppPreferences

**Files:**
- Modify: `Sources/VibeNotch/SettingsWindowController.swift`

- [ ] **Step 1: Add `systemSounds` static constant and 4 new `@Published` properties**

Replace the existing `AppPreferences` class body (from `static let presets` through the closing `}`) with this full replacement. The new properties go after `paletteIndex`:

```swift
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    static let presets: [ColorPalette] = [
        ColorPalette(
            name: "Default",
            idle: Color(white: 0.35),
            working: Color(red: 1, green: 0.4, blue: 0),
            awaiting: Color(red: 1, green: 0.2, blue: 0.2)
        ),
        ColorPalette(
            name: "Neon",
            idle: Color(white: 0.4),
            working: Color(red: 0, green: 1, blue: 0.4),
            awaiting: Color(red: 0.4, green: 0.4, blue: 1)
        ),
        ColorPalette(
            name: "Pastel",
            idle: Color(white: 0.5),
            working: Color(red: 1, green: 0.75, blue: 0.5),
            awaiting: Color(red: 0.8, green: 0.6, blue: 1)
        ),
    ]

    static let systemSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
        "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    @Published var paletteIndex: Int {
        didSet { UserDefaults.standard.set(paletteIndex, forKey: "vibenotch.paletteIndex") }
    }

    @Published var interruptSoundEnabled: Bool {
        didSet { UserDefaults.standard.set(interruptSoundEnabled, forKey: "vibenotch.interruptSoundEnabled") }
    }

    @Published var interruptSoundName: String {
        didSet { UserDefaults.standard.set(interruptSoundName, forKey: "vibenotch.interruptSoundName") }
    }

    @Published var finishSoundEnabled: Bool {
        didSet { UserDefaults.standard.set(finishSoundEnabled, forKey: "vibenotch.finishSoundEnabled") }
    }

    @Published var finishSoundName: String {
        didSet { UserDefaults.standard.set(finishSoundName, forKey: "vibenotch.finishSoundName") }
    }

    var selectedPalette: ColorPalette { Self.presets[paletteIndex] }

    private init() {
        let saved = UserDefaults.standard.integer(forKey: "vibenotch.paletteIndex")
        paletteIndex = saved < Self.presets.count ? saved : 0

        let ud = UserDefaults.standard

        if ud.object(forKey: "vibenotch.interruptSoundEnabled") != nil {
            interruptSoundEnabled = ud.bool(forKey: "vibenotch.interruptSoundEnabled")
        } else {
            interruptSoundEnabled = true
        }
        interruptSoundName = ud.string(forKey: "vibenotch.interruptSoundName") ?? "Ping"

        if ud.object(forKey: "vibenotch.finishSoundEnabled") != nil {
            finishSoundEnabled = ud.bool(forKey: "vibenotch.finishSoundEnabled")
        } else {
            finishSoundEnabled = true
        }
        finishSoundName = ud.string(forKey: "vibenotch.finishSoundName") ?? "Glass"
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/nikpavic/vibe-notch && swift build 2>&1
```

Expected: `Build complete!` with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/VibeNotch/SettingsWindowController.swift
git commit -m "Add sound preferences to AppPreferences"
```

---

### Task 2: Add playback logic to ClaudeState

**Files:**
- Modify: `Sources/VibeNotch/StateWatcher.swift`

- [ ] **Step 1: Add `playSound(for:to:)` method to `ClaudeState`**

Add this method inside the `ClaudeState` class, after the `pollAgentCount` method (before the closing `}`):

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

- [ ] **Step 2: Update the `DispatchQueue.main.async` block in `acceptConnection` to call `playSound`**

Find this existing block (lines 98–100):

```swift
DispatchQueue.main.async { [weak self] in
    if self?.pattern != next { self?.pattern = next }
}
```

Replace it with:

```swift
DispatchQueue.main.async { [weak self] in
    guard let self = self else { return }
    let prev = self.pattern
    if prev != next {
        self.pattern = next
        self.playSound(for: prev, to: next)
    }
}
```

- [ ] **Step 3: Add `AppKit` import to StateWatcher.swift** (needed for `NSSound`)

`AppKit` is not currently imported in `StateWatcher.swift`. Add it at the top:

```swift
import AppKit
import SwiftUI
import Combine
import Foundation
import Darwin
```

- [ ] **Step 4: Verify build**

```bash
cd /Users/nikpavic/vibe-notch && swift build 2>&1
```

Expected: `Build complete!` with no errors.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeNotch/StateWatcher.swift
git commit -m "Play sound on state transitions in ClaudeState"
```

---

### Task 3: Add sound section to Settings UI

**Files:**
- Modify: `Sources/VibeNotch/SettingsWindowController.swift`

- [ ] **Step 1: Add `SoundRowView` helper**

Add this view before the `GeneralSettingsView` struct:

```swift
struct SoundRowView: View {
    let label: String
    @Binding var enabled: Bool
    @Binding var soundName: String

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 70, alignment: .leading)
            Toggle("", isOn: $enabled)
                .toggleStyle(.switch)
                .labelsHidden()
            Picker("", selection: $soundName) {
                ForEach(AppPreferences.systemSounds, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
            .disabled(!enabled)
            .onChange(of: soundName) { newName in
                NSSound(named: NSSound.Name(newName))?.play()
            }
        }
    }
}
```

- [ ] **Step 2: Add sound section to `GeneralSettingsView`**

In `GeneralSettingsView.body`, after the existing `if hasBundle { Divider() ... }` block and before `Spacer()`, add:

```swift
Divider()

VStack(alignment: .leading, spacing: 8) {
    Text("Sound")
        .font(.headline)
    SoundRowView(
        label: "Interrupt",
        enabled: $prefs.interruptSoundEnabled,
        soundName: $prefs.interruptSoundName
    )
    SoundRowView(
        label: "Finish",
        enabled: $prefs.finishSoundEnabled,
        soundName: $prefs.finishSoundName
    )
}
```

- [ ] **Step 3: Bump the settings window height**

In `SettingsView.body`, change the frame modifier:

```swift
// Before:
.frame(width: 380, height: 260)

// After:
.frame(width: 380, height: 340)
```

Also update the window `contentRect` in `SettingsWindowController.showWindow()`:

```swift
// Before:
let w = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),

// After:
let w = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 380, height: 340),
```

- [ ] **Step 4: Verify build**

```bash
cd /Users/nikpavic/vibe-notch && swift build 2>&1
```

Expected: `Build complete!` with no errors.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeNotch/SettingsWindowController.swift
git commit -m "Add sound section to Preferences UI"
```

---

### Task 4: Install and manually verify

**Files:** none

- [ ] **Step 1: Build and install**

```bash
cd /Users/nikpavic/vibe-notch && ./setup.sh
```

Expected: builds, installs to `/Applications/VibeNotch.app`, launches.

- [ ] **Step 2: Open Preferences and verify sound section**

Click the `●` menu bar dot → Preferences. Confirm:
- "Sound" section appears below the Launch at Login toggle
- "Interrupt" and "Finish" rows each have a toggle and a sound picker
- Both toggles default to on
- Interrupt picker defaults to "Ping", Finish picker defaults to "Glass"
- Changing a sound picker plays the selected sound immediately

- [ ] **Step 3: Test interrupt sound**

In a terminal, run Claude Code and trigger a permission prompt. Confirm "Ping" (or selected sound) plays when the notch indicator switches to awaiting (red corners).

- [ ] **Step 4: Test finish sound**

Let Claude finish a task. Confirm "Glass" (or selected sound) plays when the indicator returns to idle.

- [ ] **Step 5: Test toggles**

Disable interrupt sound toggle. Trigger a permission prompt — confirm no sound plays. Re-enable — confirm sound returns.

- [ ] **Step 6: Test persistence**

Change sounds, quit VibeNotch, reopen — confirm selections are preserved.
