#!/bin/bash
set -e

if ! command -v watchexec &> /dev/null; then
  echo "watchexec not installed. Run: brew install watchexec"
  exit 1
fi

cd "$(dirname "$0")"

exec watchexec -r -e swift --no-vcs-ignore -- 'swift build && .build/debug/VibeNotch'
