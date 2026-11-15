# Loop file format v1

A **loop** is an alarm clock for a coding agent: a trigger wakes it, an
optional check decides whether there is work, and an agent gets the prompt.
A **loop file** is one Markdown file that defines one loop: frontmatter for
the settings, and the body for the prompt.

This is WizLoops' main contract. The schema for the parsed frontmatter is
[`loop.v1.schema.json`](loop.v1.schema.json) (JSON Schema draft 2020-12,
`$id` `wizloops.loop.v1`). The [fixtures](fixtures/) are the shared test
seam: [`fixtures/expected.json`](fixtures/expected.json) names every
fixture's expected result. Nothing in this contract is specific to one agent
workspace; each adapter's rules live in `adapters/`.

```text
loop file -> frontmatter (settings) + body (prompt)
trigger -> check (optional) -> no output: no agent
                            -> output: the agent gets the prompt and the output
```

## An example

```markdown
---
id: "nightly-report"
name: "Nightly report"
trigger: {"cron": "0 2 * * *", "timezone": "UTC"}
check: {"run": "nightly-report/check.sh", "timeout": 30}
thread: "new"
agent: {"provider": "example-provider", "model": "example-model", "reasoning": "medium"}
secrets: ["EXAMPLE_TOKEN"]
priority: 2
params: {"repo": "example-org/example-repo"}
---
Read the check's output about {{repo}} and post a short report on its open
issues. Say nothing that the output does not show.
```

## Reading a file

A reader reads the file as bytes and checks, in this order:

1. **Encoding.** The file is UTF-8, with no byte order mark, no NUL byte and
   no carriage return (line ends are LF only).
2. **Frontmatter start.** The first line is exactly `---`.
3. **Frontmatter end.** A later line is exactly `---`. The lines between the
   two are the frontmatter; everything after the closing line's LF is the
   body. A file that ends right after the closing `---` has an empty body.
4. **Lines.** Each frontmatter line is one `key: value`, as below.
5. **Fields.** Each field is checked as in "Fields".
6. **Body and params.** The body and the check's text are checked as in
   "Body" and "Params".

A failure in steps 1 to 3 stops the file: only that one refusal is reported.
A failure in step 4 stops the file after every line has been read: each bad
line is reported, in line order. Steps 5 and 6 report every problem they
find: first step 5's, in the order of the frontmatter lines (and, for one
line, in the order of the refusal tables below), then the body's, then the
check script's, then each unused param in the order `params` lists them;
then a `missing-field` refusal for each missing top-level field, in the
order of the fields table. A missing key inside `trigger`, `check` or
`agent` is reported with that field's line.

### The frontmatter subset

The frontmatter reads as YAML but parses with no YAML library. Each line is:

```text
<key>: <value>
```

- `<key>` matches `^[a-z][a-z0-9_]*$` and starts the line.
- Then exactly `: ` (a colon and one space).
- `<value>` is the rest of the line, and is exactly one JSON value
  (RFC 8259): a string, a number, `true`, `false`, `null`, an array or an
  object, on that one line. No space may come before it or after it; spaces
  inside a JSON array or object are fine.
- There are no blank lines, no comments, no YAML-only forms (unquoted
  strings, `- item` lists, `|` blocks, anchors) and no line continuations.
  A line with a good key and `: ` but a value that is not JSON (an
  unquoted string, a `|`) is refused as `json`; any other bad line as
  `line-syntax`.
- A key appears at most once. Inside any JSON object, at any depth, a key
  appears at most once: a reader refuses duplicates before it builds the
  object, so `{"a": 1, "a": 2}` is refused, never collapsed.
- Keys may come in any order.
- **Integers** are JSON numbers with no fraction and no exponent:
  `2` is an integer, `2.0` and `2e0` are not.

## Fields

