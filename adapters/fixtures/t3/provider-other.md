---
id: "provider-other"
name: "Another provider"
trigger: {"cron": "*/30 * * * *", "timezone": "UTC"}
thread: "new"
agent: {"provider": "other-provider", "model": "example-model", "reasoning": "medium"}
---
Look for new work.
