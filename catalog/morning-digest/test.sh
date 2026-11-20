#!/bin/sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../test-params.sh"
command -v jq >/dev/null || { echo "test: needs jq" >&2; exit 2; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin" "$work/data" "$work/run"
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
printf '#!/bin/sh\necho 2030-01-01T08:45:00Z\n' > "$work/bin/date"
chmod +x "$work/bin/gh" "$work/bin/date"
item() { printf '{"repository":{"nameWithOwner":"%s"},"number":%s,"title":"%s"}' "$1" "$2" "$3"; }
json() { python3 -I -c 'import json, sys; print(json.dumps(dict(zip(sys.argv[1::2], sys.argv[2::2]))))' "$@"; }

fails=0
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

wake "nothing to report: quiet, so no agent starts for nothing" '{}' ""
searched "the four searches ask about this org and owner, no other account or person" example-org example-owner
printf '[%s]\n' "$(item example-org/app 12 'Fix the login')" > "$work/data/merged-at.json"
printf '[%s]\n' "$(item example-org/api 7 'Assigned bug')" > "$work/data/assignee.json"
wake "each item one line, under its own search, none missing" '{}' "merged: example-org/app#12 Fix the login
assigned: example-org/api#7 Assigned bug"
python3 -I -c 'import json; print(json.dumps([{"repository": {"nameWithOwner": "example-org/app"}, "number": n, "title": "PR %d" % n} for n in range(1, 102)]))' \
  > "$work/data/merged-at.json"
rm "$work/data/assignee.json"
wake "101 items: the first 100 and how to finish the list, never read as complete" '{}' \
  "$(i=1; while [ $i -le 100 ]; do echo "merged: example-org/app#$i PR $i"; i=$((i + 1)); done)
check: more than 100 merged items; only the first 100 are above. Finish the list with: gh search prs --owner example-org --merged-at >=2030-01-01T08:45:00Z"
rm "$work/data/merged-at.json"
touch "$work/data/fail"
wake "GitHub can't be read: one line per search, never a quiet morning" '{}' "check: GitHub could not be read (merged): HTTP 502: bad gateway
check: GitHub could not be read (failing): HTTP 502: bad gateway
check: GitHub could not be read (review-requested): HTTP 502: bad gateway
check: GitHub could not be read (assigned): HTTP 502: bad gateway"
rm "$work/data/fail"
mkdir "$work/nogh"
ln -s "$work/bin/date" "$work/nogh/date"; ln -s "$(command -v sh)" "$work/nogh/sh"
path="$work/nogh" wake "no gh: one line says so, never a quiet morning" '{}' "check: GitHub could not be read: gh is not installed"

for v in 'example-org"$(touch${IFS}marker)"' 'example-`touch marker`' \
  "example';touch marker;'" 'release";printf${IFS}WAKE;false${IFS}"' 'example\cb'; do
  wake "payload org and owner stay data: $v" "$(json org "$v" owner "$v")" ""
  searched "payload org and owner reach gh as one argument each: $v" "$v" "$v"
done

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
echo "all passed"
