---
id: "cadence-hourly"
proof: {"run": "test -f sample/report.txt", "timeout": 30}
allowed_paths: ["sample/report.txt", "examples/"]
cadence: {"cron": "*/60 * * * *", "timezone": "UTC"}
enabled: true
---
The sample report is present.
