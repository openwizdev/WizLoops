#!/bin/sh
# Runs stall-sweep's check against a stand-in `gh` that prints synthetic
# pull requests, and checks what the check prints. Needs sh, sed, date and
# python3. Run from anywhere: sh catalog/stall-sweep/test.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
cat > "$work/bin/gh" <<'GH'
#!/bin/sh
[ -f "$FIXTURE" ] || { echo "gh: could not reach GitHub" >&2; exit 1; }
cat "$FIXTURE"
GH
chmod +x "$work/bin/gh"
# The check as an adapter applies it: params replaced by their values.
sed -e 's|{{repo}}|example-org/example-repo|g' -e 's|{{idle_minutes}}|60|g' \
  "$here/check.sh" > "$work/check.sh"

# Half a minute past each whole minute, so a slow run cannot change the count.
ago() { date -u -d "-$(( $1 * 60 + 30 )) seconds" +%Y-%m-%dT%H:%M:%SZ; }
fail=0
# run <name> <fixture file or "none"> <expected exit> <expected stdout>
run() {
  out=$(cd "$work" && FIXTURE="$2" PATH="$work/bin:$PATH" sh ./check.sh 2>/dev/null)
  code=$?
  if [ "$code" != "$3" ] || [ "$out" != "$4" ]; then
    printf 'FAIL %s\n  exit %s, want %s\n  got:  %s\n  want: %s\n' "$1" "$code" "$3" "$out" "$4"
    fail=1
  else
    echo "ok   $1"
  fi
}

# catches: a quiet wake that still prints, so an agent starts for nothing.
echo '[]' > "$work/none.json"
run "no open pull requests: quiet" "$work/none.json" 0 ""

# catches: waking on work that moved recently, or on a draft nobody waits for.
cat > "$work/fresh.json" <<J
[{"number": 3, "title": "#2: fresh", "isDraft": false, "updatedAt": "$(ago 10)", "mergeable": "CONFLICTING", "reviewDecision": "", "statusCheckRollup": []},
 {"number": 4, "title": "#2: a draft", "isDraft": true, "updatedAt": "$(ago 600)", "mergeable": "MERGEABLE", "reviewDecision": "", "statusCheckRollup": []}]
J
run "fresh and draft pull requests: quiet" "$work/fresh.json" 0 ""

# catches: a stalled pull request missed, or reported without the right reason.
cat > "$work/stalled.json" <<J
[{"number": 12, "title": "#5: conflicted and red", "isDraft": false, "updatedAt": "$(ago 90)", "mergeable": "CONFLICTING", "reviewDecision": "",
  "statusCheckRollup": [{"__typename": "CheckRun", "name": "build", "status": "COMPLETED", "conclusion": "FAILURE"},
                        {"__typename": "CheckRun", "name": "lint", "status": "COMPLETED", "conclusion": "SUCCESS"}]},
 {"number": 13, "title": "#6: approved", "isDraft": false, "updatedAt": "$(ago 125)", "mergeable": "MERGEABLE", "reviewDecision": "APPROVED",
  "statusCheckRollup": [{"__typename": "StatusContext", "context": "ci", "state": "SUCCESS"}]},
 {"number": 14, "title": "#7: stuck checks", "isDraft": false, "updatedAt": "$(ago 61)", "mergeable": "MERGEABLE", "reviewDecision": "",
  "statusCheckRollup": [{"__typename": "CheckRun", "name": "build", "status": "QUEUED", "conclusion": ""}]},
 {"number": 15, "title": "#8: nobody reviewed", "isDraft": false, "updatedAt": "$(ago 70)", "mergeable": "MERGEABLE", "reviewDecision": "REVIEW_REQUIRED",
  "statusCheckRollup": [{"__typename": "CheckRun", "name": "build", "status": "COMPLETED", "conclusion": "SUCCESS"}]},
 {"number": 16, "title": "#9: changes asked", "isDraft": false, "updatedAt": "$(ago 200)", "mergeable": "MERGEABLE", "reviewDecision": "CHANGES_REQUESTED",
  "statusCheckRollup": []}]
J
run "stalled pull requests: one line each, with why" "$work/stalled.json" 0 "#12 idle 90 min: conflicts with its base; failing checks: build
#13 idle 125 min: approved and green, not merged
#14 idle 61 min: checks not finished
#15 idle 70 min: green, waiting for a review
#16 idle 200 min: changes requested, no new push"

# catches: an unreachable GitHub read as "nothing is due", hiding every stall.
run "gh fails: the run fails, nothing printed" "none" 2 ""

exit $fail
