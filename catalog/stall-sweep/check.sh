#!/bin/sh
# stall-sweep's check: prints one line per open pull request in {{repo}}
# that has had no progress for {{idle_minutes}} minutes or more, with why it
# looks stalled. Prints nothing when nothing is stalled, so no agent starts.
# Any update counts as progress: a push, a comment, a review or a label.
# A read that fails, or that cannot list every open pull request (more than
# 1000), fails the run (exit 2) rather than looking quiet.
set -u
prs=$(timeout 40 gh pr list -R "{{repo}}" --state open --limit 1001 \
  --json number,isDraft,updatedAt,mergeable,reviewDecision,statusCheckRollup) || {
  echo "stall-sweep: could not list pull requests in {{repo}}" >&2
  exit 2
}
printf '%s' "$prs" | python3 -I -c '
import datetime, json, sys
idle_limit = int(sys.argv[1])
now = datetime.datetime.now(datetime.timezone.utc)
prs = json.load(sys.stdin)
if len(prs) > 1000:
    sys.stderr.write("stall-sweep: more than 1000 open pull requests; cannot read them all\n")
    sys.exit(2)
bad = ("FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE")
for p in sorted(prs, key=lambda p: p["number"]):
    if p["isDraft"]:
        continue
    updated = datetime.datetime.fromisoformat(p["updatedAt"].replace("Z", "+00:00"))
    idle = int((now - updated).total_seconds() // 60)
    if idle < idle_limit:
        continue
    failing, running = [], False
    for c in p.get("statusCheckRollup") or []:
        if c.get("__typename") == "StatusContext":
            state, name = c.get("state"), c.get("context")
            if state in bad:
                failing.append(name)
            elif state in ("PENDING", "EXPECTED"):
                running = True
        elif c.get("status") != "COMPLETED":
            running = True
        elif c.get("conclusion") in bad:
            failing.append(c.get("name"))
    why = []
    if p.get("mergeable") == "CONFLICTING":
        why.append("conflicts with its base")
    if failing:
        why.append("failing checks: " + ", ".join(failing))
    elif running:
        why.append("checks not finished")
    if not why:
        decision = p.get("reviewDecision")
        if decision == "APPROVED":
            why.append("approved and green, not merged")
        elif decision == "CHANGES_REQUESTED":
            why.append("changes requested, no new push")
        else:
            why.append("green, waiting for a review")
    print("#%d idle %d min: %s" % (p["number"], idle, "; ".join(why)))
' "{{idle_minutes}}" || exit 2
