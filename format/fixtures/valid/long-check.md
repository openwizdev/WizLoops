---
id: "long-check"
name: "A check that may take two minutes"
trigger: {"cron": "0 6 * * *", "timezone": "UTC"}
check: {"run": "long-check/check.sh", "timeout": 120}
thread: "new"
---
Post a short note on the example repository.
