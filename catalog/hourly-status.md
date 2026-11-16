---
id: "hourly-status"
name: "Hourly status line, only when something changed"
trigger: {"cron": "15 * * * *", "timezone": "UTC"}
check: {"run": "hourly-status/check.sh", "timeout": 60}
thread: "same"
secrets: []
priority: 2
params: {"repo": "example-org/example-repo", "spec": 1, "status_repo": "example-org/example-tracker", "status_issue": 1}
---
You manage spec {{spec}} in {{repo}}. This hour's check found that its
tickets or their pull requests changed since your last status line; its
output is below.

1. Write one status line for spec {{spec}}, from the check's output and what
   you know of the spec: tickets merged out of the total, which are in
   review, which are being built, and what blocks any that wait. Start it
   with `Status for spec {{spec}}:`. Say nothing the output and the spec's
   own records do not show.
2. Post it as one comment on issue {{status_issue}} in {{status_repo}}.
3. Only once the comment is posted, run the `mv` line the check printed, so
   the next quiet hour stays quiet. If the post failed, leave the file: the
   next hour shows the same change again.

Post nothing else and change nothing else. Public comments carry no thread
ids, private names or exact words of a private decision.

This loop grants no secrets (`secrets: []`). It runs in the thread that
applied it, so its check and this run use that thread's own `gh` login to
read {{repo}} and to post on {{status_repo}}.
