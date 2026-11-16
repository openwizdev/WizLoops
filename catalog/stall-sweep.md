---
id: "stall-sweep"
name: "Stall sweep"
trigger: {"cron": "20 * * * *", "timezone": "UTC"}
check: {"run": "stall-sweep/check.sh", "timeout": 60}
thread: "same"
secrets: []
priority: 2
params: {"repo": "example-org/example-repo", "idle_minutes": 60}
---
Stall sweep for {{repo}}. The check below lists each open pull request that
has had no progress for {{idle_minutes}} minutes or more, with why it looks
stalled.

For each line:

1. Read the pull request, its checks and its comments, and confirm the
   reason. If it moved since the check ran, skip it.
2. Name who owns the next step, by the repository's own rules: its builder
   for a conflict, failing checks or requested changes; its reviewer, or
   whoever starts reviews, when it waits for a review; whoever merges when it
   is approved and green; whoever runs CI when its checks never finished.
3. Tell that owner, once, in one short comment on the pull request or a
   message to them: what is waiting, for how long, and why.

Do not merge, review, push or rerun anything yourself unless the
repository's rules make that your job. Your comment counts as progress, so
the next sweep stays quiet about that pull request until it is idle again.
Reply with one line per pull request: its number, the reason and who you
told.
