---
id: "python-check"
name: "A Python check that reads a param"
trigger: {"cron": "40 7 * * *", "timezone": "UTC"}
check: {"run": "python-check/check.py", "timeout": 60}
thread: "new"
params: {"repo": "example-org/example-repo"}
---
Summarize what the check printed.
