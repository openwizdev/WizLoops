---
id: "fixed-time-daily"
name: "Morning digest"
trigger: {"cron": "45 8 * * *", "timezone": "UTC"}
check: {"run": "fixed-time-daily/check.sh", "timeout": 120}
thread: "same"
agent: {"provider": "example-provider", "model": "example-model", "reasoning": "medium"}
---
Send the owner the digest the check printed.
