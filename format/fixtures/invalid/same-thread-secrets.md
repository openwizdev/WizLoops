---
id: "same-thread-secrets"
name: "Example loop"
trigger: {"cron": "0 9 * * 1", "timezone": "UTC"}
thread: "same"
secrets: ["EXAMPLE_TOKEN"]
---
Post a short note on the example repository.
