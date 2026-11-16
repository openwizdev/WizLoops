---
id: "undeclared-param-env"
name: "Example loop"
trigger: {"cron": "0 9 * * 1", "timezone": "UTC"}
thread: "new"
check: {"run": "undeclared-param-env/check.sh", "timeout": 30}
params: {"repo": "example-org/example-repo"}
---
Post a short note on the example repository.
