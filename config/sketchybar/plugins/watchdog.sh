#!/opt/homebrew/bin/bash
# The bar must not outlive the window manager. 2.24.1 has --exit.
pgrep -qx AeroSpace || sketchybar --exit
exit 0
