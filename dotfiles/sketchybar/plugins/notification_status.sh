#!/bin/sh

app_name="$1"
label_prefix="$2"

status="$(lsappinfo -all info -only StatusLabel "$app_name" | sed -nr 's/\"StatusLabel\"=\{ \"label\"=\"(.+)\" \}$/\1/p')"

if [ -z "$status" ] || [ "$status" -eq 0 ] 2>/dev/null; then
  sketchybar --set "$NAME" label="" label.drawing=off
else
  if [ -n "$label_prefix" ]; then
    label="$label_prefix $status"
  else
    label="$status"
  fi
  sketchybar --set "$NAME" label="$label" label.drawing=on
fi
