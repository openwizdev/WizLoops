---
id: "cadence"
proof: {"run": "test -f sample/report.txt", "timeout": 30}
allowed_paths: ["sample/report.txt", "examples/"]
cadence: "hourly"
enabled: true
---
The sample report is present.
