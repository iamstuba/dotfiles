#!/opt/homebrew/bin/bash
# workspace.1 runs this every 10 s. AeroSpace sends no event when a window
# closes or an app quits on another workspace, so this redraws all five pills.
source "$CONFIG_DIR/plugins/aerospace_render.sh"

render_workspaces
((${#bar_args[@]})) && sketchybar "${bar_args[@]}"
exit 0
