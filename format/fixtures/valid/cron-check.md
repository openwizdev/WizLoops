---
id: "cron-check"
name: "Example triage every ten minutes"
trigger: {"cron": "*/10 * * * *", "timezone": "UTC"}
check: {"run": "cron-check/check.sh", "timeout": 60}
thread: "new"
agent: {"provider": "example-provider", "model": "example-model", "reasoning": "medium"}
secrets: ["EXAMPLE_TOKEN", ".env"]
priority: 2
params: {"repo": "example-org/example-repo", "spec": 42}
---
Triage the due items for spec {{spec}} that the check printed below.
