---
id: "same-thread-secrets"
name: "Same thread with a secret"
trigger: {"cron": "30 8 * * 1-5", "timezone": "UTC"}
thread: "same"
secrets: ["EXAMPLE_TOKEN"]
---
Post a short note on the example repository.
