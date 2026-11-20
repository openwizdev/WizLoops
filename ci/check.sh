#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if git grep -n -I -E '\b(thr_[a-z0-9]{10}|cr_sub_[0-9a-f]{16,}|cr_[0-9a-f]{8}-[0-9a-f]{4}-)' -- . ':!ci/check.sh'; then
  echo "check: private identifiers (Cloudroom thread or session ids) found above; they never belong in this public repository" >&2
  exit 1
fi
echo "check: no private identifiers"
python3 -I ci/validate.py
sh ci/test-validate.sh
sh ci/test-comment-check.sh
