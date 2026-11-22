#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

pull_request_ci() {
  name=$1 path=$2 line=$3
  repo="$tmp/$name"
  git init -q -b main "$repo"
  cd "$repo"
  git config user.email ci@example.com
  git config user.name ci
  mkdir -p "$(dirname "$path")"
  printf '#!/bin/sh\necho base\n' > "$path"
  git add -A && git commit -q -m base
  git checkout -q -b pr
  printf '#!/bin/sh\n%s\necho base\n' "$line" > "$path"
  git commit -q -am pr
  git checkout -q main
  git merge -q --no-ff -m merge pr
  set +e
  out=$(sh "$root/ci/comment-check.sh" HEAD^1 2>&1)
  code=$?
  set -e
  cd "$root"
}

workflow=$root/.github/workflows/checks.yml
no_fetch=$tmp/no-fetch.yml
sed '/git fetch/d' "$workflow" > "$no_fetch"
tolerant=$tmp/tolerant.yml
awk '{ print } /^ *- name: comment-check *$/ { match($0, /^ */); print substr($0, 1, RLENGTH) "  continue-on-error: true" }' "$workflow" > "$tolerant"
for copy in "$no_fetch" "$tolerant"; do
  if cmp -s "$workflow" "$copy"; then
    echo "test-comment-check: could not make $(basename "$copy") from $workflow" >&2
    exit 1
  fi
done

workflow_step() {
  repo="$tmp/$1" wf=$2
  step_if=$(awk '
    /^ *- name: comment-check *$/ { s = 1; ind = index($0, "-"); next }
    s && /^ *- / && index($0, "-") <= ind { exit }
    s && /^ *if: / { sub(/^ *if: */, ""); print; exit }
  ' "$wf")
  step_run=$(awk '
    /^ *- name: comment-check *$/ { s = 1; ind = index($0, "-"); next }
    s && /^ *- / && index($0, "-") <= ind { exit }
    r { match($0, /^ */); if ($0 !~ /^ *$/ && RLENGTH < k) exit; print; next }
    s && /^ *run: *\| *$/ { r = 1; k = index($0, "r"); next }
  ' "$wf")
  cd "$repo"
  mkdir -p ci tools/comment-check
  cp "$root/ci/comment-check.sh" ci/
  cp "$root/tools/comment-check/check.py" tools/comment-check/
  git remote get-url origin > /dev/null 2>&1 || git remote add origin "file://$repo"
  set +e
  if [ "$step_if" != "github.event_name == 'pull_request'" ] || [ -z "$step_run" ]; then
    out="no comment-check step that runs on pull requests in $wf (if: '$step_if')"
    code=missing
  else
    out=$(GITHUB_SHA=$(git rev-parse HEAD) bash -e -c "$step_run" 2>&1)
    code=$?
  fi
  set -e
  cd "$root"
}

expect() {
  case=$1 want_code=$2 want_text=$3
  if [ "$code" != "$want_code" ] || { [ -n "$want_text" ] && ! printf '%s' "$out" | grep -q -F -- "$want_text"; }; then
    printf 'test-comment-check: %s: expected exit %s and "%s", got exit %s:\n%s\n' \
      "$case" "$want_code" "$want_text" "$code" "$out" >&2
    failures=$((failures + 1))
  else
    echo "ok: $case"
  fi
}

pull_request_ci disallowed catalog/x/check.sh '# a plain comment'
expect 'catches: a pull request adding a disallowed comment passes CI' 1 'catalog/x/check.sh:2: comment:'
workflow_step disallowed "$workflow"
expect 'catches: the pull request workflow passes a disallowed comment' 1 'catalog/x/check.sh:2: comment:'
workflow_step disallowed "$no_fetch"
expect 'catches: the workflow proof passes a comment-check step that never fetches the merge parents' 2 'HEAD^1'
workflow_step disallowed "$tolerant"
expect 'catches: the workflow proof passes a comment-check step that tolerates its own failure' tolerated 'continue-on-error: true'

pull_request_ci escaped catalog/x/check.sh '# comment-ok: the runner reads this line'
expect 'catches: a reasoned escape tag still fails CI' 0 ''
workflow_step escaped "$workflow"
expect 'catches: the pull request workflow fails a reasoned escape tag' 0 ''

pull_request_ci fixture format/fixtures/valid/x/check.sh '# Prints nothing: nothing is due.'
expect 'catches: a format fixture planting a comment the validator reads fails CI' 0 ''
workflow_step fixture "$workflow"
expect 'catches: the pull request workflow fails a format fixture comment' 0 ''

[ "$failures" -eq 0 ] || exit 1
