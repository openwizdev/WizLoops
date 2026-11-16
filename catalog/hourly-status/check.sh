#!/bin/sh
# hourly-status check for spec {{spec}} in {{repo}}.
#
# Reads the spec's tickets and the open pull requests that close them, and
# prints that state only when it differs from the last status line the agent
# posted. Nothing changed: it prints nothing, so no agent starts. GitHub
# can't be read: it fails the run (exit 2), never a silent quiet hour.
#
# The state it printed waits in <key>.pending until the agent has posted the
# line and renamed it to <key>.posted, so a run that fails before posting
# shows the same change again next hour.
set -eu
dir="$HOME/.wizloops/hourly-status"
key=$(printf '%s-%s' '{{repo}}' '{{spec}}' | tr -c 'A-Za-z0-9.\n-' '_')
mkdir -p "$dir"

tickets=$(gh issue view '{{spec}}' -R '{{repo}}' --json subIssues \
  --jq '.subIssues.nodes[] | "#\(.number) \(.state)"') ||
  { echo "hourly-status: cannot read spec {{spec}} in {{repo}}" >&2; exit 2; }
prs=$(gh pr list -R '{{repo}}' --state open --limit 200 \
  --json number,headRefOid,closingIssuesReferences \
  --jq '.[] | "\(.number) \(.headRefOid[0:7]) \([.closingIssuesReferences[].number | tostring] | join(","))"') ||
  { echo "hourly-status: cannot read pull requests in {{repo}}" >&2; exit 2; }

# Keep only the pull requests that close one of this spec's tickets.
spec_prs=$(printf '%s\n' "$prs" | awk -v t="$tickets" '
  BEGIN { n = split(t, l, "\n"); for (i = 1; i <= n; i++) { sub(/^#/, "", l[i]); sub(/ .*/, "", l[i]); mine[l[i]] = 1 } }
  NF >= 3 { m = split($3, c, ","); for (i = 1; i <= m; i++) if (c[i] in mine) { print "#" $1 " at " $2 " (closes #" c[i] ")"; break } }')

state=$(printf 'tickets:\n%s\npull requests:\n%s\n' "$tickets" "${spec_prs:-none}")

if [ -f "$dir/$key.posted" ] && [ "$state" = "$(cat "$dir/$key.posted")" ]; then
  rm -f "$dir/$key.pending"
  exit 0
fi
printf '%s\n' "$state" > "$dir/$key.pending"
echo "Spec {{spec}} in {{repo}} changed since the last status line."
echo "Once the line is posted: mv $dir/$key.pending $dir/$key.posted"
printf '%s\n' "$state"
