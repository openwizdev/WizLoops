#!/bin/sh
# For the catalog's tests only: renders a loop's check the way the Cloudroom
# adapter rules do (adapters/cloudroom.v1.md, "Params: the body and the
# check's preamble"): the check's first line, a preamble exporting each param
# the check uses as WIZLOOP_PARAM_<NAME>, then the rest of the check. Nothing
# is replaced in the check's text.
#
#   . catalog/test-params.sh
#   render_check <loop file> <output file> [<JSON object of params to set>]
#
# The third argument sets params the file declares, as a caller would. A
# value with a line break or NUL is refused (exit 2), as the format refuses
# it (multiline-param). Needs python3.
render_check() {
  python3 -I - "$1" "$2" "${3-}" <<'PY'
import json, os, re, sys
loop, out, override = sys.argv[1], sys.argv[2], json.loads(sys.argv[3] or "{}")
lines = open(loop, encoding="utf-8").read().split("\n")
front = {}
for line in lines[1:lines.index("---", 1)]:
    key, value = line.split(": ", 1)
    front[key] = json.loads(value)
params = dict(front.get("params", {}))
for name, value in override.items():
    if name not in params:
        sys.exit("render_check: %s is not a declared param" % name)
    params[name] = value
check = open(os.path.join(os.path.dirname(loop), front["check"]["run"]), encoding="utf-8").read()
if re.search(r"\{\{[a-z][a-z0-9_]*\}\}", check):
    sys.stderr.write("render_check: a placeholder in the check (param-in-check)\n")
    sys.exit(2)
used = sorted(n for n in params if re.search("(?<![A-Za-z0-9_])WIZLOOP_PARAM_%s(?![A-Za-z0-9_])" % n.upper(), check))
exports = []
for name in used:
    value = params[name]
    if isinstance(value, int) and not isinstance(value, bool):
        exports.append("export WIZLOOP_PARAM_%s=%d\n" % (name.upper(), value))
    elif isinstance(value, str) and not re.search("[\n\r\0]", value):
        exports.append("export WIZLOOP_PARAM_%s='%s'\n" % (name.upper(), value.replace("'", "'\\''")))
    else:
        sys.stderr.write("render_check: %s must be one line, with no line break or NUL (multiline-param)\n" % name)
        sys.exit(2)
first, _, rest = check.partition("\n")
if exports:
    if first not in ("#!/bin/sh", "#!/bin/bash", "#!/usr/bin/env sh", "#!/usr/bin/env bash"):
        sys.exit("render_check: not a shell check (cf-check-shell)")
    check = (first + "\n# wizloop: params from the loop file, as data\n" + "".join(exports)
             + "# wizloop: the check\n" + rest)
open(out, "w", encoding="utf-8").write(check)
PY
}
