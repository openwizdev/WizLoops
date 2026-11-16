---
id: "timeout-too-long"
name: "Example loop"
trigger: {"cron": "0 9 * * 1", "timezone": "UTC"}
thread: "new"
check: {"run": "timeout-too-long/check.sh", "timeout": 901}
---
Post a short note on the example repository.
