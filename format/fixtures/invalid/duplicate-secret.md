---
id: "duplicate-secret"
name: "Example loop"
trigger: {"cron": "0 9 * * 1", "timezone": "UTC"}
thread: "new"
secrets: ["EXAMPLE_TOKEN", "EXAMPLE_TOKEN"]
---
Post a short note on the example repository.
