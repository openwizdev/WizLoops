---
id: "secrets-env"
name: "Only the project env files"
trigger: {"cron": "*/30 * * * *", "timezone": "UTC"}
thread: "new"
secrets: [".env"]
---
Look for new work.
