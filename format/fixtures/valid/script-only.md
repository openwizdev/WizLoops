---
id: "script-only"
name: "Kick an example job hourly"
trigger: {"cron": "12 * * * *", "timezone": "America/Los_Angeles"}
check: {"run": "script-only/check.sh", "timeout": 30}
thread: "new"
---
Nothing to do: the check does the work and prints nothing.
