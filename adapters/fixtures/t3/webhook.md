---
id: "webhook"
name: "Wake on a delivery"
trigger: {"webhook": true}
thread: "new"
params: {"repo": "example-org/example-repo"}
---
A delivery arrived for {{repo}}. Read its newest issue and label it.
