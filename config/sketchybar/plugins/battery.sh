#!/opt/homebrew/bin/bash
source "$CONFIG_DIR/colors.sh"

batt=$(pmset -g batt 2>/dev/null)
# A Mac with no battery prints only the power source line.
pct=$(awk '/InternalBattery/ && match($0, /[0-9]+%/) { print substr($0, RSTART, RLENGTH - 1); exit }' <<<"$batt")
if [[ ! $pct =~ ^[0-9]+$ ]]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

if [[ $batt == *"'AC Power'"* ]]; then icon=$'\U000f0084'
elif ((pct >= 90)); then icon=$'\uf240'
elif ((pct >= 60)); then icon=$'\uf241'
elif ((pct >= 40)); then icon=$'\uf242'
elif ((pct >= 10)); then icon=$'\uf243'
else icon=$'\uf244'
fi
color=$FG
((pct <= 20)) && color=$RED

sketchybar --set "$NAME" drawing=on icon="$icon" icon.color="$color" label="$pct%" label.color="$color"
exit 0
