---
id: "params-env"
name: "Params reach the check as data"
trigger: {"cron": "30 6 * * *", "timezone": "UTC"}
check: {"run": "params-env/check.sh", "timeout": 60}
thread: "new"
params: {"repo": "example-org/example-repo", "ref": "release/\";printf${IFS}WAKE;false${IFS}\"", "title": "it's $(touch marker) `touch marker`", "spec": 7, "note": "the check's output"}
---
Report {{note}} for spec {{spec}} in {{repo}}.
