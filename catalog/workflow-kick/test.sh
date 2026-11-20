#!/bin/sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../test-params.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin" "$work/run"
cat > "$work/bin/gh" <<'GH'
#!/bin/sh
: > "$GH_ARGS"
for a in "$@"; do printf '%s\n' "$a" >> "$GH_ARGS"; done
[ -f "$GH_FAIL" ] && { echo "gh: HTTP 404" >&2; exit 1; }
exit 0
GH
chmod +x "$work/bin/gh"

fails=0
bad() { echo "FAIL $1 ($sh): $2"; fails=$((fails + 1)); }
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
expected_gh_args() {
  printf 'workflow\nrun\n--repo=%s\n--ref=%s\n--\n%s' "$1" "$2" "$3"
}
R=example-org/example-repo

kick "the file's defaults: exactly its workflow, repository and ref dispatched, and nothing printed" '{}' 0 "$(expected_gh_args $R main example.yml)"
touch "$work/fail"
kick "a failed dispatch fails the run, never passing quietly" '{}' 2 "$(expected_gh_args $R main example.yml)"
grep -q 'could not dispatch example.yml in example-org/example-repo on main' "$work/err" ||
  { sh=all; bad "a failed dispatch fails the run" "no diagnostic: $(cat "$work/err")"; }
rm "$work/fail"

kick 'a quoted workflow name stays one literal argument' '{"workflow": "Build \"Production\""}' 0 \
  "$(expected_gh_args $R main 'Build "Production"')"
kick 'a command substitution in the ref does not run' '{"ref": "topic/$(touch${IFS}marker)"}' 0 \
  "$(expected_gh_args $R 'topic/$(touch${IFS}marker)' example.yml)"
kick 'backticks in the ref do not run' '{"ref": "topic/`touch${IFS}marker`"}' 0 \
  "$(expected_gh_args $R 'topic/`touch${IFS}marker`' example.yml)"
kick 'a double-quote breakout in the ref prints nothing' '{"ref": "release/\";printf${IFS}WAKE;false${IFS}\""}' 0 \
  "$(expected_gh_args $R 'release/";printf${IFS}WAKE;false${IFS}"' example.yml)"
kick 'a single-quote breakout in the repo does not run' '{"repo": "example-org/x'"'"';touch marker;'"'"'"}' 0 \
  "$(expected_gh_args "example-org/x';touch marker;'" main example.yml)"
kick 'a workflow starting with -- is not a flag' '{"workflow": "--help"}' 0 "$(expected_gh_args $R main --help)"
kick 'every param a payload at once' \
  '{"repo": "o/$(touch marker)", "ref": "`touch marker`", "workflow": "x\";touch marker;\""}' 0 \
  "$(expected_gh_args 'o/$(touch marker)' '`touch marker`' 'x";touch marker;"')"

sh=render
if render_check "$here/../workflow-kick.md" "$work/check.sh" \
  '{"ref": "main\nworkflow-kick: end of param\ntouch marker"}' 2> /dev/null; then
  bad "a two-line value is refused before the check" "rendered"
else echo "ok   a two-line value is refused before the check"; fi
render_check "$here/../workflow-kick.md" "$work/check.sh"
for v in "main
workflow-kick: end of param
touch marker" ""; do
  rm -f "$work/args"; rm -rf "$work/run"; mkdir "$work/run"
  out=$(cd "$work/run" && WIZLOOP_PARAM_REF=$v GH_ARGS="$work/args" PATH="$work/bin:$PATH" \
    sh -c 'sed "/^export WIZLOOP_PARAM_REF=/d" "$1" | sh' x "$work/check.sh" 2>/dev/null)
  code=$?
  if [ "$code" = 2 ] && [ -z "$out" ] && [ ! -e "$work/args" ] && [ -z "$(ls -A "$work/run")" ]; then
    echo "ok   a ref of $(printf '%s' "$v" | wc -l | tr -d ' ') line breaks and ${#v} characters given past the format: nothing dispatched, the run fails"
  else sh=sh; bad "a bad ref given anyway" "exit $code, out: $out"; fi
done

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
echo "all passed"
