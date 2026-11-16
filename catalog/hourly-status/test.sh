#!/bin/sh
# Runs hourly-status's check against a stand-in `gh` that serves raw,
# synthetic GitHub JSON and applies the check's own --jq filter with jq, and
# checks the one promise the loop makes: it prints the spec's state when it
# changed since the last posted status line, and nothing otherwise, so a
# quiet hour starts no agent.
#
# Needs jq. Usage, from anywhere: sh catalog/hourly-status/test.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null || { echo "test: needs jq" >&2; exit 2; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/home" "$work/data"

# The check with its params replaced by the file's synthetic defaults, as an
# adapter replaces them before it applies the loop.
sed -e 's#[{][{]repo[}][}]#example-org/example-repo#g' \
    -e 's#[{][{]spec[}][}]#1#g' \
    "$here/check.sh" > "$work/check.sh"

# A stand-in for `gh`. `api graphql` serves page1.json, and page2.json only
# with --paginate and an $endCursor query, as gh does; `issue view` and
# `pr list` serve the same world in their shapes (pr list honours --limit).
# Each answer goes through the caller's --jq, applied by jq. With
# data/fail it fails as gh does when GitHub can't be read.
cat > "$work/bin/gh" <<'EOF'
#!/bin/sh
[ -f "$FAKE/fail" ] && { echo "gh: could not connect" >&2; exit 1; }
cmd="$1 $2"; shift 2
filter=. paginate=no limit=30 query=
while [ $# -gt 0 ]; do
  case "$1" in
    --jq) filter=$2; shift ;;
    --limit) limit=$2; shift ;;
    --paginate) paginate=yes ;;
    -f|-F) case "$2" in query=*) query=${2#query=} ;; esac; shift ;;
  esac
  shift
done
pages="$FAKE/page1.json"
case "$query" in *'$endCursor'*) [ $paginate = yes ] && pages="$pages $FAKE/page2.json" ;; esac
case "$cmd" in
  "api graphql") for p in $pages; do jq -r "$filter" "$p" || exit 1; done ;;
  "issue view") jq -s '{subIssues: {nodes: [.[].data.repository.issue.subIssues.nodes[]]}}' \
      "$FAKE/page1.json" "$FAKE/page2.json" | jq -r "$filter" ;;
  "pr list") jq ".[0:$limit]" "$FAKE/prs.json" | jq -r "$filter" ;;
  *) echo "gh: unexpected: $cmd" >&2; exit 1 ;;
esac
EOF
chmod +x "$work/bin/gh"

