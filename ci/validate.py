#!/usr/bin/env python3
import datetime
import json
import os
import posixpath
import re
import subprocess
import sys

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

T3_MARKER = re.compile(r"^(.*) \[wizloop:([a-z0-9][a-z0-9-]{0,63})\]$")
T3_NUMBER = re.compile(r"^(0|[1-9][0-9]*)$")
T3_STEP = re.compile(r"^\*/([1-9][0-9]*)$")
T3_TEMPLATE_PART = re.compile(r"<(id|file|timeout|command|ok|body)>")


def read_loop(path):
    lines = open(path, encoding="utf-8").read().split("\n")
    end = lines.index("---", 1)
    fields = {}
    for line in lines[1:end]:
        key, value = line.split(": ", 1)
        fields[key] = json.loads(value)
    return fields, "\n".join(lines[end + 1:])


def read_rules(path):
    sections = {}
    heading = None
    block = None
    for line in open(path, encoding="utf-8").read().split("\n"):
        if block is not None:
            if line == "```":
                sections[heading]["blocks"].append("\n".join(block))
                block = None
            else:
                block.append(line)
        elif line.startswith("```"):
            block = []
        elif line.startswith("#"):
            heading = line.lstrip("#").strip()
            sections.setdefault(heading, {"rows": [], "blocks": []})
        elif heading is not None and line.startswith("| ") and not line.startswith("| ---"):
            sections[heading]["rows"].append([unquote(c.strip()) for c in line.strip()[2:-2].split(" | ")])
    return sections


def unquote(cell):
    return cell[1:-1] if len(cell) > 1 and cell[0] == "`" and cell[-1] == "`" else cell


def section(rules, name, rows=True):
    found = rules.get(name)
    if found is None or not (found["rows"] if rows else found["blocks"]):
        problems.append("adapters/t3.v1.md: no %s under the heading \"%s\"" % ("table" if rows else "text block", name))
        return None
    return found["rows"][1:] if rows else found["blocks"][0]


def t3_marker(title):
    match = T3_MARKER.match(title)
    return match.group(2) if match else None


def t3_derived_id(title):
    derived = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:64]
    return derived.rstrip("-")


def t3_instant(text):
    return datetime.datetime.fromisoformat(text.replace("Z", "+00:00"))


def t3_quote(value):
    return str(value) if isinstance(value, int) else "'" + value.replace("'", "'\\''") + "'"


def t3_weekdays(field):
    days = set()
    for item in field.split(","):
        bounds = item.split("-")
        if len(bounds) > 2 or not all(T3_NUMBER.match(b) for b in bounds):
            return None
        days.update(range(int(bounds[0]), int(bounds[-1]) + 1))
    return sorted(days)


def t3_cron(cron, zone, server_zone):
    minute, hour, day, month, weekday = cron.split(" ")
    if day != "*" or month != "*":
        return None, "t3-cron"
    if weekday == "*":
        step = T3_STEP.match(minute)
        if step and hour == "*" and int(step.group(1)) < 60 and 60 % int(step.group(1)) == 0:
            return {"type": "interval", "everyMs": int(step.group(1)) * 60000}, None
        step = T3_STEP.match(hour)
        every = int(step.group(1)) if step else 1 if hour == "*" else None
        if T3_NUMBER.match(minute) and every is not None and every < 24 and 24 % every == 0:
            return {"type": "interval", "everyMs": every * 3600000}, None
    days = None if weekday == "*" else t3_weekdays(weekday)
    if not (T3_NUMBER.match(minute) and T3_NUMBER.match(hour)) or (weekday != "*" and days is None):
        return None, "t3-cron"
    if zone != server_zone:
        return None, "t3-timezone"
    schedule = {"type": "fixed_time", "timeOfDay": "%02d:%02d" % (int(hour), int(minute))}
    if days is not None:
        schedule["weekdays"] = days
    return schedule, None


