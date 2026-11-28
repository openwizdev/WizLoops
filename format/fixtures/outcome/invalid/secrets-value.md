---
id: "secrets-value"
proof: {"run": "test -f sample/report.txt", "timeout": 30}
allowed_paths: ["sample/report.txt", "examples/"]
cadence: {"cron": "0 * * * *", "timezone": "UTC"}
enabled: false
secrets: ["EXAMPLE_REPORT_KEY=synthetic-value"]
---
The sample report is present.
