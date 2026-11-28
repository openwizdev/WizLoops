---
id: "timeout-max"
proof: {"run": "test -f sample/report.txt", "timeout": 601}
allowed_paths: ["sample/report.txt", "examples/"]
cadence: {"cron": "0 * * * *", "timezone": "UTC"}
enabled: true
---
The sample report is present.
