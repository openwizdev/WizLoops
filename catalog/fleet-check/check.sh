#!/bin/sh
# The check of one spec's fleet thread: it runs OpenWiz's launch-fleet
# helper for that spec alone and prints its due lines. Nothing
# due, nothing printed: the wake is quiet and no agent starts.
#
# It needs no loop secret. The loop's thread is "same", so the check runs in
# the fleet thread's own sandbox, with that thread's own gh login and the
# helper's cache, which it keeps between wakes.
#
# A GitHub rate limit is a quiet wake too (one note on stderr; the helper
# itself backs off the same way when the allowance runs low). Any other
# failure prints one "look:" line, which wakes the thread to see why.
#
# Its params arrive as data, in the environment: WIZLOOP_PARAM_REPO,
# WIZLOOP_PARAM_SPEC and WIZLOOP_PARAM_FLEET_SH (the helper's path).
GH_REPO=$WIZLOOP_PARAM_REPO; export GH_REPO
spec=$WIZLOOP_PARAM_SPEC
helper=$WIZLOOP_PARAM_FLEET_SH
[ -f "$helper" ] || { printf 'look: fleet #%s check: no launch-fleet helper at %s\n' "$spec" "$helper"; exit 0; }
err=$(mktemp) || { printf 'look: fleet #%s check: cannot make a temporary file\n' "$spec"; exit 0; }
trap 'rm -f "$err"' EXIT
# Stop the helper before the loop's own 60-second limit, so an overrun is
# reported here instead of failing the run.
limit=
command -v timeout > /dev/null 2>&1 && limit='timeout 50'
out=$($limit sh "$helper" spec "$spec" 2> "$err"); rc=$?
[ -n "$out" ] && printf '%s\n' "$out"
if [ "$rc" -ne 0 ]; then
  if grep -qiE 'rate limit already exceeded|secondary rate limit' "$err"; then
    printf 'fleet #%s: GitHub rate limit; skipping this wake\n' "$spec" >&2
  else
    printf 'look: fleet #%s check failed (exit %s; 124 = timeout): %s\n' "$spec" "$rc" "$(tail -n 3 "$err" | tr '\n' ' ' | head -c 400)"
  fi
fi
exit 0
