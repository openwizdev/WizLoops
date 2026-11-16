#!/bin/sh
# The validator's own proof: it must refuse a broken copy, so a green
# `checks` run means the loop files were really checked.
#
#   sh ci/test-validate.sh
#
# Each case copies catalog/ and format/ to a temporary root, breaks one
# thing and expects ci/validate.py to fail naming it.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0

# expect_refused <case> <text the failure must print>
expect_refused() {
  if python3 -I "$here/validate.py" "$tmp/$1" > "$tmp/$1.out" 2>&1; then
    echo "test-validate: $1: passed a broken copy" >&2
    failed=1
  elif ! grep -F -q -- "$2" "$tmp/$1.out"; then
    echo "test-validate: $1: failed without naming $2:" >&2
    cat "$tmp/$1.out" >&2
    failed=1
  else
    echo "test-validate: $1: refused, as it must"
  fi
}

copy() {
  mkdir "$tmp/$1"
  cp -R "$root/catalog" "$root/format" "$tmp/$1/"
}

# catches: a catalog file the format refuses still passes CI.
copy broken-catalog
sed 's/^priority: .*/priority: 9/' "$root/catalog/fleet-check.md" > "$tmp/broken-catalog/catalog/fleet-check.md"
grep -q '^priority: 9$' "$tmp/broken-catalog/catalog/fleet-check.md" || { echo "test-validate: could not break the copy" >&2; exit 1; }
expect_refused broken-catalog "catalog/fleet-check.md"

# catches: an invalid fixture refusing with a different message still passes.
copy wrong-refusal
python3 -I - "$tmp/wrong-refusal/format/fixtures/expected.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["fixtures"]["invalid/crlf.md"]["refusals"][0]["message"] = "a different message"
json.dump(data, open(path, "w", encoding="utf-8"), indent=2)
PY
expect_refused wrong-refusal "invalid/crlf.md"

# catches: a fixture missing from expected.json is skipped, so never checked.
copy unlisted-fixture
cp "$root/format/fixtures/invalid/crlf.md" "$tmp/unlisted-fixture/format/fixtures/invalid/unlisted.md"
expect_refused unlisted-fixture "invalid/unlisted.md"

exit "$failed"