| Field | Type | Required | Default | Meaning |
| --- | --- | --- | --- | --- |
| `id` | string | yes | | The loop's stable id: 1 to 64 characters, lowercase ASCII letters, digits and `-`, starting with a letter or digit (`^[a-z0-9][a-z0-9-]{0,63}$`). Unique among the loop files in one folder. Renaming the file keeps the loop; changing the id makes a new one |
| `name` | string | yes | | A display name: 1 to 100 characters, with at least one that is not whitespace, and no control characters (U+0000 to U+001F, U+007F) |
| `trigger` | object | yes | | When the loop wakes: exactly one trigger kind, below |
| `check` | object | no | none | A script that runs first, below. With no check, every wake gives the agent the prompt |
| `thread` | string | yes | | `"new"`: each run starts a fresh thread. `"same"`: each run prompts again the thread that applied the loop |
| `agent` | object | no | the caller's | `{"provider": "...", "model": "...", "reasoning": "..."}`, all three required, each 1 to 100 characters with no whitespace or control characters. Omitted: the agent of whoever applies the loop |
| `secrets` | array | no | `[]` | The only secrets the loop's runs and its check get. Each item is an environment variable name (`^[A-Z][A-Z0-9_]*$`) or `".env"` (the project's `.env` files), at most once each. `[]` means none. There is no "all" |
| `priority` | integer | no | `3` | 1 (essential) to 4 (niche) |
| `params` | object | no | `{}` | Named values the prompt and the check use, below |

No other field is allowed. In particular, budgets, shadow mode and in-file
approval are not part of v1: a loop is approved by the pull request that
adds its file.

### Trigger

`trigger` is an object with exactly one of these kinds:

| Kind | Shape | Meaning |
| --- | --- | --- |
| cron | `{"cron": "<5 fields>", "timezone": "<zone>"}` | Repeats on a cron schedule in that timezone. Both keys are required |
| at | `{"at": "<time>"}` | Runs once, at that time |
| in | `{"in": "<delay>"}` | Runs once, that long after the loop is applied |
| webhook | `{"webhook": true}` | Runs when its webhook address receives a request |

- **`cron`** has exactly five fields separated by one space: minute
  (0-59), hour (0-23), day of month (1-31), month (1-12), day of week
  (0-6, 0 is Sunday). Each field is `*` or a comma-separated list of
  items; each item is a number, a range `a-b` with `a <= b`, or either of
  those or `*` followed by a step `/n` with `n >= 1`. Numbers are decimal
  with no sign and no leading zero (`0` itself is fine). Names (`MON`,
  `JAN`), `?`, `L`, `W`, `#` and the `@daily` forms are not allowed.
  When both day fields are restricted, a run is due when either one
  matches (the usual cron rule).
- **`timezone`** is `UTC` or an IANA zone name of the form `Area/City`
  (`^[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+)+$`), such as
  `America/Los_Angeles`. A reader with the IANA database should also refuse
  a zone it does not have; the fixtures use only zones that exist.
- **`at`** is an RFC 3339 time with seconds and an explicit offset:
  `2030-01-02T03:04:05Z` or `2030-01-02T03:04:05-08:00`, with optional
  fractional seconds. A time in the past is valid in the file; whether to
  apply it is the adapter's call.
- **`in`** is a whole number from 1 with one unit, `m` (minutes), `h`
  (hours) or `d` (days), with no leading zero: `30m`, `2h`, `1d`.
- **`webhook`** is `true`. The address is the workspace's and never goes in
  the file.

### Check

`check` is `{"run": "<path>", "timeout": <seconds>}`, both required.

- **`run`** is the check script's path, relative to the folder that holds
  the loop file: `/`-separated, with no empty, `.` or `..` segment, not
  starting with `/`, with no `\`. It names a regular file that exists, not
  a symlink, and that file is UTF-8 text with no NUL. The script is run as
  its first line (`#!`) says.
- **`timeout`** is an integer number of seconds, 1 to 900.

When the loop wakes, the check runs first:

