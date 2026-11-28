---
id: "proof"
proof: "test -f sample/report.txt"
allowed_paths: ["sample/report.txt", "examples/"]
cadence: {"cron": "0 * * * *", "timezone": "UTC"}
enabled: true
---
The sample report is present.
