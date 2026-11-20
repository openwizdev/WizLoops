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

pull_request_ci escaped catalog/x/check.sh '# comment-ok: the runner reads this line'
expect 'catches: a reasoned escape tag still fails CI' 0 ''

pull_request_ci fixture format/fixtures/valid/x/check.sh '# Prints nothing: nothing is due.'
expect 'catches: a format fixture planting a comment the validator reads fails CI' 0 ''

[ "$failures" -eq 0 ] || exit 1
