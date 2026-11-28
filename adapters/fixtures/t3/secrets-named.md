---
id: "secrets-named"
name: "Only one token"
trigger: {"cron": "*/30 * * * *", "timezone": "UTC"}
thread: "new"
secrets: ["EXAMPLE_TOKEN"]
---
Look for new work.
