#!/bin/sh

# The $NAME variable is passed from sketchybar and holds the name of
# the item invoking this script:
# https://felixkratz.github.io/SketchyBar/config/events#events-and-scripting

hour="$(date '+%H')"
minute="$(date '+%M')"

sketchybar --set clock_hour label="$hour" \
           --set clock_min label="$minute"
