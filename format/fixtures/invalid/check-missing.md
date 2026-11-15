---
id: "check-missing"
name: "Example loop"
trigger: {"cron": "0 9 * * 1", "timezone": "UTC"}
thread: "new"
check: {"run": "check-missing/check.sh", "timeout": 30}
---
Post a short note on the example repository.
