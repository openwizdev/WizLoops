#!/bin/sh
# workflow-kick: dispatch one GitHub Actions workflow on the loop's schedule.
# A scheduled GitHub workflow can be delayed or skipped; a loop dispatches it
# on time instead. Needs the GitHub CLI (`gh`), signed in with access to run
# workflows in the repository; it uses no secret of the loop's own.
#
# It never prints on standard output, so no agent ever starts. A failed
# dispatch exits 2: the run fails, visibly, instead of passing quietly.
if ! gh workflow run "{{workflow}}" -R "{{repo}}" --ref "{{ref}}" >/dev/null 2>&1; then
  echo "workflow-kick: could not dispatch {{workflow}} in {{repo}} on {{ref}}" >&2
  exit 2
fi
exit 0
