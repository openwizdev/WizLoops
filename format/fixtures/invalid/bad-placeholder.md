---
id: "bad-placeholder"
name: "Example loop"
trigger: {"cron": "0 9 * * 1", "timezone": "UTC"}
thread: "new"
params: {"repo": "example-org/example-repo"}
---
Post a note on {{repo}} and {{ repo }}.
