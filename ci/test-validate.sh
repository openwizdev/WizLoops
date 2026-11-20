#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0

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

copy catalog-file-the-format-refuses
sed 's/^priority: .*/priority: 9/' "$root/catalog/fleet-check.md" > "$tmp/catalog-file-the-format-refuses/catalog/fleet-check.md"
grep -q '^priority: 9$' "$tmp/catalog-file-the-format-refuses/catalog/fleet-check.md" || { echo "test-validate: could not break the copy" >&2; exit 1; }
expect_refused catalog-file-the-format-refuses "catalog/fleet-check.md"

copy fixture-refusing-with-another-message
python3 -I - "$tmp/fixture-refusing-with-another-message/format/fixtures/expected.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["fixtures"]["invalid/crlf.md"]["refusals"][0]["message"] = "a different message"
json.dump(data, open(path, "w", encoding="utf-8"), indent=2)
PY
expect_refused fixture-refusing-with-another-message "invalid/crlf.md"

copy fixture-missing-from-expected-json
cp "$root/format/fixtures/invalid/crlf.md" "$tmp/fixture-missing-from-expected-json/format/fixtures/invalid/unlisted.md"
expect_refused fixture-missing-from-expected-json "invalid/unlisted.md"

exit "$failed"
