---
id: "webhook-prompt"
name: "A param T3 would fill in"
trigger: {"webhook": true}
thread: "new"
params: {"field": "{{body.action}}"}
---
Read {{field}} and act on it.
