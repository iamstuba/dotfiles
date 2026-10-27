#!/opt/homebrew/bin/bash
# The event loop and workspaces.sh both source this, so both draw the same
# way. Each function appends to bar_args, and the caller sends them as
# one sketchybar call.
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/plugins/icon_map.sh"

bar_args=()

render_workspaces() {
  local windows focused ws app
  local -A icons seen
  # A failed query leaves the pills as they were.
  windows=$(aerospace list-windows --all --format '%{workspace}|%{app-name}' 2>/dev/null) || return 0
  focused=$(aerospace list-workspaces --focused 2>/dev/null) || return 0
  while IFS='|' read -r ws app; do
    [[ -n $ws && -z ${seen[$ws|$app]} ]] || continue
    seen[$ws|$app]=1
    __icon_map "$app"
    icons[$ws]+=${icons[$ws]:+ }$icon_result
  done <<<"$windows"
  local bg text
  for ws in 1 2 3 4 5; do
    bg=$PILL_BG text=$FG
    [[ $ws == "$focused" ]] && bg=$ACCENT text=$BAR_COLOR
    if [[ -n ${icons[$ws]} ]]; then
      bar_args+=(--set "workspace.$ws" background.color="$bg" icon.color="$text"
        label.color="$text" label="${icons[$ws]}" label.drawing=on)
    else
      [[ $ws == "$focused" ]] || text=$GREY
      bar_args+=(--set "workspace.$ws" background.color="$bg" icon.color="$text" label.drawing=off)
    fi
  done
}

render_front_app() {
  local window title
  # No focused window, as on an empty workspace, hides the item.
  if window=$(aerospace list-windows --focused --format '%{app-name}|%{window-title}' 2>/dev/null) \
    && [[ -n $window ]]; then
    title=${window#*|}
    bar_args+=(--set front_app drawing=on label="${window%%|*}${title:+: $title}")
  else
    bar_args+=(--set front_app drawing=off)
  fi
}

render_mode() { # $1: the mode, empty when AeroSpace is paused
  case $1 in
    main) bar_args+=(--set mode drawing=off) ;;
    '') bar_args+=(--set mode drawing=on label=PAUSED background.color="$RED") ;;
    *) bar_args+=(--set mode drawing=on label="${1^^}" background.color="$ORANGE") ;;
  esac
}
