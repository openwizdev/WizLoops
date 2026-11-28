---
id: "fixed-time-weekdays"
name: "Weekday review nudge"
trigger: {"cron": "0 9 * * 1-5", "timezone": "UTC"}
thread: "new"
secrets: "all"
---
Ask for a review on each pull request still waiting for one, once.
