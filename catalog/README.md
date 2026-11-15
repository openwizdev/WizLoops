# The catalog

Starter loops, each taken from a loop that already runs a real software
factory and generalized so anyone can use it. Every catalog loop is a loop
file in the [format](../format/loop.v1.md).

| id | What it does |
| --- | --- |
| `fleet-check` | Wakes a fleet's manager only when its spec has something due |
| `hourly-status` | Posts an hourly status line, only when something changed |
| `morning-digest` | Sends the owner a daily digest at a fixed local time |
| `stall-sweep` | Finds work waiting with no progress, and says why |
| `workflow-kick` | Starts a CI workflow on time from its check alone; no agent ever starts |

## Layout

Each loop is `catalog/<id>.md`, and its check script and any other files
are in `catalog/<id>/`. Its `check.run` is `<id>/check.sh` (or another file
in that folder).

## The parameter rule

- **Everything that names a place is a param.** Every repository, spec or
  issue number, person, project, thread and address that a loop's prompt or
  check uses is a `params` entry, used as `{{name}}`. Nothing private is
  written into a catalog file.
- **Defaults are synthetic.** Each param's value in the file is a made-up
  example (`example-org/example-repo`, `1`), never a real one; the person
  applying the loop sets their own.
- **The schedule is the trigger's.** Placeholders work only in the prompt
  and the check, so a loop's time and timezone stay in its `trigger`; the
  file's values are an example to change.
- **Param names are shared.** Catalog loops use the same name for the same
  thing: `repo` (`owner/name`), `spec` (an issue number) and `owner` (who a
  message is for).
- **Secrets are none by default.** A catalog loop has `secrets: []` unless
  it truly needs one. Each secret it needs is named, and its prompt says
  why.
- **Quiet wakes cost nothing.** Every catalog loop has a check that prints
  nothing when nothing is due, so no agent starts. A loop whose check does
  all the work and always prints nothing (`workflow-kick`) never starts an
  agent at all.
- **Agent-workspace neutral.** A catalog file says nothing specific to one
  agent workspace; what each workspace can run is its adapter's call.
