#!/opt/homebrew/bin/bash
if now=$(date '+%d/%m/%Y %H:%M'); then
  sketchybar --set "$NAME" drawing=on label="$now"
else
  sketchybar --set "$NAME" drawing=off
fi
exit 0
