---
id: "timeout-min"
proof: {"run": "test -f sample/report.txt", "timeout": 1}
allowed_paths: ["sample/report.txt", "examples/"]
cadence: {"cron": "0 * * * *", "timezone": "UTC"}
enabled: true
---
The sample report is present.
