#!/bin/bash
LOG=/tmp/vibe-notch-log
touch "$LOG"

echo "┌─────────────────────────────────────────────┐"
echo "│         Claude Code — Live Activity          │"
echo "└─────────────────────────────────────────────┘"
echo "  ◐ thinking   ⚙ tool use   ✓ done   ◉ awaiting"
echo ""

tail -n 20 -f "$LOG"
