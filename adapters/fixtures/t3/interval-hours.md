---
id: "interval-hours"
name: "Status every two hours"
trigger: {"cron": "15 */2 * * *", "timezone": "UTC"}
thread: "same"
---
Post one status line, only if something changed.
