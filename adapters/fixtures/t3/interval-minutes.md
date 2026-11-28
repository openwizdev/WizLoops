---
id: "interval-minutes"
name: "Triage every ten minutes"
trigger: {"cron": "*/10 * * * *", "timezone": "UTC"}
check: {"run": "interval-minutes/check.sh", "timeout": 60}
thread: "new"
secrets: []
priority: 2
params: {"repo": "example-org/example-repo", "spec": 7, "title": "it's $(touch marker)"}
---
Triage the due items for spec {{spec}} that the check printed.
