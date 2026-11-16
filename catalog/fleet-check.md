---
id: "fleet-check"
name: "Fleet check for one spec"
trigger: {"cron": "*/10 * * * *", "timezone": "UTC"}
check: {"run": "fleet-check/check.sh", "timeout": 60}
thread: "same"
secrets: []
priority: 2
params: {"repo": "example-org/example-repo", "spec": 1, "fleet_sh": "/home/example/openwiz/skills/launch-fleet/scripts/fleet.sh"}
---
Fleet thread for spec #{{spec}} of {{repo}}: do the launch-fleet skill's step 2 for the due lines below, as its Fleet threads section says.
