#!/bin/sh
set -eu
base=$1
exec python3 -I "$(dirname "$0")/../tools/comment-check/check.py" diff --base "$base" --exclude 'format/fixtures/'
