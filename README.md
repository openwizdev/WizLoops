<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/openwizdev/.github/main/profile/art/wiz.png">
  <img alt="The OpenWiz Wiz" src="https://raw.githubusercontent.com/openwizdev/.github/main/profile/art/wiz.png" width="56">
</picture>

# WizLoops

Part of [OpenWiz](https://openwiz.dev), the open source agent factory.

**Loops as files: what wakes an [OpenWiz](https://github.com/openwizdev/OpenWiz) factory, and when.** One Markdown file per loop, changed by pull request, so you can review, copy and diff them. OpenWiz reads the files and sets the loops up on your host.

**Status:** [OpenWiz 0.1.0](https://github.com/openwizdev/OpenWiz/releases/tag/v0.1.0) is released, and its `openwiz loop` commands read these files. The format and five starter loops are here, and CI checks them against that release. Cloudroom is the only host so far; more are coming.

## Quick start

From a project with a loop file, using OpenWiz 0.1.0:

```sh
openwiz loop validate my-loop.md                                      # names every problem by file and field
openwiz loop plan my-loop.md --project <project-id>                   # a dry run: shows exactly what would change
openwiz loop apply my-loop --project <project-id> --from my-loop.md   # creates or updates that loop, then reads it back
openwiz loop export --project <project-id>                            # writes one file per loop (checks need Linux in 0.1.0)
```

`plan`, `apply` and `export` need `--project` with the Cloudroom project ID (`project_id`, not its display name). `apply` takes the loop's id and `--from` with the same path passed to `plan` (without `--from`, it looks for `./<id>.md`). In OpenWiz 0.1.0, exporting a project with an exportable loop that has a check requires Linux: on macOS, `export` exits 1 before writing any files. Copy a loop from [the catalog](catalog/README.md) and read it as a recipe, or start from one of those commands.

## How it works

A **loop** is an alarm clock for an agent: a trigger wakes it, an optional check decides whether there is work, and an agent gets the prompt. Settings go in the frontmatter, the prompt in the body:

```markdown
---
id: "review-nudge"
name: "Review nudge"
trigger: {"cron": "0 9 * * 1-5", "timezone": "UTC"}
check: {"run": "review-nudge/check.sh", "timeout": 60}
thread: "same"
priority: 2
params: {"repo": "example-org/example-repo"}
---
The check printed the pull requests in {{repo}} still waiting for a review.
Ask for a review on each one, once.
```

- **`trigger`**: a cron with a timezone, a one-off `at` time, an `in` delay or a `webhook`.
- **`check`** runs first. If it prints nothing, no agent starts, so a quiet wake costs no tokens.
- **`thread`**: `"same"` prompts the same agent again; `"new"` starts a fresh one each run.
- **`params`** fill `{{name}}` in the prompt and reach the check as `$WIZLOOP_PARAM_<NAME>`.
- **`secrets`** default to none.

Every field, refusal and fixture: [`format/loop.v1.md`](format/loop.v1.md). How each field maps to Cloudroom: [`adapters/cloudroom.v1.md`](adapters/cloudroom.v1.md). What a host can't do exactly is refused and named, never faked. A host gets an adapter only if a loop can wake or message the agent running the factory.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/openwizdev/.github/main/profile/art/map-dark.png">
  <img alt="How the repos fit: WizSkills and WizLoops feed OpenWiz, the kernel. OpenWiz drives your agents and machines and writes records to GitHub. WizSite's app reads GitHub, and WizMarket's listings feed that site. WizPlugins holds plugins for the ADEs you use, starting with WizBar. Private records and tools sit apart." src="https://raw.githubusercontent.com/openwizdev/.github/main/profile/art/map-light.png" width="560">
</picture>

### The catalog

| id | What it does |
| --- | --- |
| [`fleet-check`](catalog/fleet-check.md) | Wakes a fleet's manager only when its spec has something due |
| [`hourly-status`](catalog/hourly-status.md) | Posts an hourly status line, only when something changed |
| [`morning-digest`](catalog/morning-digest.md) | Sends the owner a daily digest at a fixed local time |
| [`stall-sweep`](catalog/stall-sweep.md) | Finds work waiting with no progress, and says why |
| [`workflow-kick`](catalog/workflow-kick.md) | Starts a CI workflow on time from its check alone; no agent ever starts |

### Not supported yet

- **Other hosts:** none yet for Claude Code, Codex or Cursor, and no local timer.
- **Cloudroom adapter v1:** no deleting loops; no changing a loop's thread kind, or to or from a webhook; no removing a check or an agent from a loop.
- **Format v1:** no budgets, no shadow mode, no in-file approval (the pull request approves it), no escape for a literal `{{`.

## Links

- [OpenWiz](https://github.com/openwizdev/OpenWiz) · [WizSkills](https://github.com/openwizdev/WizSkills) · [openwiz.dev](https://openwiz.dev) · [all repos](https://github.com/openwizdev)
- [Apache License 2.0](LICENSE)
