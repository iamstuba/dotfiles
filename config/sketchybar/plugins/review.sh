#!/opt/homebrew/bin/bash
# $1: github or gitlab. Each forge's fetch prints the total count, then up to
# ten repo<TAB>number<TAB>title<TAB>url rows, and fails when the chip should
# hide. The renderer below never sees forge JSON.
# gh and glab are mise tools, off SketchyBar's PATH. jq is macOS's own, so
# the shims stay out of each poll's jq.
export PATH=$HOME/.local/share/mise/shims:$PATH

hide() { sketchybar --set "$NAME" drawing=off popup.drawing=off; }

# The pointer has left the chip and its popup, or another window took focus.
# A fetch here would cost a request on every pass of the mouse.
if [[ ${SENDER:-} == mouse.exited.global || ${SENDER:-} == aerospace_focus_change ]]; then
  sketchybar --set "$NAME" popup.drawing=off
  exit 0
fi

fetch_github() {
  local json
  # Without a login gh exits 4 before any request, so no separate check.
  json=$(gh api -X GET search/issues \
    -f q='is:pr is:open draft:false archived:false review-requested:@me' -f per_page=10 2>/dev/null) \
    || return 1
  # A tab or newline in a title would split its row.
  /usr/bin/jq -r '.total_count, (.items[] | "\(.repository_url | sub("^.*/repos/"; ""))\t\(.number)\t\(.title | gsub("[\t\n\r]"; " "))\t\(.html_url)")' \
    <<<"$json" 2>/dev/null
}

# Without GLAB_CONFIG_DIR a glab run before any login writes a second config
# under Application Support. Telemetry doubles every request, and the update
# check prints a notice once a day.
export GLAB_CONFIG_DIR=$HOME/.config/glab-cli GLAB_SEND_TELEMETRY=0 GITLAB_HOST=gitlab.com \
  GLAB_CHECK_UPDATE=false

# This is GitLab's own review count. An MR the user approved or requested
# changes on leaves it until the author re-requests a review.
gitlab_query='{ currentUser { reviewRequestedMergeRequests(state: opened, draft: false, reviewStates: [UNREVIEWED, REVIEW_STARTED, UNAPPROVED], first: 10, sort: UPDATED_DESC) { count nodes { iid title webUrl project { fullPath } } } } }'

fetch_gitlab() {
  # A missing glab fails here too. The config file alone answers, so a Mac with
  # no login costs no request.
  [[ -n $(glab config get user --host gitlab.com 2>/dev/null) ]] || return 1
  local json
  # glab exits 1 for every failure, so the script parses its output only on
  # success.
  json=$(glab api --hostname gitlab.com graphql -f query="$gitlab_query" 2>/dev/null) || return 1
  # A revoked token answers with a null currentUser.
  /usr/bin/jq -r '.data.currentUser.reviewRequestedMergeRequests // error("no user")
    | .count, (.nodes[] | "\(.project.fullPath)\t\(.iid)\t\(.title | gsub("[\t\n\r]"; " "))\t\(.webUrl)")' \
    <<<"$json" 2>/dev/null
}

forge=${1:-}
case $forge in
  github) icon=$'\uf09b' sigil='#' ;;
  gitlab) icon=$'\uf296' sigil='!' ;;
  *) hide; exit 0 ;;
esac

if ! rows=$("fetch_$forge"); then
  hide
  exit 0
fi
{
  read -r count
  [[ $count =~ ^[0-9]+$ ]] || count=0
  if ((count == 0)); then
    hide
    exit 0
  fi
  labels=() urls=()
  while ((${#labels[@]} < 10)) && IFS=$'\t' read -r repo number title url; do
    labels+=("$repo$sigil$number  $title")
    urls+=("$url")
  done
  # SketchyBar sizes each popup row to its own text, so a short row's
  # highlight and click would stop where its text ends. Every row gets the
  # longest row's width instead. Monaspace Neon at 13 points, with the rows'
  # 8-point padding, measured 16 + 8.05 points a character in a live popup. A
  # closed popup lays out nothing, so asking SketchyBar is no use here.
  longest=0
  for label in "${labels[@]}"; do
    ((${#label} > longest)) && longest=${#label}
  done
  width=$((16 + (805 * longest + 99) / 100))
  args=(--set "$NAME" drawing=on icon="$icon" label="$count")
  for i in "${!labels[@]}"; do
    n=$((i + 1)) url=${urls[i]}
    # SketchyBar runs the click through sh. The quoting keeps the URL one
    # argument, whatever it holds. The popup closes under the pointer, so the
    # row gets no mouse.exited and the click clears its highlight.
    args+=(--set "$NAME.row.$n" drawing=on label="${labels[i]}" width="$width"
      click_script="open '${url//\'/\'\\\'\'}'; sketchybar --set $NAME popup.drawing=off --set $NAME.row.$n background.drawing=off")
  done
  for ((n = ${#labels[@]} + 1; n <= 10; n++)); do
    args+=(--set "$NAME.row.$n" drawing=off)
  done
  sketchybar "${args[@]}"
} <<<"$rows"
exit 0