- It ends with exit code 0 or 1 and prints nothing on standard output: the
  wake is quiet and no agent starts.
- It ends with exit code 0 or 1 and prints something: the agent gets the
  prompt with that output added.
- Any other exit code, or running past `timeout`, fails the run; no agent
  starts.

A check that never prints anything makes a **script-only loop**: the check
does the work, and no agent ever starts. Its body is still required.

### Body

The body is the prompt. It must have at least one character that is not
whitespace.

### Params

`params` is an object. Each key is a param name (`^[a-z][a-z0-9_]*$`); each
value is a JSON string or an integer.

A **placeholder** is `{{name}}`: two `{`, a param name, two `}`, with no
spaces. Placeholders may appear in the body and in the check script's text.
When the loop is applied, each placeholder is replaced by its param's value
(an integer as its decimal digits). A param's value in the file is its
default; how a caller passes another value is the caller's contract, and a
caller may only set params the file declares.

- Every placeholder in the body or the check names a declared param.
- Every declared param is used at least once, in the body or the check. A
  param refused as `bad-param-name` is not checked for use.
- Every `{{` in the body or the check starts a valid placeholder. v1 has no
  escape for a literal `{{`.

## Refusals

A refusal names the file, a **field** and a **message**, and has a stable
**code**. A reader prints each one as `<file>: <field>: <message>`. In the
tables, `<field>` is the field's dotted path (`trigger.cron`,
`agent.model`, `params.repo`), `<n>` is a 1-based line number and `<key>`
is a key as written. Messages are exact; only the parts in `<>` vary.

### The file (steps 1 to 4)

| Code | Field | Message |
| --- | --- | --- |
| `encoding` | `file` | `must be UTF-8 with LF line ends, no byte order mark and no NUL` |
| `frontmatter-start` | `file` | `must start with a line of exactly ---` |
| `frontmatter-end` | `file` | `frontmatter has no closing line of exactly ---` |
| `line-syntax` | `line <n>` | `must be "key: value" with one JSON value` |
| `json` | `<key>` | `value is not one JSON value` |
| `duplicate-key` | `<field>` | `appears more than once` |

`line-syntax` covers a blank line, a comment, a bad key, a missing `: `, a
space before or after the value, and any other line that is not the form
above. `json` is for a line whose key is fine but whose value does not parse
as exactly one JSON value. `duplicate-key` is for a repeated frontmatter key
and for a repeated key inside a JSON object; its field is the repeated
key's dotted path.

### Fields (step 5)

| Code | Field | Message |
| --- | --- | --- |
| `unknown-field` | `<field>` | `is not a field of loop v1` |
| `missing-field` | `<field>` | `is required` |
| `wrong-type` | `<field>` | `must be <type>` |
| `bad-id` | `id` | `must be 1 to 64 lowercase letters, digits and hyphens, starting with a letter or digit` |
| `bad-name` | `name` | `must be 1 to 100 characters, not all whitespace, with no control characters` |
| `trigger-kind` | `trigger` | `must have exactly one of cron, at, in or webhook` |
| `bad-cron` | `trigger.cron` | `must be five cron fields: minute hour day-of-month month day-of-week` |
| `bad-timezone` | `trigger.timezone` | `must be UTC or an IANA zone such as Area/City` |
| `bad-at` | `trigger.at` | `must be an RFC 3339 time with seconds and an offset` |
| `bad-in` | `trigger.in` | `must be a whole number from 1 followed by m, h or d` |
| `bad-webhook` | `trigger.webhook` | `must be true` |
| `bad-check-path` | `check.run` | `must be a relative path inside the loop's folder, with no . or .. segments` |
| `check-not-found` | `check.run` | `must name an existing regular file of UTF-8 text` |
| `bad-timeout` | `check.timeout` | `must be 1 to 900 seconds` |
| `bad-thread` | `thread` | `must be "same" or "new"` |
| `bad-agent` | `agent.<key>` | `must be 1 to 100 characters with no whitespace` |
| `bad-secret` | `secrets` | `each item must be an environment variable name or ".env"` |
| `duplicate-secret` | `secrets` | `names <item> more than once` |
| `bad-priority` | `priority` | `must be 1 to 4` |
| `bad-param-name` | `params` | `name <key> must be lowercase letters, digits and underscores, starting with a letter` |

