#!/usr/bin/env python3
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), ".."))
openwiz = os.environ.get("OPENWIZ", "openwiz")
fixtures = os.path.join(root, "format", "fixtures")
problems = []


def validate(path, catalog=False):
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


OUTCOME_MESSAGES = {
    "encoding": "must be UTF-8 with LF line ends, no byte order mark and no NUL",
    "frontmatter-start": "must start with a line of exactly ---",
    "frontmatter-end": "frontmatter has no closing line of exactly ---",
    "line-syntax": 'must be "key: value" with one JSON value',
    "json": "value is not one JSON value",
    "duplicate-key": "contains a repeated key",
    "unknown-field": "is not a setting of outcome v1",
    "missing-field": "is required",
    "bad-id": "must contain only lowercase ASCII letters, digits and hyphens",
    "id-filename": "must match the file name without .md",
    "bad-claim": "must be one plain sentence on one line",
    "bad-proof": "must be an object",
    "bad-proof-run": "must be a nonblank command on one line, with no NUL",
    "bad-timeout": "must be an integer from 1 to 600 seconds",
    "bad-allowed-paths": "must be a non-empty array of repository-relative files or folders",
    "bad-cadence": "must be an object",
    "bad-cron": "must be five cron fields: minute hour day-of-month month day-of-week",
    "cadence-too-frequent": "must select only one minute of each hour",
    "bad-timezone": "must be UTC or an IANA zone such as Area/City",
    "bad-enabled": "must be true or false",
    "bad-secrets": "must be an array of key names, never all or a value",
    "bad-secret": "each item must be an environment variable name",
    "duplicate-secret": "must name each key only once",
}
OUTCOME_REQUIRED = ("id", "proof", "allowed_paths", "cadence", "enabled")
CRON_LIMITS = ((0, 59), (0, 23), (1, 31), (1, 12), (0, 6))
CRON_ITEM = re.compile(r"(\*|0|[1-9][0-9]*)(?:-(0|[1-9][0-9]*))?(?:/([1-9][0-9]*))?")


class DuplicateOutcomeKey(ValueError):
    pass


def outcome_object(pairs):
    result = dict(pairs)
    if len(result) != len(pairs):
        raise DuplicateOutcomeKey()
    return result


def reject_json_constant(value):
    raise ValueError(value)


def outcome_refusal(code, field):
    return {"code": code, "field": field, "message": OUTCOME_MESSAGES[code]}


def outcome_refused(*items):
    return {"result": "refused", "refusals": list(items)}


def outcome_lines(path):
    text = path.read_bytes().decode("utf-8")
    if text.startswith("\ufeff") or "\x00" in text or "\r" in text:
        raise UnicodeError()
    return text.split("\n")


def outcome_read_settings(lines):
    settings = {}
    errors = []
    for number, line in enumerate(lines, 2):
        match = re.fullmatch(r"([a-z][a-z0-9_]*): (\S(?:.*\S)?)", line)
        if match is None:
            errors.append(outcome_refusal("line-syntax", f"line {number}"))
            continue
        key, value = match.groups()
        try:
            if key in settings:
                raise DuplicateOutcomeKey()
            settings[key] = json.loads(
                value, object_pairs_hook=outcome_object, parse_constant=reject_json_constant
            )
        except DuplicateOutcomeKey:
            errors.append(outcome_refusal("duplicate-key", key))
        except (ValueError, RecursionError):
            errors.append(outcome_refusal("json", key))
    return settings, errors


def outcome_shape(value, required, optional=(), field=""):
    errors = [
        outcome_refusal("unknown-field", field + key)
        for key in value if key not in required and key not in optional
    ]
    errors.extend(
        outcome_refusal("missing-field", field + key)
        for key in required if key not in value
    )
    return errors


def cron_field(field, low, high):
    selected = set()
    for item in field.split(","):
        match = CRON_ITEM.fullmatch(item)
        if match is None:
            return None
        start, stop, step = match.groups()
        if start == "*":
            if stop is not None or (step is None and field != "*"):
                return None
            first, last = low, high
        else:
            if len(start) > 2 or (stop is not None and len(stop) > 2):
                return None
            first = int(start)
            last = int(stop) if stop is not None else (high if step else first)
            if not low <= first <= last <= high:
                return None
        stride = 1 if step is None else (int(step) if len(step) <= 2 else high + 1)
        selected.update(range(first, last + 1, stride))
    return selected


def outcome_cron(value):
    if not isinstance(value, str):
        return "bad-cron"
    fields = value.split(" ")
    if len(fields) != len(CRON_LIMITS):
        return "bad-cron"
    minutes, *other_fields = [cron_field(field, *limits) for field, limits in zip(fields, CRON_LIMITS)]
    if minutes is None or any(field is None for field in other_fields):
        return "bad-cron"
    if len(minutes) > 1:
        return "cadence-too-frequent"
    return None


def outcome_timezone(value):
    if not isinstance(value, str) or not re.fullmatch(
        r"UTC|[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+)+", value
    ):
        return False
    if value == "UTC":
        return True
    try:
        ZoneInfo(value)
    except ZoneInfoNotFoundError:
        return False
    return True


def outcome_relative_path(value):
    if not isinstance(value, str) or re.search(r"[\\\x00-\x1f\x7f]|^[A-Za-z]:", value):
        return False
    return all(part not in ("", ".", "..") for part in value.removesuffix("/").split("/"))


