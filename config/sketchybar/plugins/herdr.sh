#!/opt/homebrew/bin/bash
# The working count goes in the icon slot and the blocked count in the label,
# since a label has one colour. The icon slot takes the label font, because
# the icon font has no digits.
# herdr is a Homebrew tool, off SketchyBar's PATH. jq is macOS's own, called
# by path.
export PATH=${HOMEBREW_PREFIX:-/opt/homebrew}/bin:$PATH
source "$CONFIG_DIR/colors.sh"

# herdr exits 1 when no server runs, and a missing herdr fails too.
if ! json=$(herdr agent list 2>/dev/null) \
  || ! counts=$(/usr/bin/jq -r '[.result.agents[].agent_status]
      | "\(map(select(. == "working")) | length) \(map(select(. == "blocked")) | length)"' \
      <<<"$json" 2>/dev/null); then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi
read -r working blocked <<<"$counts"
if ((working == 0 && blocked == 0)); then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

args=(--set "$NAME" drawing=on)
if ((working > 0)); then
  args+=(icon="$working" icon.drawing=on icon.color="$ACCENT" icon.font="Monaspace Neon:Regular:13.0")
else
  args+=(icon.drawing=off)
fi
if ((blocked > 0)); then
  args+=(label="$blocked" label.drawing=on label.color="$RED")
else
  args+=(label.drawing=off)
fi
sketchybar "${args[@]}"
exit 0
