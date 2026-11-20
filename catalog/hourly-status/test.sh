#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../test-params.sh"
command -v jq >/dev/null || { echo "test: needs jq" >&2; exit 2; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/home" "$work/data"

render_check "$here/../hourly-status.md" "$work/check.sh"

cat > "$work/bin/gh" <<'EOF'
#!/bin/sh
[ -n "${GH_ARGS-}" ] && for a in "$@"; do printf '%s\n' "$a"; done > "$GH_ARGS"
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

t2=CLOSED t3=OPEN t3_labels='"ready-for-agent"'
h12=abc1234 draft12=false reviews12= checks12=PENDING comments12=1
h30=ccc3000 h40=ddd4000 more_labels=false
pr() {
  printf '{"number":%s,"state":"OPEN","isDraft":%s,"headRefOid":"%s000000000000000000000000000000000","reviewDecision":null,"repository":{"nameWithOwner":"%s"},"comments":{"totalCount":%s},"latestReviews":{"pageInfo":{"hasNextPage":false},"nodes":[%s]},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"%s"}}}]},"closingIssuesReferences":[]}' \
    "$1" "$4" "$3" "$2" "$7" "$5" "$6"
}
ticket() {
  label_nodes=$(printf '%s' "$3" | sed 's/"\([^",]*\)"/{"name":"\1"}/g')
  printf '{"number":%s,"state":"%s","repository":{"nameWithOwner":"example-org/example-repo"},"labels":{"pageInfo":{"hasNextPage":%s},"nodes":[%s]},"closedByPullRequestsReferences":{"pageInfo":{"hasNextPage":false},"nodes":[%s]}}' \
    "$1" "$2" "$more_labels" "$label_nodes" "$4"
}
closes() {
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
quiet() {
  wake
  if [ -n "$out" ] || [ "$code" -gt 1 ]; then
    echo "FAIL $1: expected a quiet wake, got exit $code and: $out"; fails=$((fails + 1))
  else echo "ok   $1"; fi
}
due() {
  wake
  case "$out" in
    *"$2"*) if [ "$code" -le 1 ]; then echo "ok   $1"; return; fi ;;
  esac
  echo "FAIL $1: expected output with '$2', got exit $code and: $out"; fails=$((fails + 1))
}
shows() {
  case "$out" in *"$2"*) echo "ok   $1" ;; *) echo "FAIL $1: no '$2' in: $out"; fails=$((fails + 1)) ;; esac
}
lacks() {
  case "$out" in *"$2"*) echo "FAIL $1: '$2' shown in: $out"; fails=$((fails + 1)) ;; *) echo "ok   $1" ;; esac
}
failed() {
  wake
  if [ -z "$out" ] && [ "$code" -gt 1 ]; then echo "ok   $1"
  else echo "FAIL $1: expected a failed run, got exit $code and: $out"; fails=$((fails + 1)); fi
}
agent_posted_the_line() {
  for f in "$work/home/.wizloops/hourly-status/"*.pending; do [ -e "$f" ] || continue; mv "$f" "${f%.pending}.posted"; done
}

due "the first wake shows the state, so a spec gets its first line" "#12 at abc1234"
lacks "a pull request closing another repository's #2 is not work on this spec's ticket #2" "#40"
shows "the 201st open pull request, closing a ticket on the second page of sub-issues, is seen" "#30 at ccc3000"
agent_posted_the_line; quiet "nothing changed since the posted line: no output, so no agent starts"
t3=CLOSED
due "a ticket closed is a change, so the status line never goes stale" "#3 example-org/example-repo CLOSED"
due "a change not posted yet is still due, so a run failing before posting loses nothing" "#3 example-org/example-repo CLOSED"
agent_posted_the_line; quiet "posted, quiet again"
t3=OPEN h12=abc9999
due "a push to the spec's pull request is a change" "#12 at abc9999"
agent_posted_the_line
draft12=true; due "same head: marked draft" "draft"; agent_posted_the_line
draft12=false; due "same head: marked ready" "ready"; agent_posted_the_line
reviews12='{"state":"CHANGES_REQUESTED","author":{"login":"example-reviewer"}}'
due "same head: a review asks for changes" "example-reviewer=CHANGES_REQUESTED"; agent_posted_the_line
checks12=FAILURE; due "same head: CI failed" "checks:FAILURE"; agent_posted_the_line
comments12=2; due "same head: a new comment (a verdict)" "comments:2"; agent_posted_the_line
t3_labels='"ready-for-agent","needs-info"'
due "a ticket asks a question" "needs-info"; agent_posted_the_line
quiet "all of that posted, quiet again"
h40=ddd9999; quiet "an unrelated pull request moved: this spec's agent stays asleep"
more_labels=true; failed "a list GitHub cut short fails the run, never read as complete"; more_labels=false
touch "$work/data/fail"; failed "a failed read fails the run, never a quiet hour"
rm "$work/data/fail"

for repo in 'example-org/x"$(touch${IFS}marker)"' 'example-org/`touch marker`' \
  "example-org/x';touch marker;'" 'release/";printf${IFS}WAKE;false${IFS}"' 'example-org/a\cb'; do
  render_check "$here/../hourly-status.md" "$work/check.sh" \
    "$(python3 -I -c 'import json, sys; print(json.dumps({"repo": sys.argv[1]}))' "$repo")"
  rm -f "$work/marker" "$work/args"; touch "$work/args"
  (cd "$work" && GH_ARGS="$work/args" FAKE="$work/data" HOME="$work/home" PATH="$work/bin:$PATH" \
    sh "$work/check.sh" > "$work/out" 2>&1) || true
  if [ "$(head -n 1 "$work/out")" = "Spec 1 in $repo changed since the last status line." ] &&
     grep -qxF -- "owner=${repo%%/*}" "$work/args" && grep -qxF -- "name=${repo#*/}" "$work/args" &&
     [ ! -e "$work/marker" ]; then
    printf 'ok   payload repo stays data: %s\n' "$repo"
  else
    printf 'FAIL payload repo stays data: %s: %s\n' "$repo" "$(head -n 2 "$work/out" | tr '\n' ' ')"
    fails=$((fails + 1))
  fi
done

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
echo "all passed"
