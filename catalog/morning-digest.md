---
id: "morning-digest"
name: "Morning digest"
trigger: {"cron": "45 8 * * *", "timezone": "America/Los_Angeles"}
check: {"run": "morning-digest/check.sh", "timeout": 60}
thread: "same"
secrets: []
priority: 3
params: {"org": "example-org", "owner": "example-owner"}
---
It is the morning digest for {{owner}}, who checks in soon. The check below
listed what changed in the last 24 hours across the repositories of the
GitHub account {{org}}: each pull request that merged, each open pull request
whose checks fail, and each open item waiting on {{owner}} (a review they are
asked for, or an issue assigned to them).

Prepare the digest from that list and what you can read on GitHub:

1. **Merged:** what landed in the last 24 hours, grouped by repository, and
   how it compares with the plan you or {{owner}} wrote down yesterday, if
   there is one.
2. **Stuck:** what is failing or waiting with no progress, and why, in one
   line each.
3. **Waiting on {{owner}}:** every item that needs them, each with its link,
   so nothing that needs them is left out.

Keep it short and plain. Report only what you read; never guess a state you
did not check. If the check says GitHub could not be read, say so first.
Change nothing: this loop only reports.
