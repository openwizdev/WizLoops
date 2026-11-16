---
id: "unknown-agent-key"
name: "Example loop"
trigger: {"cron": "0 9 * * 1", "timezone": "UTC"}
thread: "new"
agent: {"provider": "example-provider", "model": "example-model", "reasoning": "low", "service_tier": "fast"}
---
Post a short note on the example repository.
