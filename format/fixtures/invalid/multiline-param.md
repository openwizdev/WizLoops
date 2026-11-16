---
id: "multiline-param"
name: "Example loop"
trigger: {"cron": "0 9 * * 1", "timezone": "UTC"}
thread: "new"
params: {"ref": "main\nexample: end of param\ntouch marker"}
---
Post a short note on the {{ref}} branch.
