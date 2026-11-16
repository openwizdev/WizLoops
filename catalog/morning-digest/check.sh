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

# One search: print its lines, or one line saying GitHub could not be read.
search() {
  label=$1
  shift
  if ! lines=$(gh search "$@" --limit 100 --json repository,number,title \
    --jq ".[] | \"$label: \(.repository.nameWithOwner)#\(.number) \(.title)\"" 2>&1); then
    echo "check: GitHub could not be read ($label): $(printf '%s' "$lines" | head -n 1)"
    return
  fi
  [ -n "$lines" ] && printf '%s\n' "$lines"
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
