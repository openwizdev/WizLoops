#!/bin/sh
# The check of spec #{{spec}}'s fleet thread in {{repo}}: it runs OpenWiz's
# launch-fleet helper for that spec alone and prints its due lines. Nothing
# due, nothing printed: the wake is quiet and no agent starts.
#
# It needs no loop secret. The loop's thread is "same", so the check runs in
# the fleet thread's own sandbox, with that thread's own gh login and the
# helper's cache, which it keeps between wakes.
#
# A GitHub rate limit is a quiet wake too (one note on stderr; the helper
# itself backs off the same way when the allowance runs low). Any other
# failure prints one "look:" line, which wakes the thread to see why.
GH_REPO='{{repo}}'; export GH_REPO
helper='{{fleet_sh}}'
[ -f "$helper" ] || { echo "look: fleet #{{spec}} check: no launch-fleet helper at $helper"; exit 0; }
err=$(mktemp) || { echo "look: fleet #{{spec}} check: cannot make a temporary file"; exit 0; }
trap 'rm -f "$err"' EXIT
# Stop the helper before the loop's own 60-second limit, so an overrun is
# reported here instead of failing the run.
limit=
command -v timeout > /dev/null 2>&1 && limit='timeout 50'
out=$($limit sh "$helper" spec {{spec}} 2> "$err"); rc=$?
[ -n "$out" ] && printf '%s\n' "$out"
if [ "$rc" -ne 0 ]; then
  if grep -qiE 'rate limit already exceeded|secondary rate limit' "$err"; then
    echo "fleet #{{spec}}: GitHub rate limit; skipping this wake" >&2
  else
    echo "look: fleet #{{spec}} check failed (exit $rc; 124 = timeout): $(tail -n 3 "$err" | tr '\n' ' ' | head -c 400)"
  fi
fi
exit 0