# The synthetic world. Spec 1 has tickets #2 and #3 on the first page of its
# sub-issues and #4 on the second. #12 closes #3; #30 closes #4 and is the
# 201st open pull request; #40 closes other-org/other-repo#2, not ticket #2.
t2=CLOSED t3=OPEN t3_labels='"ready-for-agent"'
h12=abc1234 draft12=false reviews12= checks12=PENDING comments12=1
h30=ccc3000 h40=ddd4000 more_labels=false
pr() { # number repo head draft reviews checks comments
  printf '{"number":%s,"state":"OPEN","isDraft":%s,"headRefOid":"%s000000000000000000000000000000000","reviewDecision":null,"repository":{"nameWithOwner":"%s"},"comments":{"totalCount":%s},"latestReviews":{"pageInfo":{"hasNextPage":false},"nodes":[%s]},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"%s"}}}]},"closingIssuesReferences":[]}' \
    "$1" "$4" "$3" "$2" "$7" "$5" "$6"
}
ticket() { # number state labels prs
  printf '{"number":%s,"state":"%s","repository":{"nameWithOwner":"example-org/example-repo"},"labels":{"pageInfo":{"hasNextPage":%s},"nodes":[%s]},"closedByPullRequestsReferences":{"pageInfo":{"hasNextPage":false},"nodes":[%s]}}' \
    "$1" "$2" "$more_labels" "$(printf '%s' "$3" | sed 's/"\([^",]*\)"/{"name":"\1"}/g')" "$4"
}
closes() { # <pr json> <issue number> <its repository>
  printf '%s' "$1" | sed "s#\"closingIssuesReferences\":\[\]#\"closingIssuesReferences\":[{\"number\":$2,\"repository\":{\"nameWithOwner\":\"$3\"}}]#"
}
world() {
  p12=$(pr 12 example-org/example-repo "$h12" "$draft12" "$reviews12" "$checks12" "$comments12")
  p30=$(pr 30 example-org/example-repo "$h30" false "" SUCCESS 0)
  p40=$(pr 40 example-org/example-repo "$h40" false "" SUCCESS 0)
  printf '{"data":{"repository":{"issue":{"subIssues":{"pageInfo":{"hasNextPage":true,"endCursor":"Mg"},"nodes":[%s,%s]}}}}}\n' \
    "$(ticket 2 "$t2" "" "")" "$(ticket 3 "$t3" "$t3_labels" "$p12")" > "$work/data/page1.json"
  printf '{"data":{"repository":{"issue":{"subIssues":{"pageInfo":{"hasNextPage":false,"endCursor":"Mw"},"nodes":[%s]}}}}}\n' \
    "$(ticket 4 OPEN "" "$p30")" > "$work/data/page2.json"
  # pr list: #12 and #40 first, 198 unrelated, then #30 as the 201st.
  { printf '[%s,%s' "$(closes "$p12" 3 example-org/example-repo)" "$(closes "$p40" 2 other-org/other-repo)"
    i=100; while [ $i -lt 298 ]; do printf ',%s' "$(pr $i example-org/example-repo eee0000 false "" SUCCESS 0)"; i=$((i + 1)); done
    printf ',%s]\n' "$(closes "$p30" 4 example-org/example-repo)"
  } > "$work/data/prs.json"
}

fails=0
wake() {
  world
  set +e
  out=$(FAKE="$work/data" HOME="$work/home" PATH="$work/bin:$PATH" sh "$work/check.sh" 2>"$work/err")
  code=$?
  set -e
}
quiet() { # <case>: the wake printed nothing and ended 0 or 1
  wake
  if [ -n "$out" ] || [ "$code" -gt 1 ]; then
    echo "FAIL $1: expected a quiet wake, got exit $code and: $out"; fails=$((fails + 1))
  else echo "ok   $1"; fi
}
due() { # <case> <text it must show>: the wake printed the state
  wake
  case "$out" in
    *"$2"*) if [ "$code" -le 1 ]; then echo "ok   $1"; return; fi ;;
  esac
  echo "FAIL $1: expected output with '$2', got exit $code and: $out"; fails=$((fails + 1))
}
shows() { # <case> <text>: the last wake's output shows it
  case "$out" in *"$2"*) echo "ok   $1" ;; *) echo "FAIL $1: no '$2' in: $out"; fails=$((fails + 1)) ;; esac
}
lacks() { # <case> <text>: the last wake's output does not show it
  case "$out" in *"$2"*) echo "FAIL $1: '$2' shown in: $out"; fails=$((fails + 1)) ;; *) echo "ok   $1" ;; esac
}
failed() { # <case>: the wake failed the run (exit over 1) and printed nothing
  wake
  if [ -z "$out" ] && [ "$code" -gt 1 ]; then echo "ok   $1"
  else echo "FAIL $1: expected a failed run, got exit $code and: $out"; fails=$((fails + 1)); fi
}
posted() { # the agent posted the line and recorded it, as the prompt says
  for f in "$work/home/.wizloops/hourly-status/"*.pending; do [ -e "$f" ] || continue; mv "$f" "${f%.pending}.posted"; done
}

# catches: the first wake stays quiet, so a spec never gets its first line
due "first wake shows the state" "#12 at abc1234"
# catches: a pull request that closes another repository's #2 is counted as
# work on this spec's ticket #2
lacks "another repository's #2 is not this spec's" "#40"
# catches: a fixed window over the repository's open pull requests, or only
# the first page of sub-issues, hides the spec's pull request #30
shows "a ticket's pull request past any window is seen" "#30 at ccc3000"
# catches: the check prints on every wake (as an always-echo check does), so
# every hour starts an agent even when nothing changed
posted; quiet "nothing changed since the posted line"
# catches: a change is missed, so the status line goes stale
t3=CLOSED
due "a ticket closed" "#3 example-org/example-repo CLOSED"
# catches: the check marks a change as posted itself, so a run that fails
# before posting loses the change for good
due "not posted yet, still due" "#3 example-org/example-repo CLOSED"
posted; quiet "posted, quiet again"
# catches: a push to the spec's pull request is not seen as progress
t3=OPEN h12=abc9999
due "a pull request moved" "#12 at abc9999"
posted
# catches: progress at the same head is missed: a draft marked ready, a
# review, a CI result, a verdict comment, a blocking label
draft12=true; due "same head: marked draft" "draft"; posted
draft12=false; due "same head: marked ready" "ready"; posted
reviews12='{"state":"CHANGES_REQUESTED","author":{"login":"example-reviewer"}}'
due "same head: a review asks for changes" "example-reviewer=CHANGES_REQUESTED"; posted
checks12=FAILURE; due "same head: CI failed" "checks:FAILURE"; posted
comments12=2; due "same head: a new comment (a verdict)" "comments:2"; posted
t3_labels='"ready-for-agent","needs-info"'
due "a ticket asks a question" "needs-info"; posted
quiet "all of that posted, quiet again"
# catches: another spec's or nobody's pull request wakes this spec's agent
h40=ddd9999; quiet "an unrelated pull request moved"
# catches: a list GitHub cut short is read as complete, hiding changes
more_labels=true; failed "a cut-short list fails the run"; more_labels=false
# catches: GitHub can't be read and the check exits 0 or 1 with no output,
# which reads as a quiet hour and hides the failure
touch "$work/data/fail"; failed "a failed read fails the run"

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
echo "all passed"
