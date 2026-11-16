---
thread: "same"
id: "in-same"
trigger: {"in": "30m"}
name: "Look again in half an hour"
priority: 1
params: {"hours": 6}
---
Check what changed in the last {{hours}} hours and say it in one line.