def outcome_proof_errors(proof):
    if not isinstance(proof, dict):
        return [outcome_refusal("bad-proof", "proof")]
    errors = outcome_shape(proof, ("run", "timeout"), field="proof.")
    if "run" in proof:
        run = proof["run"]
        if not isinstance(run, str) or not run.strip() or re.search(r"[\r\n\x00]", run):
            errors.append(outcome_refusal("bad-proof-run", "proof.run"))
    if "timeout" in proof:
        timeout = proof["timeout"]
        if type(timeout) is not int or not 1 <= timeout <= 600:
            errors.append(outcome_refusal("bad-timeout", "proof.timeout"))
    return errors


def outcome_cadence_errors(cadence):
    if not isinstance(cadence, dict):
        return [outcome_refusal("bad-cadence", "cadence")]
    errors = outcome_shape(cadence, ("cron", "timezone"), field="cadence.")
    if "cron" in cadence:
        code = outcome_cron(cadence["cron"])
        if code:
            errors.append(outcome_refusal(code, "cadence.cron"))
    if "timezone" in cadence and not outcome_timezone(cadence["timezone"]):
        errors.append(outcome_refusal("bad-timezone", "cadence.timezone"))
    return errors


def outcome_secret_error(value):
    if not isinstance(value, list):
        return "bad-secrets"
    if any(not isinstance(name, str) or not re.fullmatch(r"[A-Z][A-Z0-9_]*", name) for name in value):
        return "bad-secret"
    if len(set(value)) != len(value):
        return "duplicate-secret"
    return None


def outcome_field_errors(path, settings):
    errors = outcome_shape(settings, OUTCOME_REQUIRED, ("secrets",))
    for key, value in settings.items():
        if key == "id":
            if not isinstance(value, str) or not re.fullmatch(r"[a-z0-9-]+", value):
                errors.append(outcome_refusal("bad-id", key))
            elif path.name != value + ".md":
                errors.append(outcome_refusal("id-filename", key))
        elif key == "proof":
            errors.extend(outcome_proof_errors(value))
        elif key == "allowed_paths":
            if not isinstance(value, list) or not value or not all(map(outcome_relative_path, value)):
                errors.append(outcome_refusal("bad-allowed-paths", key))
        elif key == "cadence":
            errors.extend(outcome_cadence_errors(value))
        elif key == "enabled" and type(value) is not bool:
            errors.append(outcome_refusal("bad-enabled", key))
        elif key == "secrets":
            code = outcome_secret_error(value)
            if code:
                errors.append(outcome_refusal(code, key))
    return errors


def validate_outcome(path):
    try:
        lines = outcome_lines(path)
    except UnicodeError:
        return outcome_refused(outcome_refusal("encoding", "file"))
    if lines[0] != "---":
        return outcome_refused(outcome_refusal("frontmatter-start", "file"))
    try:
        end = lines.index("---", 1)
    except ValueError:
        return outcome_refused(outcome_refusal("frontmatter-end", "file"))
    settings, errors = outcome_read_settings(lines[1:end])
    if errors:
        return outcome_refused(*errors)
    errors = outcome_field_errors(path, settings)
    claim = "\n".join(lines[end + 1:]).strip()
    if (
        len(claim.splitlines()) != 1
        or not re.search(r"[^\W_]", claim)
        or not claim.endswith((".", "!", "?"))
        or re.search(r"[.!?]\s", claim)
    ):
        errors.append(outcome_refusal("bad-claim", "claim"))
    if errors:
        return outcome_refused(*errors)
    return {"result": "valid", "parsed": {"secrets": [], **settings, "claim": claim}}


def outcome_proof_result(exit_code, stdout):
    if exit_code == 0:
        return {"result": "holds"}
    if exit_code == 1:
        return {"result": "broken", "evidence": stdout}
    if exit_code == 3:
        return {"result": "unproved", "reason": stdout}
    reason = "proof timed out" if exit_code is None else f"proof exited {exit_code}"
    return {"result": "unproved", "reason": reason}


def validate_outcome_fixtures(directory):
    label = "format/fixtures/outcome"
    manifest = directory / "expected.json"
    suite = json.loads(manifest.read_text(encoding="utf-8"), object_pairs_hook=outcome_object)
    expected = suite["fixtures"]
    on_disk = {
        path.relative_to(directory).as_posix()
        for path in directory.rglob("*")
        if path.is_file() and path != manifest
    }
    for name in sorted(on_disk - expected.keys()):
        problems.append(f"{label}/{name}: not listed in expected.json, so never checked")
    for name in sorted(expected.keys() - on_disk):
        problems.append(f"{label}/{name}: listed in expected.json but not found")
    for name in sorted(expected.keys() & on_disk):
        got = validate_outcome(directory / name)
        if got != expected[name]:
            problems.append(f"{label}/{name}: {json.dumps(got)}, expected {json.dumps(expected[name])}")
    for case in suite["proof_results"]:
        got = outcome_proof_result(case["exit"], case["stdout"])
        if got != case["want"]:
            problems.append(f"{label}: proof exit {case['exit']}: {got}, expected {case['want']}")
    return len(expected), len(suite["proof_results"])


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

outcome_count, proof_count = validate_outcome_fixtures(Path(fixtures) / "outcome")

for p in problems:
    print("validate: " + p, file=sys.stderr)
if problems:
    sys.exit(1)
print("validate: the catalog and %d fixtures match expected.json" % len(expected))
print(f"validate: {outcome_count} outcome fixtures and {proof_count} proof results match outcome/expected.json")
