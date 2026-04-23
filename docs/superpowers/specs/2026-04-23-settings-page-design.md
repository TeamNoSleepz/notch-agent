# Settings Page Design

**Date:** 2026-04-23  
**Project:** VibeNotch  
**Status:** Approved

## Overview

Add a Preferences window to VibeNotch. Opened via "Preferences…" in the status menu. Exposes color palette selection and Launch at Login toggle.

## Architecture

New file `Sources/VibeNotch/SettingsWindowController.swift` keeps all settings code separate from the existing `main.swift`.

### New types

**`ColorPalette`** — value type defining a named theme:
```swift
struct ColorPalette {
    let name: String
    let idle: Color
    let working: Color
    let awaiting: Color
}
```
Presets defined as a static `[ColorPalette]` array in `SettingsWindowController.swift`. The developer populates this array.

**`AppPreferences`** — `ObservableObject` singleton backed by `UserDefaults`:
- `@Published var paletteIndex: Int` — index into the presets array
- Writes to `UserDefaults` key `vibenotch.paletteIndex` on change via `didSet`
- Computed property `selectedPalette: ColorPalette` returns `presets[paletteIndex]`
- Defaults to index `0` on first launch (no migration needed)

**`SettingsWindowController`** — singleton that owns the `NSWindow`:
- `showWindow()` called from a new "Preferences…" status menu item
- Window: ~380×220pt, titled, closeable, not resizable, dark appearance
- Content: `NSHostingView` wrapping `SettingsView`

### Changes to existing code

**`IndicatorPattern.color` / `nsColor`** — currently hardcoded. Change to read from `AppPreferences.shared.selectedPalette` at call time. `NotchView` must also add `@ObservedObject var prefs = AppPreferences.shared` so a palette change triggers a redraw even when `ClaudeState.pattern` hasn't changed.

**`AppDelegate.buildStatusMenu()`** — add "Preferences…" item above the separator before "Quit". Add `NSMenuDelegate` update for Launch at Login state (already present via tag 3).

## UI

Single "General" tab. Future tabs (e.g. Audio) can be added later.

### Color Palette picker

Horizontal row of swatches, one per preset:
- Each swatch: small rounded rectangle showing 3 colored dots (idle / working / awaiting) stacked or inline, with the preset name below
- Selected swatch: highlighted border (system accent color)
- Click to select — updates `AppPreferences.shared.paletteIndex`

### Launch at Login

Checkbox row below the palette picker. Reads `SMAppService.mainApp.status` as source of truth. Calls existing `SMAppService` register/unregister logic. Status menu item (tag 3) stays and remains in sync via `menuWillOpen`.

## Data Flow

```
User clicks swatch
  → AppPreferences.paletteIndex updated
  → UserDefaults written
  → IndicatorPattern.color reads new palette on next render
  → NotchView redraws (triggered by existing pattern publisher)

User toggles Launch at Login
  → SMAppService.register() / unregister()
  → Status menu item reflects state via menuWillOpen (existing)
```

## Out of Scope

- Audio settings (future tab)
- Custom per-state color pickers (presets only)
- Hotkeys, advanced, or license tabs
