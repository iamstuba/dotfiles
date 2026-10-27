#!/opt/homebrew/bin/bash
# The bar must not outlive the window manager. 2.24.1 has --exit. AeroSpace
# starts the bar, so it is this script's ancestor, which pgrep skips without -a.
pgrep -aqx AeroSpace || sketchybar --exit
exit 0
