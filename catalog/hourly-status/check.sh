#!/bin/sh
# hourly-status check for spec {{spec}} in {{repo}}.
#
# Reads every one of the spec's tickets (all pages) with its labels, and for
# each ticket the open pull requests GitHub links as closing that exact
# issue, with their head, draft state, review decision, latest reviews, CI
# state and comment count. It prints that state only when it differs from
# the last status line the agent posted. Nothing changed: it prints nothing,
# so no agent starts. GitHub can't be read, or cut a list short: it fails the
# run (exit 2), never a silent quiet hour.
#
# The state it printed waits in <key>.pending until the agent has posted the
# line and renamed it to <key>.posted, so a run that fails before posting
# shows the same change again next hour.
set -eu
dir="$HOME/.wizloops/hourly-status"
key=$(printf '%s-%s' '{{repo}}' '{{spec}}' | tr -c 'A-Za-z0-9.\n-' '_')
mkdir -p "$dir"
repo='{{repo}}'

query='query($owner: String!, $name: String!, $spec: Int!, $endCursor: String) {
  repository(owner: $owner, name: $name) { issue(number: $spec) {
    subIssues(first: 50, after: $endCursor) {
      pageInfo { hasNextPage endCursor }
      nodes {
        number state repository { nameWithOwner }
        labels(first: 50) { pageInfo { hasNextPage } nodes { name } }
        closedByPullRequestsReferences(first: 20, includeClosedPrs: false) {
          pageInfo { hasNextPage }
          nodes {
            number state isDraft headRefOid reviewDecision
            repository { nameWithOwner }
            comments { totalCount }
            latestReviews(first: 50) { pageInfo { hasNextPage } nodes { state author { login } } }
            commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
          }
        }
      }
    }
  } }
}'
# One line per ticket and per open pull request that closes it; a line
# "cut-short" when GitHub has more labels, pull requests or reviews than
# were read.
filter='.data.repository.issue.subIssues.nodes[] |
  (if .labels.pageInfo.hasNextPage or .closedByPullRequestsReferences.pageInfo.hasNextPage
      or any(.closedByPullRequestsReferences.nodes[]; .latestReviews.pageInfo.hasNextPage)
   then "cut-short #\(.number)" else empty end),
  "#\(.number) \(.repository.nameWithOwner) \(.state) labels:\([.labels.nodes[].name] | sort | join(","))",
  (.closedByPullRequestsReferences.nodes[] | select(.state == "OPEN") |
   "  #\(.number) at \(.headRefOid[0:7]) in \(.repository.nameWithOwner)"
   + " \(if .isDraft then "draft" else "ready" end)"
   + " decision:\(.reviewDecision // "none")"
   + " reviews:\([.latestReviews.nodes[] | "\(.author.login // "ghost")=\(.state)"] | sort | join(","))"
   + " checks:\(.commits.nodes[0].commit.statusCheckRollup.state // "none")"
   + " comments:\(.comments.totalCount)")'

state=$(gh api graphql --paginate -F owner="${repo%%/*}" -F name="${repo#*/}" \
  -F spec='{{spec}}' -f query="$query" --jq "$filter") ||
  { echo "hourly-status: cannot read spec {{spec}} in {{repo}}" >&2; exit 2; }
case "$state" in
  cut-short*|*"
cut-short"*) echo "hourly-status: GitHub cut a list short for spec {{spec}} in {{repo}}" >&2; exit 2 ;;
esac

if [ -f "$dir/$key.posted" ] && [ "$state" = "$(cat "$dir/$key.posted")" ]; then
  rm -f "$dir/$key.pending"
  exit 0
fi
printf '%s\n' "$state" > "$dir/$key.pending"
echo "Spec {{spec}} in {{repo}} changed since the last status line."
echo "Once the line is posted: mv $dir/$key.pending $dir/$key.posted"
echo "Each ticket, then the open pull requests that close it:"
printf '%s\n' "$state"
