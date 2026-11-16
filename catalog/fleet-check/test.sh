#!/bin/sh
# Runs fleet-check's check, rendered as the Cloudroom adapter renders it
# (catalog/test-params.sh), against a stand-in launch-fleet helper, and
# checks what the loop promises: the helper's due lines wake the fleet
# thread, nothing due or a rate limit is a quiet wake, and any other failure
# prints one "look:" line. Its params reach the helper as data.
# Needs python3. Usage, from anywhere: sh catalog/fleet-check/test.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../test-params.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/run"

# helper <path>: a stand-in fleet.sh that records its arguments and GH_REPO,
# then prints $HELPER_OUT, writes $HELPER_ERR to stderr and exits $HELPER_RC.
helper() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'H'
for a in "$@"; do printf '%s\n' "$a"; done > "$RECORD"
printf 'GH_REPO=%s\n' "$GH_REPO" >> "$RECORD"
[ -n "$HELPER_OUT" ] && printf '%s\n' "$HELPER_OUT"
[ -n "$HELPER_ERR" ] && printf '%s\n' "$HELPER_ERR" >&2
exit "$HELPER_RC"
H
}
json() { python3 -I -c 'import json, sys; print(json.dumps(dict(zip(sys.argv[1::2], sys.argv[2::2]))))' "$@"; }

fails=0
# wake <case> <params JSON> <want stdout> [<want recorded args and GH_REPO>]
wake() {
  render_check "$here/../fleet-check.md" "$work/check.sh" "$2" || { echo "FAIL $1: not rendered"; fails=$((fails + 1)); return; }
  rm -f "$work/record"; rm -rf "$work/run"; mkdir "$work/run"
  out=$(cd "$work/run" && RECORD="$work/record" HELPER_OUT=${out_lines-} HELPER_ERR=${err_lines-} \
    HELPER_RC=${rc-0} sh "$work/check.sh" 2> "$work/err")
  code=$?
  if [ "$code" != 0 ]; then printf 'FAIL %s: exit %s\n' "$1" "$code"; fails=$((fails + 1))
  elif [ "$out" != "$3" ]; then printf 'FAIL %s\n  got:  %s\n  want: %s\n' "$1" "$out" "$3"; fails=$((fails + 1))
  elif [ $# -ge 4 ] && [ "$(cat "$work/record" 2>/dev/null)" != "$4" ]; then
    printf 'FAIL %s: the helper got: %s\n' "$1" "$(cat "$work/record" 2>/dev/null)"; fails=$((fails + 1))
  elif [ -n "$(ls -A "$work/run")" ]; then printf 'FAIL %s: a payload ran\n' "$1"; fails=$((fails + 1))
  else printf 'ok   %s\n' "$1"; fi
}
H="$work/openwiz/skills/launch-fleet/scripts/fleet.sh"
helper "$H"
P=$(json fleet_sh "$H")
R='spec
1
GH_REPO=example-org/example-repo'

# catches: a wake with nothing due that still prints, so the fleet thread
# is prompted for nothing
wake "nothing due: quiet" "$P" "" "$R"
# catches: due lines lost, or the helper asked about another spec or repository
out_lines='due: #2 ready for a builder'
wake "due lines wake the thread" "$P" "due: #2 ready for a builder" "$R"
# catches: a rate limit waking the thread every ten minutes for nothing
out_lines= err_lines='gh: API rate limit already exceeded for user' rc=1
wake "a rate limit is a quiet wake" "$P" ""
grep -q 'fleet #1: GitHub rate limit; skipping this wake' "$work/err" ||
  { echo "FAIL a rate limit is a quiet wake: no note on stderr"; fails=$((fails + 1)); }
# catches: a broken helper read as a quiet wake, so the fleet stalls unseen
err_lines='fleet.sh: cannot parse the plan' rc=3
wake "any other failure prints one look line" "$P" "look: fleet #1 check failed (exit 3; 124 = timeout): fleet.sh: cannot parse the plan "
err_lines= rc=0
# catches: a missing helper read as a quiet wake
wake "no helper prints one look line" "$(json fleet_sh "$work/missing/fleet.sh")" \
  "look: fleet #1 check: no launch-fleet helper at $work/missing/fleet.sh"

# The payloads from the review of workflow-kick's first pull request.
# catches: a param value read as shell code, which could run commands with
# the fleet thread's GitHub access or print and wake the thread.
for v in 'example-org/x"$(touch${IFS}marker)"' 'example-org/`touch marker`' \
  "example-org/x';touch marker;'" 'release/";printf${IFS}WAKE;false${IFS}"' 'example-org/a\cb'; do
  wake "payload repo stays data: $v" "$(json fleet_sh "$H" repo "$v")" "" "spec
1
GH_REPO=$v"
done
weird="$work/it's \$(touch marker) \`touch marker\`/fleet.sh"
helper "$weird"
wake "payload helper path stays data" "$(json fleet_sh "$weird")" "" "$R"
wake "payload spec stays one argument" "$(json fleet_sh "$H" spec '1;touch marker $(touch marker)')" "" \
  'spec
1;touch marker $(touch marker)
GH_REPO=example-org/example-repo'

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
echo "all passed"
