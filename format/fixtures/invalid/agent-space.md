---
id: "agent-space"
name: "Example loop"
trigger: {"cron": "0 9 * * 1", "timezone": "UTC"}
thread: "new"
agent: {"provider": "example-provider", "model": "example model", "reasoning": "low"}
---
Post a short note on the example repository.
