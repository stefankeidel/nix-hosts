#!/usr/bin/env bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title ghostty new nu
# @raycast.mode silent
open -n -a ~/Applications/Home\ Manager\ Apps/Ghostty.app --args -e /etc/profiles/per-user/${USER}/bin/nu
