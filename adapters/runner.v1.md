# The runner contract v1

What every runner does. A **runner** is the rules for running loop files
([`format/loop.v1.md`](../format/loop.v1.md)) on one kind of scheduler;
WizLoops calls them adapters, and keeps each one's rules in
`adapters/<runner>.v1.md`. WizLoops holds no code: OpenWiz's `openwiz loop`
commands and WizSkills' skills follow these rules.

| Runner | Rules | Refusal codes |
| --- | --- | --- |
| Cloudroom loops | [`cloudroom.v1.md`](cloudroom.v1.md) | `cf-` |
| T3 scheduled tasks | [`t3.v1.md`](t3.v1.md) | `t3-` |

[`cloudroom.v1.md`](cloudroom.v1.md) is the first runner under this
contract, unchanged: it already does everything below, and nothing in this
contract changes how it behaves.

No runner is a default. The user picks the runner; a tool that runs loops
never picks one for them.

## What every runner does

1. **Plans.** Plan reads loop files and the scheduler's objects, and shows
   exactly what apply would change: each create and update with the exact
   values it would send, each refusal, each unmanaged object, and each
   difference between what the file says and what the scheduler will do
   (such as an interval that counts from when it was saved). Plan changes
   nothing.
2. **Applies, then reads back.** Apply makes only the changes plan showed,
   then reads the scheduler's objects again and plans again against them.
   Anything but "no difference" is a failed apply, reported as such and
   never retried silently. When a call's outcome is unknown, apply reads
   before it writes again, and finds the object by its marker rather than
   make a second one.
3. **Exports.** Export reads the scheduler's objects and writes one loop
   file per object it can write exactly. What it can't write as a valid
   loop file, it refuses and names.
4. **Never changes a loop silently.** When a file asks for something the
   scheduler can't do exactly, the runner refuses that file and names the
   field. It never rounds a schedule, drops a setting or widens a grant to
   make a file fit.
5. **Names every refusal.** A refusal has a stable code that starts with
   the runner's prefix, a field (the loop file's dotted path, as the
   format's refusals have; or, for export, the scheduler's field) and an
   exact message, and is printed as the format's are:
   `<file>: <field>: <message>`. Each runner's rules have the table of its
   codes, fields and messages.
6. **Marks what it manages.** Every object a runner makes carries the
   loop's **marker** at the end of its name:

   ```text
   <name> [wizloop:<id>]
   ```

   The name is the file's `name`, one space, and `[wizloop:<id>]`. Read
   back, a name ending with one space and `[wizloop:<id>]`, where `<id>` is
   a valid loop id, is that loop's object; the part before the space is
   its `name`. Two objects in one scope with the same marker are refused;
   the runner changes neither. A runner whose objects have no name says in
   its rules where the marker goes instead.
7. **Never changes an unmanaged object.** An object without a marker is
   unmanaged: plan lists it, and plan and apply never change it, unless a
   runner's rules let the caller adopt it explicitly, for one apply. An
   adoption is never inferred from a name.
8. **Handles secrets by name only.** A loop file names secrets, never holds
   one, and a runner never reads, copies, writes or prints a secret's
   value. A runner refuses a loop whose `secrets` it can't grant exactly as
   written; its rules say which values it can.
9. **Keeps state in files.** What a runner keeps between runs lives in
   files: its own folder in the project, or for a home, `.openwiz/home/`.
   Never in a hosted service of ours.
10. **Says what a run costs and what its words mean.** A runner's rules
    say whether a quiet run (a check that printed nothing) starts an agent
    or a session, and what each run status the scheduler reports means:
    a status that only says a run was dispatched is never read as the run
    having done its work.

## What a runner's rules have

- The inputs plan reads, and the scheduler's commands or tools, with their
  exact fields.
- Where the marker goes, and what scope one id is unique in.
- How each field of a loop file maps to the scheduler, and back.
- What apply sends, what it reads back, and what export writes.
- The refusals table.
- Fixtures under `adapters/fixtures/<runner>/`: one case per mapping and
  per refusal, each a loop file and its exact result, and a row in
  `ci/validate.py` so CI checks every case against the rules. Cloudroom's
  fixtures are the format's own, in the table at the end of its rules.
