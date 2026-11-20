#!/bin/sh
set -eu
dir="$HOME/.wizloops/hourly-status"
repo=$WIZLOOP_PARAM_REPO
spec=$WIZLOOP_PARAM_SPEC
key=$(printf '%s-%s' "$repo" "$spec" | tr -c 'A-Za-z0-9.\n-' '_')
mkdir -p "$dir"

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
  -F spec="$spec" -f query="$query" --jq "$filter") ||
  { printf 'hourly-status: cannot read spec %s in %s\n' "$spec" "$repo" >&2; exit 2; }
case "$state" in
  cut-short*|*"
cut-short"*) printf 'hourly-status: GitHub cut a list short for spec %s in %s\n' "$spec" "$repo" >&2; exit 2 ;;
esac

if [ -f "$dir/$key.posted" ] && [ "$state" = "$(cat "$dir/$key.posted")" ]; then
  rm -f "$dir/$key.pending"
  exit 0
fi
printf '%s\n' "$state" > "$dir/$key.pending"
printf 'Spec %s in %s changed since the last status line.\n' "$spec" "$repo"
echo "Once the line is posted: mv $dir/$key.pending $dir/$key.posted"
echo "Each ticket, then the open pull requests that close it:"
printf '%s\n' "$state"
