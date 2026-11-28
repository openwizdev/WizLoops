---
id: "docs-truth"
name: "Docs truth"
trigger: {"cron": "25 4 * * *", "timezone": "UTC"}
check: {"run": "docs-truth/check.sh", "timeout": 60}
thread: "new"
secrets: []
priority: 3
params: {"sources": "{\"docs\":{\"example-org/example-repo\":[\"README.md\",\"docs/\"]},\"help\":{\"example-cli\":[\"example-org/example-repo\",\"cli/help.json\"]}}"}
---
The docs-truth check reads the configured repositories at main, files an
issue on the source repository for each drift and closes its own resolved
issues. It does all the work without waking an agent. If you are reading
this, report the unexpected check output and leave the repositories alone.
