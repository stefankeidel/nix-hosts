#!/bin/sh

status="$(lsappinfo -all info -only StatusLabel "Microsoft Teams" | sed -nr 's/\"StatusLabel\"=\{ \"label\"=\"(.+)\" \}$/\1/p')"

if [ -z "$status" ] || [ "$status" -eq 0 ] 2>/dev/null; then
  sketchybar --set "$NAME" label="" label.drawing=off
else
  sketchybar --set "$NAME" label="T $status" label.drawing=on
fi
