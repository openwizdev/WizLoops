#!/bin/sh
# Morning digest check. Prints one line per item for the digest, from the
# GitHub account {{org}}'s repositories: each pull request merged in the last
# 24 hours, each open pull request whose checks fail, and each open review
# request or issue waiting on {{owner}}. Prints nothing when there is none of
# these, so a quiet morning starts no agent. Read-only; needs a signed-in gh.
since=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null ||
  date -u -v-24H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
if [ -z "$since" ]; then
  echo "check: could not work out the time 24 hours ago"
  exit 0
fi

# One search: print up to 100 lines, or one line saying GitHub could not be
# read. It asks for 101, so a list cut at 100 is told apart from exactly 100:
# then it adds one line saying the list is incomplete and how to finish it.
search() {
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
search merged prs --owner "{{org}}" --merged-at ">=$since"
search failing prs --owner "{{org}}" --state open --checks failure
search review-requested prs --owner "{{org}}" --state open --review-requested "{{owner}}"
search assigned issues --owner "{{org}}" --state open --assignee "{{owner}}"
exit 0
