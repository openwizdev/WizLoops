# Cloudroom adapter rules v1

How a loop file ([`format/loop.v1.md`](../format/loop.v1.md)) becomes a
Cloudroom loop, and how a Cloudroom loop becomes a loop file again. OpenWiz's
`openwiz loop plan`, `apply` and `export` follow these rules; WizLoops holds
no code. The commands are `room-cli loop create`, `update` and `list`, as
`room-cli loop --help` describes them.

The adapter never changes a loop silently. When a file asks for something
Cloudroom cannot do exactly, the adapter refuses that file and names the
field; when a Cloudroom loop cannot be written as a valid loop file, export
refuses that loop and names the field.

```text
loop file --plan/apply--> room-cli loop create|update
loop file <--export------ room-cli loop list (JSON)
```

## Which loops are the file's

Cloudroom has no field for a loop file's `id`, so the adapter carries it in
the loop's name, as a **marker** at its end:

```text
<name> [wizloop:<id>]
```

- **Applied:** the Cloudroom name is the file's `name`, one space, then
  `[wizloop:<id>]`.
- **Read back:** a name that ends with one space and `[wizloop:<id>]`, where
  `<id>` is a valid loop id, is the loop with that id; its `name` is the
  part before the space. Any other loop is **unmanaged**: plan and apply
  never change it, and plan lists it as unmanaged, unless the caller adopts
  it (below).
- **Scope:** `room-cli loop list` returns every loop on the account. The
  adapter reads only the loops whose `project_id` is the project it applies
  to; ids are unique there, as they are in one folder.
- **One loop per id:** two loops in that project with the same marker are
  refused (`cf-duplicate-marker`); the adapter changes neither.

### Adopting an unmarked loop

A loop that was made by hand has no marker. The adapter takes it over only
when the caller **adopts** it: an explicit binding of one file's `id` to one
Cloudroom loop `id`, given for that one apply. How the caller passes a
binding is OpenWiz's CLI contract; the binding is never inferred from a name
and never stored in a file.

- **What a binding allows:** apply treats the bound loop as that file's
  managed loop and updates it, adding the marker to its name. It never
  creates a second loop for that file.
- **Checked before any write:** the bound loop is in `list`, in this project,
  and has no marker; no loop in this project already carries the file's
  marker; the binding names a file being applied; and no two bindings name
  the same loop or the same `id`. Any failure is refused
  (`cf-adopt-binding`), and nothing is written for that file.
- **The update rules still hold:** a change `update` cannot make (below) is
  refused, as for any managed loop.
- **No binding, but a name that looks like it:** when a file has no managed
  loop and an unmarked loop in this project has a name whose derived id (the
  rule in "`room-cli loop list` to a file") is the file's `id`, apply
  refuses (`cf-unmarked-match`) instead of creating a second loop. The
  caller adopts that loop, or gives the file another `id`.

**A synthetic round trip.** One project has one unmarked loop:

```json
{"automations": [{"id": "loop-a", "project_id": "project-1", "name": "Hourly kick", "cron": "12 * * * *", "timezone": "UTC", "run_at": null, "webhook": false, "new_thread": true, "script": "#!/bin/sh\nexit 0\n", "agent": null, "secrets": [], "priority": 3, "prompt": "Nothing to do.", "enabled": true}]}
```

1. Export writes `hourly-kick.md` (`id` `"hourly-kick"`, derived from the
   name) and `hourly-kick/check`, and reports the pair `hourly-kick` and
   `loop-a` to its caller, as the binding it would need.
2. Plan on that file with no binding: no loop carries `[wizloop:hourly-kick]`,
   and `loop-a`'s name derives `hourly-kick`, so it refuses
   (`cf-unmarked-match`). Nothing is created.
3. Plan with the binding `hourly-kick` to `loop-a`: one update of `loop-a`,
   `--name "Hourly kick [wizloop:hourly-kick]"`, and nothing else differs.
   No create.
4. After apply, `loop-a` carries the marker; the next plan, with no binding,
   matches it by marker and shows no difference.

