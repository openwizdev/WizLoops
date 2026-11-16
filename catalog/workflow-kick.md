---
id: "workflow-kick"
name: "Kick a workflow on time"
trigger: {"cron": "12 * * * *", "timezone": "UTC"}
check: {"run": "workflow-kick/check.sh", "timeout": 60}
thread: "new"
secrets: []
priority: 3
params: {"repo": "example-org/example-repo", "workflow": "example.yml", "ref": "main"}
---
Nothing to do. This is a script-only loop: its check dispatches the
{{workflow}} workflow in {{repo}} on {{ref}} and never prints anything, so no
agent starts. If you are reading this, the check printed something it should
not have: report that output and change nothing.
