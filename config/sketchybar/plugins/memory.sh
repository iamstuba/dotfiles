#!/opt/homebrew/bin/bash
free=$(memory_pressure 2>/dev/null \
  | awk -F': ' '/^System-wide memory free percentage:/ { sub(/%.*/, "", $2); print $2 }')
if [[ $free =~ ^[0-9]+$ ]]; then
  sketchybar --set "$NAME" drawing=on icon=$'\U000f035b' label="$((100 - free))%"
else
  sketchybar --set "$NAME" drawing=off
fi
exit 0
