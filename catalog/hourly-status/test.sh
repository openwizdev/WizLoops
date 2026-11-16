#!/bin/sh
# Runs hourly-status's check against a stand-in `gh` that serves synthetic
# spec data, and checks the one promise the loop makes: it prints the spec's
# state when it changed since the last posted status line, and nothing
# otherwise, so a quiet hour starts no agent.
#
# Usage, from anywhere: sh catalog/hourly-status/test.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/home" "$work/data"

# The check with its params replaced by the file's synthetic defaults, as an
# adapter replaces them before it applies the loop.
sed -e 's#[{][{]repo[}][}]#example-org/example-repo#g' \
    -e 's#[{][{]spec[}][}]#1#g' \
    "$here/check.sh" > "$work/check.sh"

# A stand-in for `gh`: it prints the synthetic answer for the command the
# check runs (after gh's own --jq), or fails like gh does when GitHub can't
# be read.
cat > "$work/bin/gh" <<'EOF'
#!/bin/sh
[ -f "$FAKE/fail" ] && { echo "gh: could not connect" >&2; exit 1; }
case "$1 $2" in
  "issue view") cat "$FAKE/tickets" ;;
  "pr list") cat "$FAKE/prs" ;;
  *) echo "gh: unexpected: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$work/bin/gh"

fails=0
wake() {
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
posted() { # the agent posted the line and recorded it, as the prompt says
  for f in "$work/home/.wizloops/hourly-status/"*.pending; do [ -e "$f" ] || continue; mv "$f" "${f%.pending}.posted"; done
}

printf '#2 CLOSED\n#3 OPEN\n#4 OPEN\n' > "$work/data/tickets"
printf '12 abc1234 3\n20 fff0000 99\n' > "$work/data/prs"

# catches: the first wake stays quiet, so a spec never gets its first line
due "first wake shows the state" "#12 at abc1234"
# catches: the check prints on every wake (as an always-echo check does), so
# every hour starts an agent even when nothing changed
posted; quiet "nothing changed since the posted line"
# catches: a change is missed, so the status line goes stale
printf '#2 CLOSED\n#3 CLOSED\n#4 OPEN\n' > "$work/data/tickets"
due "a ticket closed" "#3 CLOSED"
# catches: the check marks a change as posted itself, so a run that fails
# before posting loses the change for good
due "not posted yet, still due" "#3 CLOSED"
posted; quiet "posted, quiet again"
# catches: a push to the spec's pull request is not seen as progress
printf '12 abc9999 3\n20 fff0000 99\n' > "$work/data/prs"
due "a pull request moved" "#12 at abc9999"
posted
# catches: another spec's pull request wakes this spec's agent
printf '12 abc9999 3\n20 fff1111 99\n21 eee0000 98\n' > "$work/data/prs"
quiet "another spec's pull request changed"
# catches: GitHub can't be read and the check exits 0 or 1 with no output,
# which reads as a quiet hour and hides the failure
touch "$work/data/fail"
wake
if [ -z "$out" ] && [ "$code" -gt 1 ]; then echo "ok   a failed read fails the run"
else echo "FAIL a failed read fails the run: got exit $code and: $out"; fails=$((fails + 1)); fi

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
echo "all passed"