## Params: the body and the check's preamble

The format's "Params" gives a param two ways in: a placeholder in the body,
and an environment variable for the check. Cloudroom has no field for
params and no way to set a loop's environment, so the adapter carries them
like this:

- **The body:** the adapter replaces each placeholder with its param's
  value, as the format says. The result is the Cloudroom `prompt`.
- **The check:** the adapter never replaces anything in the check's text.
  It puts a fixed **preamble** in the script, after the check's first
  line, that exports the params the check uses. The result is the
  Cloudroom `script`.

The **rendered script** of a file with a check is built from the check's
text `C`, byte for byte:

1. **The params it carries** are the params the check uses (the format's
   rule: its text names `WIZLOOP_PARAM_<NAME>`), in byte order of their
   names. A param only the body uses is not in the preamble.
2. **Never mistaken for a preamble:** a check whose own second line is
   exactly `# wizloop: params from the loop file, as data` is refused
   (`cf-check-preamble`), with params or without, because export could not
   tell that line from the adapter's.
3. **None:** the rendered script is `C` exactly, with no preamble.
4. **Some:** `C` must start with one of these lines, LF included, because
   the preamble is POSIX shell: `#!/bin/sh`, `#!/bin/bash`,
   `#!/usr/bin/env sh` or `#!/usr/bin/env bash`. Any other first line,
   or none, is refused (`cf-check-shell`). The rendered script is then
   `C`'s first line, the preamble, and the rest of `C`:

```text
<C's first line>
# wizloop: params from the loop file, as data
export WIZLOOP_PARAM_<NAME>=<value>        one line per param it carries
# wizloop: the check
<the rest of C, from its second line, byte for byte>
```

Each `<value>` is written so the shell reads it back exactly, as data:

- **A string:** POSIX single-quoted. The value is wrapped in `'`, and each
  `'` in it is written as `'\''`. Nothing inside single quotes is expanded,
  so `$(...)`, backticks, `"`, `;` and `\` stay literal. A string has no
  line break or NUL (the format refuses it as `multiline-param`), so each
  export is one line.
- **An integer:** its decimal digits, with a leading `-` if negative, not
  quoted.

Nothing else is ever substituted into the script. A synthetic example: the
check uses `ref`, `repo` and `spec`, and `spec` is the integer `7`.

```sh
#!/bin/sh
# wizloop: params from the loop file, as data
export WIZLOOP_PARAM_REF='it'\''s $(touch marker) `id`'
export WIZLOOP_PARAM_REPO='example-org/example-repo'
export WIZLOOP_PARAM_SPEC=7
# wizloop: the check
gh issue list -R "$WIZLOOP_PARAM_REPO"
```

When it runs, `WIZLOOP_PARAM_REF` holds `` it's $(touch marker) `id` ``
exactly, and nothing in it runs.

**Reading the preamble back.** Export reads a `script` this way:

- Its second line is not exactly `# wizloop: params from the loop file, as
  data`: the script has no preamble, the exported check is the whole
  `script`, and it carries no params.
- Otherwise the preamble runs to the first later line that is exactly
  `# wizloop: the check`. Each line between is one export:
  `export WIZLOOP_PARAM_<NAME>=` and then a value, either an integer
  (`-?(0|[1-9][0-9]*)`) or a single-quoted string as above, read by undoing
  the quoting. `<NAME>` in lower case is the param's name; an unquoted value
  is an integer, a quoted one a string. The exported check is the script's
  first line followed by everything after the `# wizloop: the check` line.
- **Exactly, or not at all:** export renders the file it read back (its
  check and its params, as above) and compares that with `script` byte for
  byte. A missing end line, a line that is not one export, a name that is
  not a param name, names out of byte order or repeated, or any other
  difference is refused (`cf-export-preamble`), and nothing is written for
  that loop.

A param only the body uses reached Cloudroom only inside the prompt's text,
so export cannot read it back as a param: the exported body holds its
value, as written.

## A file to `room-cli loop create`

