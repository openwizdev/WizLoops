---
id: "short-check"
name: "A check with a thirty-second bound"
trigger: {"cron": "0 7 * * *", "timezone": "UTC"}
check: {"run": "short-check/check.sh", "timeout": 30}
thread: "new"
---
Post a short note on the example repository.
