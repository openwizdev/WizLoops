#!/bin/sh
# The `checks` CI check. Needs `openwiz` on PATH (or OPENWIZ set to it),
# built from the OpenWiz commit .github/workflows/checks.yml pins.
set -eu
cd "$(dirname "$0")/.."
# Refuse private identifiers in tracked files: Cloudroom thread ids and
# session ids never belong in this public repository.
if git grep -n -I -E '\b(thr_[a-z0-9]{10}|cr_sub_[0-9a-f]{16,}|cr_[0-9a-f]{8}-[0-9a-f]{4}-)' -- . ':!ci/check.sh'; then
  echo "check: private identifiers found above" >&2
  exit 1
fi
echo "check: no private identifiers"
# Every catalog file and every fixture, with openwiz loop validate.
python3 -I ci/validate.py
# The validator refuses broken copies.
sh ci/test-validate.sh
sh ci/test-comment-check.sh