| Field | `room-cli loop create` flag |
| --- | --- |
| `id`, `name` | `--name "<name> [wizloop:<id>]"` |
| body | `--prompt-file <the body, with its placeholders replaced>` |
| `trigger` cron | `--cron "<cron>" --timezone <timezone>` |
| `trigger` at | `--at <at>` |
| `trigger` in | `--in <in>` |
| `trigger` webhook | `--webhook` |
| `thread` | `"new"`: `--new-thread`; `"same"`: `--same-thread` |
| `check` | `--script-file <the rendered script>`: the check with its params preamble (above). `check.timeout` has no flag: see "Limits" |
| `agent` | `--provider <provider> --model <model> --reasoning <reasoning>`; omitted, no flags (the caller's agent) |
| `priority` | `--priority <priority>`, always, even for the default 3 |
| `secrets` | `[]`: `--secrets none`; `"all"`: `--secrets all`; otherwise `--secrets <items joined by ,>`, in file order (`.env` as written). Always passed, so the file, not Cloudroom's default, decides |

The flags come in the order of the table. With no `check`, no
`--script-file`; with no `agent`, no agent flags.

## A file to `room-cli loop update`

When a managed loop exists and differs from its file, apply updates it with
`room-cli loop update <Cloudroom id>` and only the flags for fields that
differ: `--name`, `--priority`, `--prompt` (the body's text, with its
placeholders replaced), `--cron` with `--timezone`, `--at` or `--in`,
`--script-file` (the rendered script, preamble included),
`--provider` with `--model` and `--reasoning`, and `--secrets`.

`update` has no flag for these changes, so the adapter refuses them and
names the field; it never deletes and recreates a loop in v1:

| Change | Refusal |
| --- | --- |
| A trigger to or from `webhook` | `cf-update-webhook` |
| `thread` from `same` to `new` or back | `cf-update-thread` |
| Removing the `check` | `cf-update-remove-check` |
| Removing the `agent` (back to the caller's) | `cf-update-remove-agent` |

## `room-cli loop list` to a file

`room-cli loop list` prints `{"automations": [...]}`. Each item maps back:

| `list` key | Loop file |
| --- | --- |
| `name` | `id` from the marker and `name` from the rest, as above. Unmarked: export derives `id` from the name (lowercase it, turn each run of characters other than `a-z` and `0-9` into one `-`, trim `-` from both ends, keep at most 64 characters, trim a trailing `-`) and reports that `id` with the loop's Cloudroom `id` as the binding an apply needs to adopt it (above). Two unmarked loops in the project that derive the same `id` are both refused (`cf-export-id`) |
| `cron`, `timezone` | `cron` set: `trigger` `{"cron": <cron>, "timezone": <timezone>}` |
| `run_at` | `run_at` set: `trigger` `{"at": <run_at>}`, exactly as Cloudroom wrote it |
| `webhook` | `true`: `trigger` `{"webhook": true}`. The address is never in `list` and never in the file |
| `script` | `null`: no `check`. Text: `check` `{"run": "<id>/check", "timeout": 60}`; the preamble, if any, is read back into `params` and the check without it is written byte for byte to `<id>/check` beside the loop file (see "Reading the preamble back") |
| `new_thread` | `true`: `thread` `"new"`; `false`: `"same"` |
| `agent` | `null`: no `agent`. An object: `agent` with its `provider`, `model` and `reasoning` |
| `secrets` | `null` (every secret): `secrets` `"all"`. `[]`: `secrets` `[]`. A list: the same list. Each is kept exactly, for both thread kinds; a same-thread loop with a non-empty list is refused, as the format requires (`cf-export-invalid`, `same-thread-secrets`) |
| `priority` | `priority` |
| `prompt` | the body |

- **`in` reads back as `at`.** Cloudroom keeps a `--in` loop as its
  `run_at`, so an `in` file can only create a loop, and export writes the
  `at` it became.
- **Params read back from the preamble.** Each param the check carries
  comes back with its value and type. A param only the body used comes
  back as text in the body, not as a param (above).
- **Not mapped:** `enabled`, `last_error`, `last_run_at`, `next_run_at` and
  `runs` (run state, not definition) and `timezone` when `cron` is `null`.
  `id`, `project_id` and `session_id` are Cloudroom's own identifiers: the
  adapter uses `id` to address `update` and `project_id` for scope, and
  writes none of the three to a file.
- A loop with none of `cron`, `run_at` and `webhook` is refused
  (`cf-export-trigger`).
- **Export writes only valid files.** If a mapped loop would not be a valid
  loop file (a name over 100 characters, an agent value with a space, a
  `{{` in the prompt, a `{{name}}` placeholder in the script), export
  refuses it with `cf-export-invalid`, naming the format's field and code.

## How plan compares

Plan maps each file as in "A file to `room-cli loop create`", maps its
managed loop back as in "`room-cli loop list` to a file", and compares field
by field:

- `name`, `thread`, `agent`, `priority`, and the trigger's kind and values
  must be equal; the body after its placeholders are replaced must equal
  `prompt` byte for byte, and the rendered script must equal `script` byte
  for byte. The preamble is part of that comparison, so a changed value of
  a param the check uses, or a change in which params it uses, is a
  difference in `--script-file`; a changed value of a param only the body
  uses is a difference in `--prompt`.
- `secrets` are compared exactly, with a list as a set (Cloudroom may keep
  it in another order): `"all"` equals only `null`, and `[]` equals only
  `[]`. `null` and `[]` are never treated as equal, for either thread kind,
  so a loop that gets every secret and a file that grants none always show
  as a difference.
- `at` is compared as an instant: `2030-01-02T03:04:05Z` and
  `2030-01-02T03:04:05.000+00:00` are equal.
- **An `in` file never matches an existing loop.** Its delay became an
  absolute `run_at` when it was applied, and `list` cannot show whether a
  `run_at` came from this delay or from anything else. So an `in` file with
  a managed (or bound) loop is refused (`cf-in-existing`), whatever that
  loop's trigger is: the caller writes the `at` it means, or gives the file
  a new `id`. Example: a managed reminder has `run_at` next week, and its
  file is changed to `{"in": "30m"}`; plan refuses, rather than reporting
  no change and leaving the reminder next week.
- `check.timeout` is always 60 on both sides (see "Limits").
- A paused managed loop (`enabled: false`) is reported as paused; plan and
  apply neither pause nor resume loops.
- A file with no managed loop is a create, unless `cf-unmarked-match`
  refuses it; a bound loop is the file's managed loop. A managed loop with
  no file is reported and left alone (v1 never deletes).

## Limits the adapter reports

| Limit | What the adapter does |
| --- | --- |
| **A check runs for 60 seconds** in Cloud, and the adapter cannot set another bound | Any `check.timeout` but 60 is refused (`cf-check-timeout`). Over 60, Cloudroom would stop the check early; under 60, Cloudroom would let a late check's output start an agent that the file says must not start. The adapter does not wrap the script to enforce a shorter bound in v1 |
| **A loop without a check runs at most every 15 minutes** | A `cron` trigger with no `check` that can be due twice within 15 minutes is refused (`cf-too-frequent`). The rule: list the minutes of the day the minute and hour fields allow; if any two in a row, including the last of one day and the first of the next, are less than 15 minutes apart, it is refused. With a check, a loop may run every minute |
| **A webhook address is shown once** | `create` prints the address once. Apply passes it to its caller once, and never writes it to a file, a plan or a log. Plan cannot show it. `room-cli loop hook <id>` replaces it; the adapter does not call it in v1 |
| **Loops cannot be created from a thread a loop started** | Apply must run from an ordinary thread or a terminal. If Cloudroom refuses for this reason, apply reports Cloudroom's error unchanged and reports the loop as not created |
| **An agent is set only on new-thread loops** | A file with `thread` `"same"` and an `agent` is refused (`cf-agent-same-thread`) |
| **Secrets are limited only on new-thread loops** | The format allows only `[]` or `"all"` for `thread` `"same"`, and says a same-thread run keeps its thread's environment: Cloudroom re-prompts that thread, and its check runs in that thread's sandbox. The adapter passes the file's value (`--secrets none` or `--secrets all`) and keeps what `list` returns exactly, so export and plan round-trip it; plan states that a same-thread run has the thread's own environment whatever the value. `room-cli loop --help` documents `--secrets` only for fresh-thread loops, so what each value changes for a same-thread run is an inference from the help text, not a live observation |
| **A one-time trigger in the past** | An `at` time that has passed is refused at create (`cf-at-past`); an existing managed `at` loop still matches its file |

Also true of Cloudroom, and reported by plan where it applies: a check's
exit codes follow the format (0 or 1 is fine, anything else fails the run),
and 3 failed runs in a row pause the loop; one run of a loop waits for the
last to finish; Cloudroom documents up to 100 Cloud loops per account.

## Refusals

A refusal names the file (or, for export, the Cloudroom loop's name), the
field and the message, with a stable code, printed as the format's are.

| Code | Field | Message |
| --- | --- | --- |
| `cf-duplicate-marker` | `id` | `two Cloudroom loops in this project carry [wizloop:<id>]` |
| `cf-adopt-binding` | `id` | `the binding to Cloudroom loop <loop> cannot be used: <reason>` |
| `cf-unmarked-match` | `id` | `an unmarked Cloudroom loop in this project has this name; adopt it or choose another id` |
| `cf-in-existing` | `trigger.in` | `an in trigger can only create a loop; write the at time instead` |
| `cf-export-id` | `id` | `another unmarked loop in this project derives the same id` |
| `cf-check-shell` | `check.run` | `Cloudroom passes params to a check through a shell preamble; its first line must be #!/bin/sh, #!/bin/bash, #!/usr/bin/env sh or #!/usr/bin/env bash` |
| `cf-check-preamble` | `check.run` | `the check's second line is the adapter's preamble line; change that line` |
| `cf-export-preamble` | `check` | `the script's params preamble is not one this adapter writes` |
| `cf-check-timeout` | `check.timeout` | `Cloudroom runs a check for exactly 60 seconds; set the timeout to 60` |
| `cf-too-frequent` | `trigger.cron` | `Cloudroom runs a loop without a check at most every 15 minutes` |
| `cf-agent-same-thread` | `agent` | `Cloudroom sets an agent only for new-thread loops` |
| `cf-at-past` | `trigger.at` | `the time has passed` |
| `cf-update-webhook` | `trigger` | `Cloudroom cannot change a loop to or from a webhook` |
| `cf-update-thread` | `thread` | `Cloudroom cannot change a loop's thread` |
| `cf-update-remove-check` | `check` | `Cloudroom cannot remove a loop's check` |
| `cf-update-remove-agent` | `agent` | `Cloudroom cannot return a loop to the caller's agent` |
| `cf-export-trigger` | `trigger` | `the loop has no cron, run time or webhook` |
| `cf-export-invalid` | `<field>` | `would be refused by the format as <code>` |

## The rule for every adapter

A loop must be able to wake or message the orchestrator: a run either
prompts the orchestrator's own thread again (`thread` `"same"`) or can send
it a message. Cloudroom meets this with `--same-thread` loops, and a
new-thread run can message other threads. An agent workspace that can do
neither gets no adapter; there is no GitHub Actions fallback.

## The format's fixtures under these rules

Each valid fixture in [`format/fixtures/valid/`](../format/fixtures/valid/),
created fresh (no managed or unmarked loop with its id yet), with an `at`
time still in the future. `cron-check.md`, `script-only.md` and
`same-thread-agent.md` use a 60-second check, the only one Cloudroom
applies; `invalid/same-thread-secrets.md` is refused by the format itself.
Exported back, each create below reads back as its own file, `secrets`
included:

| Fixture | Result |
| --- | --- |
| `cron-check.md` | `create --name "Example triage every ten minutes [wizloop:cron-check]" --prompt-file <body> --cron "*/10 * * * *" --timezone UTC --new-thread --script-file <check> --provider example-provider --model example-model --reasoning medium --priority 2 --secrets EXAMPLE_TOKEN,.env` |
| `at-same.md` | `create --name "One reminder [wizloop:at-same]" --prompt-file <body> --at 2030-01-02T03:04:05Z --same-thread --priority 3 --secrets none` |
| `in-same.md` | `create --name "Look again in half an hour [wizloop:in-same]" --prompt-file <body> --in 30m --same-thread --priority 1 --secrets none` |
| `webhook-new.md` | `create --name "Wake on a delivery [wizloop:webhook-new]" --prompt-file <body> --webhook --new-thread --priority 4 --secrets none` |
| `script-only.md` | `create --name "Kick an example job hourly [wizloop:script-only]" --prompt-file <body> --cron "12 * * * *" --timezone America/Los_Angeles --new-thread --script-file <check> --priority 3 --secrets none` |
| `all-secrets-new.md` | `create --name "A new-thread loop with every secret [wizloop:all-secrets-new]" --prompt-file <body> --cron "0 5 * * *" --timezone UTC --new-thread --priority 3 --secrets all`; `list` then shows `"secrets": null`, which exports as `"all"` |
| `all-secrets-same.md` | `create --name "A same-thread loop with every secret [wizloop:all-secrets-same]" --prompt-file <body> --cron "15 5 * * *" --timezone UTC --same-thread --priority 3 --secrets all`; reads back as `"all"` the same way |
| `params-env.md` | `create --name "Params reach the check as data [wizloop:params-env]" --prompt-file <body> --cron "30 6 * * *" --timezone UTC --new-thread --script-file <check> --priority 3 --secrets none` |
| `python-check.md` | refused: `cf-check-shell` (`check.run`): its check uses `repo` and starts `#!/usr/bin/env python3` |
| `same-thread-agent.md` | refused: `cf-agent-same-thread` (`agent`) |
| `fast-no-check.md` | refused: `cf-too-frequent` (`trigger.cron`) |
| `long-check.md` | refused: `cf-check-timeout` (`check.timeout`, 120) |
| `short-check.md` | refused: `cf-check-timeout` (`check.timeout`, 30) |

`<body>` is a file holding the body with its placeholders replaced, and
`<check>` a file holding the rendered script. `cron-check.md`'s prompt-file
holds `Triage the due items for spec 42 that the check printed below.`, and
its script-file holds exactly:

```sh
#!/bin/sh
# wizloop: params from the loop file, as data
export WIZLOOP_PARAM_REPO='example-org/example-repo'
# wizloop: the check
# Prints one line per due item in $WIZLOOP_PARAM_REPO; nothing when none is due.
if [ -f due.txt ]; then cat due.txt; fi
exit 0
```

`params-env.md` carries PR-review injection payloads as param values.
`note` is used only in the body, so its prompt-file holds
`Report the check's output for spec 7 in example-org/example-repo.`, and
its script-file holds exactly:

```sh
#!/bin/sh
# wizloop: params from the loop file, as data
export WIZLOOP_PARAM_REF='release/";printf${IFS}WAKE;false${IFS}"'
export WIZLOOP_PARAM_REPO='example-org/example-repo'
export WIZLOOP_PARAM_SPEC=7
export WIZLOOP_PARAM_TITLE='it'\''s $(touch marker) `touch marker`'
# wizloop: the check
# Reads its params from the environment as data and prints nothing, so no
# agent starts: $WIZLOOP_PARAM_REPO, $WIZLOOP_PARAM_REF, $WIZLOOP_PARAM_TITLE
# and $WIZLOOP_PARAM_SPEC.
exit 0
```

Exported back, each reads back as its file's own check and the params it
carries: `cron-check.md` with `params` `{"repo": "example-org/example-repo"}`
and the body's `42` as text, and `params-env.md` with `ref`, `repo`,
`spec` (the integer `7`) and `title`.
