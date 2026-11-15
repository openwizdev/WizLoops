---
id: "same-thread-agent"
name: "Same thread with its own agent"
trigger: {"cron": "0 * * * *", "timezone": "UTC"}
check: {"run": "same-thread-agent/check.sh", "timeout": 60}
thread: "same"
agent: {"provider": "example-provider", "model": "example-model", "reasoning": "high"}
---
Post a short note on the example repository.
