#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title alacrity new nu
# @raycast.mode silent
open -n -a ~/Applications/Home\ Manager\ Apps/Alacritty.app --args -e /etc/profiles/per-user/${USER}/bin/nu
