#!/opt/homebrew/bin/bash
# sketchybarrc starts this in the background. It redraws the pills and the
# mode badge on each AeroSpace event, one sketchybar call per event.
# subscribe sends the current state on connect.
source "$CONFIG_DIR/plugins/aerospace_render.sh"

# A reload reruns sketchybarrc, so an older copy of this loop must end. The
# command check keeps a reused pid from killing something else, or this copy.
pidfile=${TMPDIR:-/tmp/}
pidfile=${pidfile%/}/sketchybar-aerospace-events.pid
if [[ -f $pidfile ]] && old=$(<"$pidfile") && [[ $old =~ ^[0-9]+$ && $old != "$$" ]] \
  && [[ $(/bin/ps -o command= -p "$old") == *"$CONFIG_DIR/plugins/aerospace_events.sh"* ]]; then
  kill "$old"
fi
echo $$ >"$pidfile"

exec {events}< <(exec aerospace subscribe focus-changed focused-workspace-changed mode-changed)
subscribe=$!
# Without this, subscribe keeps running until its next event hits a closed pipe.
trap 'kill "$subscribe" 2>/dev/null' EXIT

while IFS= read -r line <&"$events"; do
  IFS=$'\t' read -r event mode < <(jq -r '[._event // "", .mode // ""] | @tsv' <<<"$line" 2>/dev/null)
  bar_args=()
  case $event in
    focus-changed | focused-workspace-changed) render_workspaces ;;
    mode-changed) render_mode "$mode" ;;
    *) continue ;;
  esac
  # A refused command means the bar has quit.
  sketchybar "${bar_args[@]}" || break
done
exit 0
