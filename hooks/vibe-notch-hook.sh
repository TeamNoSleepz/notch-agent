#!/bin/bash
# Called by Claude Code hooks (configured in ~/.claude/settings.json).
# Writes the current agent state to /tmp/vibe-notch (read by the VibeNotch app)
# and appends a human-readable line to /tmp/vibe-notch-log.
#
# Usage: vibe-notch-hook.sh <event>
# Events: user-prompt | pre-tool | post-tool | stop | session-start

EVENT="$1"
LOG=/tmp/vibe-notch-log
TS=$(date "+%H:%M:%S")

case "$EVENT" in
  user-prompt)
    echo "thinking" > /tmp/vibe-notch
    ;;
  pre-tool)
    echo "tool" > /tmp/vibe-notch
    printf '%s  Working\n' "$TS" >> "$LOG"
    ;;
  post-tool)
    echo "thinking" > /tmp/vibe-notch
    printf '%s  Thinking\n' "$TS" >> "$LOG"
    ;;
  stop)
    echo "awaiting" > /tmp/vibe-notch
    printf '%s  Waiting\n' "$TS" >> "$LOG"
    ;;
  session-start)
    echo "idle" > /tmp/vibe-notch
    ;;
esac
