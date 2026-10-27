#!/opt/homebrew/bin/bash
# ps gives each process's share of one core, so the sum is over all cores.
if usage=$(ps -A -o %cpu=) && cores=$(sysctl -n hw.ncpu) && [[ $cores =~ ^[1-9][0-9]*$ ]]; then
  pct=$(awk -v cores="$cores" '{ sum += $1 } END { printf "%.0f", sum / cores }' <<<"$usage")
  sketchybar --set "$NAME" drawing=on icon=$'\uf4bc' label="$pct%"
else
  sketchybar --set "$NAME" drawing=off
fi
exit 0
