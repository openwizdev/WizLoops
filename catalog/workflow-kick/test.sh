#!/bin/sh
# Runs workflow-kick's check, rendered as the Cloudroom adapter renders it
# (catalog/test-params.sh), against a stand-in `gh` that records its
# arguments, under dash, bash and bash --posix. It checks the loop's one
# promise: it dispatches exactly the workflow, repository and ref it is
# given, as data, and never prints, so no agent ever starts. Every injection
# payload from the review of this loop's first pull request is a case.
# Needs python3. Usage, from anywhere: sh catalog/workflow-kick/test.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../test-params.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin" "$work/run"
cat > "$work/bin/gh" <<'GH'
#!/bin/sh
# Records each argument on its own line; fails when asked to.
: > "$GH_ARGS"
for a in "$@"; do printf '%s\n' "$a" >> "$GH_ARGS"; done
[ -f "$GH_FAIL" ] && { echo "gh: HTTP 404" >&2; exit 1; }
exit 0
GH
chmod +x "$work/bin/gh"

fails=0
bad() { echo "FAIL $1 ($sh): $2"; fails=$((fails + 1)); }
# kick <case> <params JSON> <expected exit> <expected gh arguments, one per
# line, or "" for none>: renders the check, runs it in an empty folder, and
# checks stdout is empty, the exit code, gh's exact arguments, and that no
# payload made a file.
kick() {
  if ! render_check "$here/../workflow-kick.md" "$work/check.sh" "$2" 2> "$work/render"; then
    bad "$1" "not rendered: $(cat "$work/render")"; return
  fi
  for sh in dash bash "bash --posix"; do
    rm -f "$work/args"; rm -rf "$work/run"; mkdir "$work/run"
    out=$(cd "$work/run" && GH_ARGS="$work/args" GH_FAIL="$work/fail" PATH="$work/bin:$PATH" \
      $sh "$work/check.sh" 2> "$work/err")
    code=$?
    got=$(cat "$work/args" 2>/dev/null)
    if [ -n "$out" ]; then bad "$1" "printed (an agent would start): $out"
    elif [ "$code" != "$3" ]; then bad "$1" "exit $code, want $3: $(cat "$work/err")"
    elif [ "$got" != "$4" ]; then bad "$1" "gh got: $got"
    elif [ -n "$(ls -A "$work/run")" ]; then bad "$1" "a payload ran: $(ls -A "$work/run")"
    else continue; fi
    return
  done
  echo "ok   $1"
}
args() { # <repo> <ref> <workflow>: the arguments gh must receive
  printf 'workflow\nrun\n--repo=%s\n--ref=%s\n--\n%s' "$1" "$2" "$3"
}
R=example-org/example-repo

# catches: a dispatch that is not exactly the file's workflow, repository and
# ref, or a check that prints and so starts an agent
kick "the file's defaults: dispatched exactly, quietly" '{}' 0 "$(args $R main example.yml)"
# catches: a failed dispatch passing quietly, so a broken kick goes unseen
touch "$work/fail"
kick "a failed dispatch fails the run" '{}' 2 "$(args $R main example.yml)"
grep -q 'could not dispatch example.yml in example-org/example-repo on main' "$work/err" ||
  { sh=all; bad "a failed dispatch fails the run" "no diagnostic: $(cat "$work/err")"; }
rm "$work/fail"

# The review's payloads. catches: a param value read as shell code, which
# could run commands with the check's GitHub access or print and wake an agent.
kick 'a quoted workflow name stays one literal argument' '{"workflow": "Build \"Production\""}' 0 \
  "$(args $R main 'Build "Production"')"
kick 'a command substitution in the ref does not run' '{"ref": "topic/$(touch${IFS}marker)"}' 0 \
  "$(args $R 'topic/$(touch${IFS}marker)' example.yml)"
kick 'backticks in the ref do not run' '{"ref": "topic/`touch${IFS}marker`"}' 0 \
  "$(args $R 'topic/`touch${IFS}marker`' example.yml)"
kick 'a double-quote breakout in the ref prints nothing' '{"ref": "release/\";printf${IFS}WAKE;false${IFS}\""}' 0 \
  "$(args $R 'release/";printf${IFS}WAKE;false${IFS}"' example.yml)"
kick 'a single-quote breakout in the repo does not run' '{"repo": "example-org/x'"'"';touch marker;'"'"'"}' 0 \
  "$(args "example-org/x';touch marker;'" main example.yml)"
kick 'a workflow starting with -- is not a flag' '{"workflow": "--help"}' 0 "$(args $R main --help)"
kick 'every param a payload at once' \
  '{"repo": "o/$(touch marker)", "ref": "`touch marker`", "workflow": "x\";touch marker;\""}' 0 \
  "$(args 'o/$(touch marker)' '`touch marker`' 'x";touch marker;"')"

# catches: a two-line value reaching the check, where the old here-document
# form let its second line end the param early and run its third
sh=render
if render_check "$here/../workflow-kick.md" "$work/check.sh" \
  '{"ref": "main\nworkflow-kick: end of param\ntouch marker"}' 2> /dev/null; then
  bad "a two-line value is refused before the check" "rendered"
else echo "ok   a two-line value is refused before the check"; fi
# catches: the check trusting the format alone; given a two-line or empty
# value anyway, it must dispatch nothing and fail the run
render_check "$here/../workflow-kick.md" "$work/check.sh"
for v in "main
workflow-kick: end of param
touch marker" ""; do
  rm -f "$work/args"; rm -rf "$work/run"; mkdir "$work/run"
  out=$(cd "$work/run" && WIZLOOP_PARAM_REF=$v GH_ARGS="$work/args" PATH="$work/bin:$PATH" \
    sh -c 'sed "/^export WIZLOOP_PARAM_REF=/d" "$1" | sh' x "$work/check.sh" 2>/dev/null)
  code=$?
  if [ "$code" = 2 ] && [ -z "$out" ] && [ ! -e "$work/args" ] && [ -z "$(ls -A "$work/run")" ]; then
    echo "ok   a ref of $(printf '%s' "$v" | wc -l | tr -d ' ') line breaks and ${#v} characters: nothing dispatched, the run fails"
  else sh=sh; bad "a bad ref given anyway" "exit $code, out: $out"; fi
done

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
echo "all passed"
