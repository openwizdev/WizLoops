---
id: "allowed-path-absolute"
proof: {"run": "test -f sample/report.txt", "timeout": 30}
allowed_paths: ["/sample/report.txt"]
cadence: {"cron": "0 * * * *", "timezone": "UTC"}
enabled: true
---
The sample report is present.
