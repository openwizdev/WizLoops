#!/bin/sh

repo=${WIZLOOP_PARAM_REPO-}
workflow=${WIZLOOP_PARAM_WORKFLOW-}
ref=${WIZLOOP_PARAM_REF-}

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