def t3_same_schedule(a, b):
    if a["type"] != b["type"]:
        return False
    if a["type"] == "interval":
        return a["everyMs"] == b["everyMs"]
    if a["type"] == "once":
        return t3_instant(a["runAt"]) == t3_instant(b["runAt"])
    if a["type"] == "fixed_time":
        def parts(s):
            hour, minute = s["timeOfDay"].split(":")
            days = sorted(set(s.get("weekdays") or []))
            return int(hour), int(minute), [] if len(days) == 7 else days
        return parts(a) == parts(b)
    return True


def t3_render(templates, fields, body, file_rel, check_text, state):
    params = fields.get("params", {})
    for name, value in params.items():
        body = body.replace("{{%s}}" % name, str(value))
    parts = {"id": fields["id"], "file": file_rel, "ok": "%s/%s/ok.log" % (state, fields["id"]), "body": body.rstrip("\n")}
    template = templates["without"]
    if "check" in fields:
        used = sorted(n for n in params if re.search(r"(?<![A-Za-z0-9_])WIZLOOP_PARAM_%s(?![A-Za-z0-9_])" % n.upper(), check_text))
        env = "".join("WIZLOOP_PARAM_%s=%s " % (n.upper(), t3_quote(params[n])) for n in used)
        path = "./" + posixpath.join(posixpath.dirname(file_rel), fields["check"]["run"])
        parts["command"] = ("env " + env if env else "") + check_text.split("\n", 1)[0][2:].strip(" ") + " " + t3_quote(path)
        parts["timeout"] = str(fields["check"]["timeout"])
        template = templates["with"]
    return T3_TEMPLATE_PART.sub(lambda m: parts[m.group(1)], template)


def t3_plan(rules, fields, body, file_rel, check_text, server, tasks):
    found = []

    def refuse(code, field, **parts):
        message = rules["refusals"][code][1]
        for key, value in parts.items():
            message = message.replace("<%s>" % key, value)
        found.append({"code": code, "field": field, "message": message})

    loop_id = fields["id"]
    thread = server["thread"]
    managed = [t for t in tasks if t3_marker(t["title"]) == loop_id]
    unmanaged = [t["scheduledTaskId"] for t in tasks if t3_marker(t["title"]) is None]
    if len(managed) > 1:
        refuse("t3-duplicate-marker", "id", id=loop_id)
    if not managed and any(t3_derived_id(t3_marker_name(t["title"])) == loop_id for t in tasks if t3_marker(t["title"]) is None):
        refuse("t3-unmarked-match", "id")
    bind = fields["thread"] == "same"
    if len(managed) == 1:
        task = managed[0]
        if bind != (task["boundThreadId"] is not None) or task["freshSession"] == bind or (bind and task["boundThreadId"] != thread["id"]):
            refuse("t3-update-thread", "thread")
    trigger = fields["trigger"]
    schedule = None
    if "cron" in trigger:
        schedule, code = t3_cron(trigger["cron"], trigger["timezone"], server["server"].get("timeZone"))
        if code == "t3-cron":
            refuse(code, "trigger.cron")
        elif code:
            refuse(code, "trigger.timezone", zone=server["server"].get("timeZone") or "unknown")
    elif "at" in trigger:
        if t3_instant(trigger["at"]) <= t3_instant(server["now"]):
            refuse("t3-at-past", "trigger.at")
        schedule = {"type": "once", "runAt": trigger["at"]}
    elif "in" in trigger:
        unit = {"m": "minutes", "h": "hours", "d": "days"}[trigger["in"][-1]]
        run_at = t3_instant(server["now"]) + datetime.timedelta(**{unit: int(trigger["in"][:-1])})
        schedule = {"type": "once", "runAt": run_at.strftime("%Y-%m-%dT%H:%M:%SZ")}
    else:
        schedule = {"type": "webhook"}
    if "check" in fields and not check_text.startswith("#!"):
        refuse("t3-check-start", "check.run")
    for key in ("provider", "model", "reasoning"):
        if "agent" in fields and fields["agent"][key] != thread[key]:
            refuse("t3-provider", "agent." + key)
            break
    if isinstance(fields.get("secrets"), list) and fields["secrets"]:
        refuse("t3-secrets", "secrets")
    prompt = None
    if not any(r["code"] == "t3-check-start" for r in found):
        prompt = t3_render(rules["templates"], fields, body, file_rel, check_text, server["state"])
        if schedule == {"type": "webhook"} and "{{" in prompt:
            holders = [n for n in sorted(fields.get("params", {})) if "{{" in str(fields["params"][n])]
            refuse("t3-webhook-prompt", "params." + holders[0] if holders else "file")
    if found:
        order = list(rules["refusals"])
        return {"refusals": sorted(found, key=lambda r: order.index(r["code"])), "unmanaged": unmanaged}
    title = "%s [wizloop:%s]" % (fields["name"], loop_id)
    if managed:
        task = managed[0]
        change = {}
        if task["title"] != title:
            change["title"] = title
        if task["prompt"] != prompt:
            change["prompt"] = prompt
        if not t3_same_schedule(task["schedule"], schedule):
            change["schedule"] = schedule
        if not change:
            return {"unchanged": task["scheduledTaskId"], "unmanaged": unmanaged}
        return {"schedule_task": dict(scheduledTaskId=task["scheduledTaskId"], **change), "unmanaged": unmanaged}
    task = {"title": title, "prompt": prompt, "schedule": schedule, "bindToCurrentThread": bind, "freshSession": not bind}
    return {"schedule_task": task, "unmanaged": unmanaged}


