---
id: "cadence-timezone"
proof: {"run": "test -f sample/report.txt", "timeout": 30}
allowed_paths: ["sample/report.txt", "examples/"]
cadence: {"cron": "0 9 * * 1-5", "timezone": "America/Los_Angeles"}
enabled: true
---
The sample report is present.
