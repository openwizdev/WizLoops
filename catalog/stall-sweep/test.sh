#!/bin/sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../test-params.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
cat > "$work/bin/gh" <<'GH'
#!/bin/sh
[ -n "${GH_ARGS-}" ] && for a in "$@"; do printf '%s\n' "$a"; done > "$GH_ARGS"
[ -f "$FIXTURE" ] || { echo "gh: could not reach GitHub" >&2; exit 1; }
limit=30
while [ $# -gt 0 ]; do [ "$1" = "--limit" ] && limit=$2; shift; done
python3 -I -c 'import json, sys
prs = sorted(json.load(open(sys.argv[1])), key=lambda p: -p["number"])
print(json.dumps(prs[:int(sys.argv[2])]))' "$FIXTURE" "$limit"
GH
chmod +x "$work/bin/gh"
render_check "$here/../stall-sweep.md" "$work/check.sh" || exit 1

half_past_minutes_ago() { date -u -d "-$(( $1 * 60 + 30 )) seconds" +%Y-%m-%dT%H:%M:%SZ; }
fail=0
run() {
  out=$(cd "$work" && FIXTURE="$2" PATH="$work/bin:$PATH" sh ./check.sh 2>/dev/null)
  code=$?
  if [ "$code" != "$3" ] || [ "$out" != "$4" ]; then
    printf 'FAIL %s\n  exit %s, want %s\n  got:  %s\n  want: %s\n' "$1" "$code" "$3" "$out" "$4"
    fail=1
  else
    printf 'ok   %s\n' "$1"
  fi
}

echo '[]' > "$work/none.json"
run "no open pull requests: quiet, so no agent starts for nothing" "$work/none.json" 0 ""

cat > "$work/fresh.json" <<J
[{"number": 3, "title": "#2: fresh", "isDraft": false, "updatedAt": "$(half_past_minutes_ago 10)", "mergeable": "CONFLICTING", "reviewDecision": "", "statusCheckRollup": []},
 {"number": 4, "title": "#2: a draft", "isDraft": true, "updatedAt": "$(half_past_minutes_ago 600)", "mergeable": "MERGEABLE", "reviewDecision": "", "statusCheckRollup": []}]
J
run "fresh and draft pull requests: quiet, no wake for recent work or a draft nobody waits for" "$work/fresh.json" 0 ""

cat > "$work/stalled.json" <<J
[{"number": 12, "title": "#5: conflicted and red", "isDraft": false, "updatedAt": "$(half_past_minutes_ago 90)", "mergeable": "CONFLICTING", "reviewDecision": "",
  "statusCheckRollup": [{"__typename": "CheckRun", "name": "build", "status": "COMPLETED", "conclusion": "FAILURE"},
                        {"__typename": "CheckRun", "name": "lint", "status": "COMPLETED", "conclusion": "SUCCESS"}]},
 {"number": 13, "title": "#6: approved", "isDraft": false, "updatedAt": "$(half_past_minutes_ago 125)", "mergeable": "MERGEABLE", "reviewDecision": "APPROVED",
  "statusCheckRollup": [{"__typename": "StatusContext", "context": "ci", "state": "SUCCESS"}]},
 {"number": 14, "title": "#7: stuck checks", "isDraft": false, "updatedAt": "$(half_past_minutes_ago 61)", "mergeable": "MERGEABLE", "reviewDecision": "",
  "statusCheckRollup": [{"__typename": "CheckRun", "name": "build", "status": "QUEUED", "conclusion": ""}]},
 {"number": 15, "title": "#8: nobody reviewed", "isDraft": false, "updatedAt": "$(half_past_minutes_ago 70)", "mergeable": "MERGEABLE", "reviewDecision": "REVIEW_REQUIRED",
  "statusCheckRollup": [{"__typename": "CheckRun", "name": "build", "status": "COMPLETED", "conclusion": "SUCCESS"}]},
 {"number": 16, "title": "#9: changes asked", "isDraft": false, "updatedAt": "$(half_past_minutes_ago 200)", "mergeable": "MERGEABLE", "reviewDecision": "CHANGES_REQUESTED",
  "statusCheckRollup": []}]
J
run "stalled pull requests: one line each, none missed, each with its right reason" "$work/stalled.json" 0 "#12 idle 90 min: conflicts with its base; failing checks: build
#13 idle 125 min: approved and green, not merged
#14 idle 61 min: checks not finished
#15 idle 70 min: green, waiting for a review
#16 idle 200 min: changes requested, no new push"

open_prs_only_the_oldest_stalled() {
  python3 -I -c 'import json, sys
fresh, old = sys.argv[2], sys.argv[3]
prs = [{"number": n, "isDraft": False, "updatedAt": fresh, "mergeable": "MERGEABLE",
        "reviewDecision": "", "statusCheckRollup": []} for n in range(2, int(sys.argv[1]) + 1)]
prs.append({"number": 1, "isDraft": False, "updatedAt": old, "mergeable": "CONFLICTING",
            "reviewDecision": "", "statusCheckRollup": []})
print(json.dumps(prs))' "$2" "$(half_past_minutes_ago 10)" "$(half_past_minutes_ago 1440)" > "$1"
}

open_prs_only_the_oldest_stalled "$work/many.json" 201
run "201 open, the oldest stalled behind 200 fresh: reported, never dropped by a capped read" "$work/many.json" 0 "#1 idle 1440 min: conflicts with its base"

open_prs_only_the_oldest_stalled "$work/toomany.json" 1001
run "1001 open, more than the check can read: the run fails, never looks quiet" "$work/toomany.json" 2 ""

run "gh fails: the run fails, never read as nothing due" "none" 2 ""

for repo in 'example-org/x"$(touch${IFS}marker)"' 'example-org/`touch marker`' \
  "example-org/x';touch marker;'" 'release/";printf${IFS}WAKE;false${IFS}"' 'example-org/a\cb'; do
  rm -f "$work/marker"
  render_check "$here/../stall-sweep.md" "$work/check.sh" \
    "$(python3 -I -c 'import json, sys; print(json.dumps({"repo": sys.argv[1]}))' "$repo")" || exit 1
  GH_ARGS="$work/args" run "payload repo stays data: $repo" "$work/none.json" 0 ""
  want=$(printf 'pr\nlist\n-R\n%s' "$repo")
  if [ "$(head -n 4 "$work/args")" != "$want" ] || [ -e "$work/marker" ]; then
    printf 'FAIL payload repo reached gh as:\n%s\n' "$(cat "$work/args")"; fail=1
  fi
done

exit $fail