def t3_marker_name(title):
    match = T3_MARKER.match(title)
    return match.group(1) if match else title


def t3_export(rules, tasks):
    found = []
    template_res = [re.compile("^" + T3_TEMPLATE_PART.sub("(.+?)", re.escape(t).replace("\\<", "<").replace("\\>", ">")) + "$", re.S) for t in rules["templates"].values()]
    for task in tasks:
        loop_id = t3_marker(task["title"])
        if loop_id is None:
            continue
        reasons = []
        if (task["boundThreadId"] is None) != task["freshSession"]:
            reasons.append(("thread", "its thread is neither a fresh session per run nor its bound thread's next turn"))
        every = task["schedule"].get("everyMs")
        if every is not None and not (every % 60000 == 0 and 60 % (every // 60000) == 0 and every < 3600000) and not (every % 3600000 == 0 and 24 % (every // 3600000) == 0 and every < 86400000):
            reasons.append(("schedule", "its interval is not every N minutes or hours that a cron can say"))
        if not any(r.match(task["prompt"]) for r in template_res) or not task["prompt"].startswith("[wizloop:%s] " % loop_id):
            reasons.append(("prompt", "its prompt is not one these rules write"))
        for field, reason in reasons:
            message = rules["refusals"]["t3-export"][1].replace("<reason>", reason)
            found.append({"task": task["scheduledTaskId"], "code": "t3-export", "field": field, "message": message})
    return {"refusals": found}


def t3_summary(result):
    if "refusals" in result:
        return "refused: " + ", ".join("`%s` (`%s`)" % (r["code"], r["field"]) for r in result["refusals"])
    if "unchanged" in result:
        return "unchanged"
    return "update" if "scheduledTaskId" in result["schedule_task"] else "create"


def check_t3():
    fixtures_dir = os.path.join(root, "adapters", "fixtures", "t3")
    rules_path = os.path.join(root, "adapters", "t3.v1.md")
    if not os.path.isdir(fixtures_dir) and not os.path.exists(rules_path):
        return 0
    if not os.path.isdir(fixtures_dir):
        problems.append("adapters/fixtures/t3/: not found, so adapters/t3.v1.md has no fixtures")
        return 0
    cases = sorted(n[:-5] for n in os.listdir(fixtures_dir) if n.endswith(".json") and n != "server.json")
    if not os.path.exists(rules_path):
        problems.append("adapters/t3.v1.md: not found, so the %d cases in adapters/fixtures/t3/ have no rules" % len(cases))
        return 0
    text = read_rules(rules_path)
    refusal_rows = section(text, "Refusals")
    field_rows = section(text, "The schedule_task input")
    case_rows = section(text, "The fixtures")
    templates = {"with": section(text, "The prompt with a check", rows=False), "without": section(text, "The prompt without a check", rows=False)}
    if None in (refusal_rows, field_rows, case_rows) or None in templates.values():
        return 0
    rules = {"refusals": {r[0]: (r[1], r[2]) for r in refusal_rows}, "templates": templates}
    input_fields = {r[0] for r in field_rows}
    table = {r[0]: r[1] for r in case_rows}
    for name in sorted(set(cases) - set(table)):
        problems.append("adapters/fixtures/t3/%s: not in the fixtures table of adapters/t3.v1.md" % name)
    for name in sorted(set(table) - set(cases)):
        problems.append("adapters/t3.v1.md: fixture %s is not in adapters/fixtures/t3/" % name)
    code, report = validate("adapters/fixtures/t3")
    if report is not None:
        for f in report["files"]:
            for r in f["refusals"]:
                problems.append("%s: %s: %s (%s)" % (f["file"], r["field"], r["message"], r["code"]))
        for r in report["folder_refusals"]:
            problems.append("%s: %s: %s (%s)" % (r["file"], r["field"], r["message"], r["code"]))
    server = json.load(open(os.path.join(fixtures_dir, "server.json"), encoding="utf-8"))
    seen = {"codes": set(), "schedules": set(), "triggers": set(), "bind": set(), "results": set()}
    for name in cases:
        want = json.load(open(os.path.join(fixtures_dir, name + ".json"), encoding="utf-8"))
        loop_path = os.path.join(fixtures_dir, name + ".md")
        if os.path.exists(loop_path):
            fields, body = read_loop(loop_path)
            check_text = ""
            if "check" in fields:
                check_text = open(os.path.join(fixtures_dir, fields["check"]["run"]), encoding="utf-8").read()
            got = t3_plan(rules, fields, body, "adapters/fixtures/t3/%s.md" % name, check_text, server, want["list"]["tasks"])
            key = "plan"
        else:
            got = t3_export(rules, want["list"]["tasks"])
            key = "export"
        if json.dumps(got, sort_keys=True) != json.dumps(want.get(key), sort_keys=True):
            problems.append("adapters/fixtures/t3/%s: %s is %s, expected %s" % (name, key, json.dumps(got, sort_keys=True), json.dumps(want.get(key), sort_keys=True)))
        if name in table and table[name] != t3_summary(got):
            problems.append("adapters/t3.v1.md: fixture %s says %s, but its result is %s" % (name, table[name], t3_summary(got)))
        for r in got.get("refusals", []):
            seen["codes"].add(r["code"])
            pattern = re.escape(rules["refusals"][r["code"]][0]).replace("\\<", "<").replace("\\>", ">")
            if not re.match("^" + re.sub(r"<[^>]+>", ".+", pattern) + "$", r["field"]):
                problems.append("adapters/fixtures/t3/%s: %s names field %s, not the rules' %s" % (name, r["code"], r["field"], rules["refusals"][r["code"]][0]))
        seen["results"].add(t3_summary(got).split(":")[0])
        task = got.get("schedule_task")
        if task is not None:
            for field in sorted(set(task) - input_fields):
                problems.append("adapters/fixtures/t3/%s: schedule_task has %s, which the rules' input table does not name" % (name, field))
            if "scheduledTaskId" not in task:
                seen["schedules"].add(task["schedule"]["type"])
                seen["triggers"].add(next(iter(fields["trigger"].keys() - {"timezone"})))
                seen["bind"].add(task["bindToCurrentThread"])
    for code in sorted(set(rules["refusals"]) - seen["codes"]):
        problems.append("adapters/fixtures/t3/: no fixture is refused with %s" % code)
    for kind, need in (("schedules", {"interval", "fixed_time", "once", "webhook"}), ("triggers", {"cron", "at", "in", "webhook"}), ("bind", {True, False}), ("results", {"create", "update", "unchanged", "refused"})):
        for item in sorted(need - seen[kind], key=str):
            problems.append("adapters/fixtures/t3/: no fixture covers %s %s" % (kind, json.dumps(item)))
    return len(cases)


t3_cases = check_t3()

for p in problems:
    print("validate: " + p, file=sys.stderr)
if problems:
    sys.exit(1)
print("validate: the catalog and %d fixtures match expected.json" % len(expected))
if t3_cases:
    print("validate: %d T3 runner fixtures match adapters/t3.v1.md" % t3_cases)
