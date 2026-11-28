# Outcome file format v1

An **outcome** records a claim that must stay true and how to prove it
again. A project keeps one Markdown file per outcome directly in
`outcomes/`, as `<id>.md`. Readers skip `README.md`. The frontmatter
holds the settings and the body holds the claim.

The [schema](outcome.v1.schema.json) identifies this format as
`openwiz.outcome.v1`. Reading or validating a file runs nothing and
grants nothing. A proof runner uses the project's own authorization
for commands and secrets. The allowed paths describe the scope of a
future fix.

## Example

`outcomes/sample-report.md`:

```markdown
---
id: "sample-report"
proof: {"run": "test -f sample/report.txt", "timeout": 30}
allowed_paths: ["sample/report.txt", "examples/"]
cadence: {"cron": "0 9 * * 1-5", "timezone": "UTC"}
enabled: false
secrets: ["EXAMPLE_REPORT_KEY"]
---
The sample report is present.
```

## Reading a file

Use UTF-8 with LF line ends, no byte order mark and no NUL. The first
line and the frontmatter's closing line are each exactly `---`.
Settings follow the [loop format's frontmatter subset](loop.v1.md#the-frontmatter-subset):
each line is a lowercase key followed by `: ` and one JSON value, with
no extra whitespace around the value. Keys can be in any order. A key
can appear only once in the frontmatter or within the same JSON object.

| Field | Required | Rule |
| --- | --- | --- |
| `id` | yes | A nonempty string of lowercase ASCII letters, digits and hyphens. The file name is exactly `<id>.md`, which makes ids unique within `outcomes/`. |
| `claim` | yes, in the body | One plain sentence on one line. After trimming surrounding whitespace, the line must contain at least one letter or number and end in `.`, `!` or `?`. Earlier occurrences of those marks cannot be followed by whitespace. A dot inside a name such as `example.test` is fine. |
| `proof` | yes | An object with `run` and `timeout`. `run` is a nonblank command on one line with no NUL, run from the project root. `timeout` is 1 to 600 seconds, written as a JSON integer with no fraction or exponent. |
| `allowed_paths` | yes | A non-empty array of literal paths relative to the repository root. Use `/` separators and end a folder with `/`. A path cannot have an empty, `.` or `..` segment, a drive prefix, a backslash or an ASCII control character. The paths can name files or folders a fix will create. |
| `cadence` | yes | An object with `cron` and `timezone`. Use the [loop format's five-field cron syntax](loop.v1.md#trigger), including its day-of-month and day-of-week matching rule. The minute field must expand to exactly one distinct minute from 0 to 59. Use `UTC` or an available IANA zone such as `America/Los_Angeles`. |
| `enabled` | yes | A JSON boolean. `false` leaves the outcome listed and skips its proof. |
| `secrets` | no | An array of distinct environment variable names, each matching `^[A-Z][A-Z0-9_]*$`. The default is `[]`. Use key names only. The string `"all"` and secret values are forbidden. |

Only the listed frontmatter fields and object keys are allowed. The
claim is read from the body instead of a frontmatter key. A decoded
outcome contains all seven fields, including the body as `claim` and
the default for omitted `secrets`.

For example, `0 * * * *` is hourly and `0,59 * * * *` is refused.
The limit also applies across timezone transitions. If matching local
times map to instants less than one elapsed hour apart, only the first
is due within that hour.

## Proof results

| Exit or condition | Result | Output |
| --- | --- | --- |
| `0` | holds | |
| `1` | broken | Standard output is the evidence. |
| `3` | unproved | Standard output says why. |
| Any other exit | unproved | The reason names the exit code. |
| Timeout | unproved | The reason says the proof timed out. |

Unproved never counts as holding.

## Refusals

A refusal has a stable **code**, a **field** and a **message**. A reader
can print it as `<file>: <field>: <message>`. Encoding and frontmatter
boundary refusals stop validation. After reading the settings, any
line, JSON or duplicate-key refusals stop validation before checking the
fields. Shape checks report unknown keys and missing required keys.
Each invalid value gets one refusal for its field. A proof or cadence
that is the wrong type has no child fields to validate.

| Code | Field | Message |
| --- | --- | --- |
| `encoding` | `file` | `must be UTF-8 with LF line ends, no byte order mark and no NUL` |
| `frontmatter-start` | `file` | `must start with a line of exactly ---` |
| `frontmatter-end` | `file` | `frontmatter has no closing line of exactly ---` |
| `line-syntax` | `line <n>` | `must be "key: value" with one JSON value` |
| `json` | `<key>` | `value is not one JSON value` |
| `duplicate-key` | `<key>` | `contains a repeated key` |
| `unknown-field` | `<field>` | `is not a setting of outcome v1` |
| `missing-field` | `<field>` | `is required` |
| `bad-id` | `id` | `must contain only lowercase ASCII letters, digits and hyphens` |
| `id-filename` | `id` | `must match the file name without .md` |
| `bad-claim` | `claim` | `must be one plain sentence on one line` |
| `bad-proof` | `proof` | `must be an object` |
| `bad-proof-run` | `proof.run` | `must be a nonblank command on one line, with no NUL` |
| `bad-timeout` | `proof.timeout` | `must be an integer from 1 to 600 seconds` |
| `bad-allowed-paths` | `allowed_paths` | `must be a non-empty array of repository-relative files or folders` |
| `bad-cadence` | `cadence` | `must be an object` |
| `bad-cron` | `cadence.cron` | `must be five cron fields: minute hour day-of-month month day-of-week` |
| `cadence-too-frequent` | `cadence.cron` | `must select only one minute of each hour` |
| `bad-timezone` | `cadence.timezone` | `must be UTC or an IANA zone such as Area/City` |
| `bad-enabled` | `enabled` | `must be true or false` |
| `bad-secrets` | `secrets` | `must be an array of key names, never all or a value` |
| `bad-secret` | `secrets` | `each item must be an environment variable name` |
| `duplicate-secret` | `secrets` | `must name each key only once` |

`<n>` is a 1-based file line. For a repeated key inside a JSON object,
`<key>` names the frontmatter key holding that value. Nested fields in
shape checks use dotted paths such as `proof.timeout`.

## Schema and fixtures

The schema checks the decoded settings and claim. A reader also checks
the source encoding, frontmatter syntax, duplicate keys, filename,
sentence, integer spelling, cron and timezone. This document defines
those rules.

[The expected results](fixtures/outcome/expected.json) name every
synthetic file in [the fixture folder](fixtures/outcome/). A valid
fixture has `result: "valid"` and the decoded outcome in `parsed`. A
refused fixture has `result: "refused"` and its `refusals`. The
manifest also supplies synthetic exit codes and standard output to
test proof-result classification. A null exit represents a timeout.
CI compares the results with the manifest and rejects missing or
unlisted fixtures.
