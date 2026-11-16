#!/bin/sh
# workflow-kick: dispatch one GitHub Actions workflow on the loop's schedule.
# A scheduled GitHub workflow can be delayed or skipped; a loop dispatches it
# on time instead. Needs the GitHub CLI (`gh`), signed in with access to run
# workflows in the repository; it uses no secret of the loop's own.
#
# It never prints on standard output, so no agent ever starts. A failed
# dispatch exits 2: the run fails, visibly, instead of passing quietly.
#
# Params are replaced into this text as written, so each one is read only as
# data, from a quoted here-document (no expansion, no quotes to break out of),
# and is used only as one quoted argument. Each value must be one line.

repo=$(cat <<'workflow-kick: end of param'
{{repo}}
workflow-kick: end of param
)
workflow=$(cat <<'workflow-kick: end of param'
{{workflow}}
workflow-kick: end of param
)
ref=$(cat <<'workflow-kick: end of param'
{{ref}}
workflow-kick: end of param
)

nl='
'
for value in "$repo" "$workflow" "$ref"; do
  case $value in
    '' | *"$nl"*)
      echo "workflow-kick: repo, workflow and ref must each be one non-empty line" >&2
      exit 2 ;;
  esac
done

if ! gh workflow run --repo="$repo" --ref="$ref" -- "$workflow" >/dev/null 2>&1; then
  printf 'workflow-kick: could not dispatch %s in %s on %s\n' "$workflow" "$repo" "$ref" >&2
  exit 2
fi
exit 0
