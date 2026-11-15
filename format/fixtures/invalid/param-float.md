---
id: "param-float"
name: "Example loop"
trigger: {"cron": "0 9 * * 1", "timezone": "UTC"}
thread: "new"
params: {"hours": 1.5}
---
Look back {{hours}} hours.