- **`unknown-field`** is for a frontmatter key that is not in the fields
  table, and for an extra key inside `trigger`, `check` or `agent`
  (`agent.service_tier`). A `trigger` with an unknown key and no known kind
  is refused as `unknown-field` and `trigger-kind`. `timezone` is an
  unknown key only beside another kind: `{"at": "...", "timezone": "UTC"}`
  is `unknown-field` (`trigger.timezone`), while `{"timezone": "UTC"}`,
  with no kind, is `trigger-kind` alone.
- **`missing-field`** is for `id`, `name`, `trigger`, `thread`, and for
  `trigger.timezone` with `trigger.cron`, `check.run`, `check.timeout`,
  `agent.provider`, `agent.model` and `agent.reasoning`.
- **`wrong-type`**'s `<type>` is one of `a string`, `an integer`,
  `an object`, `an array`, or `a string or an integer` (a param's
  value). Any `trigger.webhook` value but `true` is `bad-webhook`, and any
  `secrets` item that is not a string is `bad-secret`. A field of the wrong type gets no other check. `null` is a wrong
  type for every field; an optional field is left out, never `null`.
- A **`trigger-kind`** refusal stops that trigger's other checks: a
  trigger with both `cron` and `at` is one refusal, not three.
- **`check-not-found`** is checked only when `check.run` passed
  `bad-check-path`.

### Body and params (step 6)

| Code | Field | Message |
| --- | --- | --- |
| `empty-body` | `body` | `the prompt must not be empty` |
| `bad-placeholder` | `body` or `check` | `{{ must start a placeholder {{name}}` |
| `undeclared-param` | `body` or `check` | `uses {{<name>}}, which params does not declare` |
| `unused-param` | `params.<name>` | `is declared but never used` |

### Folders

A reader given a folder checks every `*.md` file directly inside it, except
`README.md`, as a loop file, and then:

| Code | Field | Message |
| --- | --- | --- |
| `duplicate-id` | `id` | `<id> is also the id of <other file>` |

`duplicate-id` is reported on each file after the first, in byte order of
file name, naming the first.

## The fixtures

[`fixtures/`](fixtures/) holds synthetic loop files:

- `fixtures/valid/`: files every reader must accept. Together they cover
  every trigger kind, a check, both thread kinds, an agent, secrets and
  params.
- `fixtures/invalid/`: files every reader must refuse, each with exactly
  one refusal.
- `fixtures/invalid-folder/`: a folder whose files are each valid alone and
  that together must refuse with `duplicate-id`.

[`fixtures/expected.json`](fixtures/expected.json) lists every fixture by
its path relative to `fixtures/`. A valid one has `"result": "valid"` and
`"parsed"`: its frontmatter as JSON with every default filled in (key order
is not significant). An invalid one has `"result": "refused"` and
`"refusals"`: each refusal's `code`, `field` and `message`, in report
order. The folder fixture's entry ends with `/`, and each of its
refusals also has `file`, the refused file's name in that folder. A reader
passes the fixtures when its results match the file exactly, apart from key
order.

Each folder under `valid/` or `invalid/` named after a fixture's id holds
that fixture's check script; it is not itself a fixture.

## What the schema covers

The schema checks the parsed frontmatter's structure: fields, types,
required keys, the trigger kinds, the patterns and the ranges. It cannot
check the frontmatter subset, duplicate keys, the check file, the body,
placeholders or folders; a reader checks those as this contract says. Where
the schema and this contract differ, this contract holds.
