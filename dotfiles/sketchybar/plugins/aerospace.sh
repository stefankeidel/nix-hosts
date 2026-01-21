#!/bin/sh

exec >>/tmp/sketchybar-aerospace.log 2>&1
set -x

workspace="${1:-${NAME#aerospace.}}"
focused="$FOCUSED_WORKSPACE"
if [ -z "$focused" ]; then
  focused="$("${AEROSPACE_BIN:-/etc/profiles/per-user/$USER/bin/aerospace}" list-workspaces --focused | head -n 1)"
fi

if [ "$workspace" = "$focused" ]; then
  sketchybar --set "$NAME" background.drawing=on
else
  sketchybar --set "$NAME" background.drawing=off
fi
