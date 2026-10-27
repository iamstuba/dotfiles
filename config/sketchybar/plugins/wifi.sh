#!/opt/homebrew/bin/bash
# $1: the Wi-Fi device, which sketchybarrc looks up. macOS redacts the SSID,
# so only the link state is shown. A down link still exits 0.
if [[ -z ${1:-} ]] || ! summary=$(ipconfig getsummary "$1" 2>/dev/null); then
  sketchybar --set "$NAME" drawing=off
elif grep -Eq '^[[:space:]]*LinkStatusActive : TRUE$' <<<"$summary"; then
  sketchybar --set "$NAME" drawing=on icon=$'\U000f05a9'
else
  sketchybar --set "$NAME" drawing=on icon=$'\U000f05aa'
fi
exit 0
