#!/bin/sh
# Refuse private identifiers in tracked files: Cloudroom thread ids and
# session ids never belong in this public repository.
set -eu
if git grep -n -I -E '\b(thr_[a-z0-9]{10}|cr_sub_[0-9a-f]{16,}|cr_[0-9a-f]{8}-[0-9a-f]{4}-)' -- . ':!ci/check.sh'; then
  echo "check: private identifiers found above" >&2
  exit 1
fi
echo "check: no private identifiers"
