#!/bin/sh
GH_REPO=$WIZLOOP_PARAM_REPO; export GH_REPO
spec=$WIZLOOP_PARAM_SPEC
helper=$WIZLOOP_PARAM_FLEET_SH
[ -f "$helper" ] || { printf 'look: fleet #%s check: no launch-fleet helper at %s\n' "$spec" "$helper"; exit 0; }
err=$(mktemp) || { printf 'look: fleet #%s check: cannot make a temporary file\n' "$spec"; exit 0; }
trap 'rm -f "$err"' EXIT
stop_before_the_loops_60s_limit=
command -v timeout > /dev/null 2>&1 && stop_before_the_loops_60s_limit='timeout 50'
out=$($stop_before_the_loops_60s_limit sh "$helper" spec "$spec" 2> "$err"); rc=$?
[ -n "$out" ] && printf '%s\n' "$out"
if [ "$rc" -ne 0 ]; then
  if grep -qiE 'rate limit already exceeded|secondary rate limit' "$err"; then
    printf 'fleet #%s: GitHub rate limit; skipping this wake\n' "$spec" >&2
  else
    printf 'look: fleet #%s check failed (exit %s; 124 = timeout): %s\n' "$spec" "$rc" "$(tail -n 3 "$err" | tr '\n' ' ' | head -c 400)"
  fi
fi
exit 0
