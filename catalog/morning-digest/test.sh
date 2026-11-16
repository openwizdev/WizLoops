#!/bin/sh
# Runs morning-digest's check, rendered as the Cloudroom adapter renders it
# (catalog/test-params.sh), against a stand-in `gh search` that serves
# synthetic results through the check's own --jq filter, and checks what the
# loop promises: one line per item for the digest, nothing on a quiet
# morning, a line when GitHub can't be read or a list is cut at 100, and its
# org and owner reach gh as data. Needs jq and python3.
# Usage, from anywhere: sh catalog/morning-digest/test.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../test-params.sh"
command -v jq >/dev/null || { echo "test: needs jq" >&2; exit 2; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin" "$work/data" "$work/run"
# `gh search <kind> ...`: appends its arguments to $GH_LOG (one per line,
# then a line "--end"), and serves data/<label>.json through --jq, where the
# label is the search's first flag after --owner: --merged-at, --checks,
# --review-requested or --assignee. data/fail makes it fail as gh does.
cat > "$work/bin/gh" <<'GH'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done >> "$GH_LOG"; echo "--end" >> "$GH_LOG"
[ -f "$DATA/fail" ] && { echo "HTTP 502: bad gateway" >&2; exit 1; }
file= filter=.
while [ $# -gt 0 ]; do
  case "$1" in
    --merged-at|--checks|--review-requested|--assignee) [ -z "$file" ] && file=${1#--} ;;
    --jq) filter=$2 ;;
  esac
  shift
done
[ -f "$DATA/$file.json" ] || { echo '[]' | jq -r "$filter"; exit; }
jq -r "$filter" "$DATA/$file.json"
GH
# `date`, fixed: 24 hours ago is always this time.
printf '#!/bin/sh\necho 2030-01-01T08:45:00Z\n' > "$work/bin/date"
chmod +x "$work/bin/gh" "$work/bin/date"
item() { printf '{"repository":{"nameWithOwner":"%s"},"number":%s,"title":"%s"}' "$1" "$2" "$3"; }
json() { python3 -I -c 'import json, sys; print(json.dumps(dict(zip(sys.argv[1::2], sys.argv[2::2]))))' "$@"; }

fails=0
# wake <case> <params JSON> <want stdout>
wake() {
  render_check "$here/../morning-digest.md" "$work/check.sh" "$2" || { echo "FAIL $1: not rendered"; fails=$((fails + 1)); return; }
  : > "$work/log"; rm -rf "$work/run"; mkdir "$work/run"
  out=$(cd "$work/run" && GH_LOG="$work/log" DATA="$work/data" PATH="${path:-$work/bin:$PATH}" sh "$work/check.sh" 2>/dev/null)
  code=$?
  if [ "$code" != 0 ]; then printf 'FAIL %s: exit %s\n' "$1" "$code"; fails=$((fails + 1))
  elif [ "$out" != "$3" ]; then printf 'FAIL %s\n  got:  %s\n  want: %s\n' "$1" "$out" "$3"; fails=$((fails + 1))
  elif [ -n "$(ls -A "$work/run")" ]; then printf 'FAIL %s: a payload ran\n' "$1"; fails=$((fails + 1))
  else printf 'ok   %s\n' "$1"; fi
}
# searched <case> <org> <owner>: the four searches gh got, in order, with
# the org and owner each exactly one argument
searched() {
  got=$(grep -v -e '^>=' -e '^--json$' -e '^repository,number,title$' -e '^--limit$' -e '^101$' -e '^--jq$' \
    -e '^\.\[\] | ' "$work/log")
  want=$(printf '%s\n' search prs --owner "$2" --merged-at --end \
    search prs --owner "$2" --state open --checks failure --end \
    search prs --owner "$2" --state open --review-requested "$3" --end \
    search issues --owner "$2" --state open --assignee "$3" --end)
  if [ "$got" = "$want" ]; then printf 'ok   %s\n' "$1"
  else printf 'FAIL %s: gh got:\n%s\n' "$1" "$got"; fails=$((fails + 1)); fi
}

# catches: a quiet morning that still prints, so an agent starts for nothing
wake "nothing to report: quiet" '{}' ""
# catches: the searches asking about another account or person
searched "the four searches use the org and owner" example-org example-owner
# catches: an item missing from the digest, or listed under the wrong heading
printf '[%s]\n' "$(item example-org/app 12 'Fix the login')" > "$work/data/merged-at.json"
printf '[%s]\n' "$(item example-org/api 7 'Assigned bug')" > "$work/data/assignee.json"
wake "each item one line, under its search" '{}' "merged: example-org/app#12 Fix the login
assigned: example-org/api#7 Assigned bug"
# catches: a list cut at 100 read as complete
python3 -I -c 'import json; print(json.dumps([{"repository": {"nameWithOwner": "example-org/app"}, "number": n, "title": "PR %d" % n} for n in range(1, 102)]))' \
  > "$work/data/merged-at.json"
rm "$work/data/assignee.json"
wake "101 items: the first 100 and how to finish the list" '{}' \
  "$(i=1; while [ $i -le 100 ]; do echo "merged: example-org/app#$i PR $i"; i=$((i + 1)); done)
check: more than 100 merged items; only the first 100 are above. Finish the list with: gh search prs --owner example-org --merged-at >=2030-01-01T08:45:00Z"
rm "$work/data/merged-at.json"
# catches: GitHub unreadable read as a quiet morning
touch "$work/data/fail"
wake "GitHub can't be read: one line per search" '{}' "check: GitHub could not be read (merged): HTTP 502: bad gateway
check: GitHub could not be read (failing): HTTP 502: bad gateway
check: GitHub could not be read (review-requested): HTTP 502: bad gateway
check: GitHub could not be read (assigned): HTTP 502: bad gateway"
rm "$work/data/fail"
# catches: no gh read as a quiet morning
mkdir "$work/nogh"
ln -s "$work/bin/date" "$work/nogh/date"; ln -s "$(command -v sh)" "$work/nogh/sh"
path="$work/nogh" wake "no gh: one line says so" '{}' "check: GitHub could not be read: gh is not installed"

# The payloads from the review of workflow-kick's first pull request, as the
# org and the owner. catches: a param value read as shell code, which could
# run commands with the thread's GitHub access or print and wake an agent.
for v in 'example-org"$(touch${IFS}marker)"' 'example-`touch marker`' \
  "example';touch marker;'" 'release";printf${IFS}WAKE;false${IFS}"' 'example\cb'; do
  wake "payload org and owner stay data: $v" "$(json org "$v" owner "$v")" ""
  searched "payload org and owner reach gh as one argument each: $v" "$v" "$v"
done

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
echo "all passed"
