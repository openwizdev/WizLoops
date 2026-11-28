---
id: "check-start"
name: "A check with no #! line"
trigger: {"cron": "*/30 * * * *", "timezone": "UTC"}
check: {"run": "check-start/check.sh", "timeout": 60}
thread: "new"
---
Act on what the check printed.
