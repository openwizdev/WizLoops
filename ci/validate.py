#!/usr/bin/env python3
"""Validate every loop file in this repository with `openwiz loop validate`.

    python3 -I ci/validate.py [<root>]

<root> is the repository root (default: this file's parent's parent). Uses
the `openwiz` on PATH, or $OPENWIZ. Checks that:

- catalog/, read as a catalog, is all valid;
- every fixture under format/fixtures/ is listed in expected.json, and each
  one's result and refusals (code, field, message, in order) match it.

Prints each problem and exits 1 if there is any, 0 otherwise.
"""
import json
import os
import subprocess
import sys

root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), ".."))
openwiz = os.environ.get("OPENWIZ", "openwiz")
fixtures = os.path.join(root, "format", "fixtures")
problems = []


def validate(path, catalog=False):
    """Run validate on <path> (relative to root); return (exit code, report)."""
    args = [openwiz, "loop", "validate", "--json"] + (["--catalog"] if catalog else []) + ["--", path]
    run = subprocess.run(args, cwd=root, capture_output=True, text=True)
    try:
        report = json.loads(run.stdout)
    except ValueError:
        report = None
    if run.returncode not in (0, 5) or not isinstance(report, dict) or report.get("exit_code") != run.returncode:
        problems.append("%s: openwiz exited %d with no validate report: %s" % (path, run.returncode, (run.stderr or run.stdout).strip()))
        return run.returncode, None
    return run.returncode, report


def refusals(items, with_file=False):
    keys = ("file", "code", "field", "message") if with_file else ("code", "field", "message")
    return [{k: os.path.basename(r[k]) if k == "file" else r[k] for k in keys} for r in items]


# The catalog: every file valid, read as a catalog.
code, report = validate("catalog", catalog=True)
if report is not None:
    if not report["files"]:
        problems.append("catalog: no loop files read")
    for f in report["files"]:
        for r in f["refusals"]:
            problems.append("%s: %s: %s (%s)" % (f["file"], r["field"], r["message"], r["code"]))
    for r in report["folder_refusals"]:
        problems.append("%s: %s: %s (%s)" % (r["file"], r["field"], r["message"], r["code"]))
    if code != 0 and not problems:
        problems.append("catalog: openwiz exited %d with no refusal" % code)

# The fixtures: what is on disk is exactly what expected.json lists.
expected = json.load(open(os.path.join(fixtures, "expected.json"), encoding="utf-8"))["fixtures"]
on_disk = set()
for kind in ("valid", "invalid"):
    for name in os.listdir(os.path.join(fixtures, kind)):
        if name.endswith(".md"):
            on_disk.add("%s/%s" % (kind, name))
for kind in ("invalid-folder", "catalog"):
    folders = [""] if kind == "catalog" else sorted(os.listdir(os.path.join(fixtures, kind)))
    for folder in folders:
        base = "/".join(p for p in (kind, folder) if p)
        on_disk.add(base + "/")
        for name in os.listdir(os.path.join(fixtures, base)):
            if name.endswith(".md") and name != "README.md":
                on_disk.add("%s/%s" % (base, name))
for name in sorted(on_disk - set(expected)):
    problems.append("format/fixtures/%s: not listed in expected.json, so never checked" % name)
for name in sorted(set(expected) - on_disk):
    problems.append("format/fixtures/%s: listed in expected.json but not found" % name)

for name in sorted(set(expected) & on_disk):
    want = expected[name]
    path = "format/fixtures/" + name
    folder = name.endswith("/")
    code, report = validate(path, catalog=want.get("read_as") == "catalog")
    if report is None:
        continue
    want_code = 0 if want["result"] == "valid" else 5
    if folder:
        got = refusals(report["folder_refusals"], with_file=True)
        if any(f["refusals"] for f in report["files"]):
            got = got + [dict(r, file=os.path.basename(f["file"])) for f in report["files"] for r in refusals(f["refusals"])]
    else:
        got = refusals(report["files"][0]["refusals"]) + refusals(report["folder_refusals"])
        if report["files"][0]["result"] != want["result"]:
            problems.append("%s: %s, expected %s" % (path, report["files"][0]["result"], want["result"]))
    if got != want.get("refusals", []):
        problems.append("%s: refusals %s, expected %s" % (path, json.dumps(got), json.dumps(want.get("refusals", []))))
    if code != want_code:
        problems.append("%s: openwiz exited %d, expected %d" % (path, code, want_code))

for p in problems:
    print("validate: " + p, file=sys.stderr)
if problems:
    sys.exit(1)
print("validate: the catalog and %d fixtures match expected.json" % len(expected))
