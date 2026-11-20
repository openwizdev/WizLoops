#!/bin/sh
org=$WIZLOOP_PARAM_ORG
owner=$WIZLOOP_PARAM_OWNER
since=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null ||
  date -u -v-24H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
if [ -z "$since" ]; then
  echo "check: could not work out the time 24 hours ago"
  exit 0
fi

search_up_to_100() {
  label=$1
  shift
  if ! lines=$(gh search "$@" --limit 101 --json repository,number,title \
    --jq ".[] | \"$label: \(.repository.nameWithOwner)#\(.number) \(.title)\"" 2>&1); then
    echo "check: GitHub could not be read ($label): $(printf '%s' "$lines" | head -n 1)"
    return
  fi
  [ -z "$lines" ] && return
  printf '%s\n' "$lines" | head -n 100
  if [ "$(printf '%s\n' "$lines" | wc -l)" -gt 100 ]; then
    echo "check: more than 100 $label items; only the first 100 are above. Finish the list with: gh search $*"
  fi
}

if ! command -v gh >/dev/null 2>&1; then
  echo "check: GitHub could not be read: gh is not installed"
  exit 0
fi
search_up_to_100 merged prs --owner "$org" --merged-at ">=$since"
search_up_to_100 failing prs --owner "$org" --state open --checks failure
search_up_to_100 review-requested prs --owner "$org" --state open --review-requested "$owner"
search_up_to_100 assigned issues --owner "$org" --state open --assignee "$owner"
exit 0
