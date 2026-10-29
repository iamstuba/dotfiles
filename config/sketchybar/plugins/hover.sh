#!/opt/homebrew/bin/bash
# Lights an item under the pointer. The item's own background holds the colour.
case ${SENDER:-} in
  mouse.entered) sketchybar --set "$NAME" background.drawing=on ;;
  mouse.exited) sketchybar --set "$NAME" background.drawing=off ;;
esac
exit 0
