# Notch Hover Expansion

**Date:** 2026-04-28
**Status:** Approved

## Goal

When the user hovers over the notch panel, the black notch shape springs open downward, revealing a list of running agents and their states. Mouse leave collapses it instantly with a spring close.

## Panel

Pre-allocate panel height to ~300pt instead of the current `notchHeight`. Top edge stays pinned to screen top; extra height hangs into the display. This avoids resizing the panel on every hover.

`panel.ignoresMouseEvents = false` — the panel is non-activating (`canBecomeKey: false`, `.nonactivatingPanel` style mask) so it will not steal focus from the user's active app.

## Layout

`NotchView` becomes a `VStack(spacing: 0)`:

1. **Notch bar** (always visible) — existing `IndicatorView` + agent count badge, fixed at `notchHeight`.
2. **Agent list** — `frame(height: expanded ? 200 : 0)` + `.clipped()`. Height 0 when collapsed; hidden by clipping, not removed from hierarchy. Total panel pre-allocation is notchHeight + 200 + padding.

`NotchShape` remains as `.background` on the VStack. Because it fills whatever rect the view occupies, it naturally grows as the VStack height animates — no shape changes needed beyond the height.

## Animation

```swift
@State private var expanded = false

// on the VStack:
.animation(.spring(response: 0.35, dampingFraction: 0.75), value: expanded)
.onHover { expanded = $0 }
```

Both expand and collapse are spring-driven. Collapse triggers immediately on mouse leave — no delay.

## Agent List (placeholder)

Each row:
- Mini 3×3 indicator icon (same `IndicatorView` at smaller scale)
- "Claude Code · Vibe Notch" subtitle
- State label: Idle / Thinking / Working / Waiting for input

Rows use hardcoded placeholder data for this iteration. Real per-agent state tracking is deferred.

## Out of Scope

- Real per-agent data model
- Scrolling (list exceeds panel height)
- Click actions on rows
- Per-row hover highlights
