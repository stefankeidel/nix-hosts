#!/bin/sh

workspace="${1:-${NAME#aerospace.}}"
focused="$FOCUSED_WORKSPACE"
if [ -z "$focused" ]; then
  focused="$(aerospace list-workspaces --focused | head -n 1)"
fi

if [ "$workspace" = "$focused" ]; then
  sketchybar --set "$NAME" background.drawing=on
else
  sketchybar --set "$NAME" background.drawing=off
fi
