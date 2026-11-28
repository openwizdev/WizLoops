# Fleet settings

Every fleet in this repository starts from these settings. The fleet skills read this file instead of naming any project's agents, commands or rules. Each value names its source; when a source changes, run the `setup` skill again (or edit the line by hand) so the two agree. Keep the machine-read table headings, columns and agent rows unchanged.

Before your first commit in this repository, set Git's `user.email` to your GitHub `users.noreply.github.com` address; verify that both author and committer emails use that domain for every outgoing commit.

## Builder

One per ticket. It builds its ticket on its own branch, and never reviews or merges.

| Setting | Value | `room-cli thread spawn` flag |
| --- | --- | --- |
| Harness | Claude Code | `--provider claude-code` |
| Model | Opus 5.5 | `--model claude-opus-5-5` |
| Effort | Medium | `--reasoning-level medium` |

Source: Jake, 2026-11-14 (FR3): builders default to Opus at Medium effort ([private record](https://github.com/jparker2006/ClosedWiz/issues/325#issuecomment-6888295193)); Jake, 2026-11-05: Claude Code Opus builders, with the other family reviewing ([private record](https://github.com/jparker2006/ClosedWiz/issues/1275#issuecomment-6704671951)).

## Builder for small tickets

Tickets with an exact `polish`, `huntr` or `proposal` label use this table; every other ticket uses `## Builder`.

| Setting | Value | `room-cli thread spawn` flag |
| --- | --- | --- |
| Harness | Claude Code | `--provider claude-code` |
| Model | Opus 5.5 | `--model claude-opus-5-5` |
| Effort | Medium | `--reasoning-level medium` |

Source: the same as `## Builder`.

## Reviewer for Claude-built

One per pull request, in a fresh thread that never built or helped build it. It reviews the exact head and never edits.

| Setting | Value | `room-cli thread spawn` flag |
| --- | --- | --- |
| Harness | Codex | `--provider codex` |
| Model | Sol 6.1 | `--model gpt-6.1-sol` |
| Effort | High | `--reasoning-level high` |

## Reviewer for GPT-built

| Setting | Value | `room-cli thread spawn` flag |
| --- | --- | --- |
| Harness | Claude Code | `--provider claude-code` |
| Model | Opus 5.5 | `--model claude-opus-5-5` |
| Effort | High | `--reasoning-level high` |

## Reviewer

One per pull request, from a different model family than the builder, read from the builder's actual provider. It reviews the exact head and never edits. If it can't be started, the review waits: it is never swapped for another model. Codex runs at the default service tier, never fast mode.

Source: Jake, 2026-10-30 and 2026-11-01: the other family reviews, at High effort, and the selected reviewer is never silently swapped ([private record](https://github.com/jparker2006/ClosedWiz/issues/1275#issuecomment-6704671951)).

## Builder helpers

Cheap helpers a builder starts for searches and chores; the builder keeps every judgment and writes every line. How to start, brief, check and archive one is in [helpers.md](helpers.md).

| Setting | Value | `room-cli thread spawn` flag |
| --- | --- | --- |
| Harness | Claude Code | `--provider claude-code` |
| Model | Haiku 5.5 | `--model claude-haiku-5-5` |
| Effort | High | `--reasoning-level high` |

## Reviewer helpers

Helpers a reviewer starts to check one part each; the reviewer keeps every judgment and posts the one report. Reviewers of GPT-built pull requests use Claude Code, Haiku 5.5, High instead.

| Setting | Value | `room-cli thread spawn` flag |
| --- | --- | --- |
| Harness | Codex | `--provider codex` |
| Model | Sol 6.1 | `--model gpt-6.1-sol` |
| Effort | High | `--reasoning-level high` |

Source for both helper tables: Jake, 2026-11-05 and 2026-11-06, as in OpenWiz's fleet settings ([private record](https://github.com/jparker2006/ClosedWiz/issues/1275#issuecomment-6704671951)).

## Swarm size

| Ticket | Builder helpers | Reviewer helpers |
| --- | --- | --- |
| Small | about 1–3 | about 1–3 |
| Medium | about 3–8 | about 3–8 |
| Large | about 8–15 | about 8–15 |

A starting point, never a cap. Source: Jake, 2026-10-31 ([private record](https://github.com/jparker2006/ClosedWiz/issues/1275#issuecomment-6704671951)).

## Loop

| Setting | Value |
| --- | --- |
| GitHub's messages | Off: no webhook on this repository yet. Adding one needs Jake's yes |
| The safety net | None yet; the spec's fleet thread covers its spec |
| A spec's fleet thread | One per approved spec (ADR 0011 in OpenWiz), started by the orchestrator as its own child. Its own loop wakes that same thread: `launch-fleet #<spec> openwizdev/WizLoops`, `--same-thread`, its spec's check every 10 minutes |

## Labels

The triage labels and their names here are in `triage-labels.md`. A fleet adds one label of its own:

| Label | Means | Put on by | Taken off by |
| --- | --- | --- | --- |
| `held` | The ticket is held: it waits for the user's approval of a changed plan or contract, and never starts while it has this label. It has no ready label while held | `plan-graph`, before it changes an approved plan; `launch-fleet`, when a merge changes a contract the ticket relies on | `plan-graph`, as it puts the ready label back once the new approval is recorded; `launch-fleet`'s `release` line, if it is still on after that |

## Test commands

| # | Folder | Command | CI check |
| --- | --- | --- | --- |
| 1 | repository root | `sh ci/check.sh` | `checks` |

`ci/check.sh` refuses private identifiers, then runs `openwiz loop validate` on the catalog and every fixture (`ci/validate.py`, against `format/fixtures/expected.json`), checks that the validator refuses broken copies (`ci/test-validate.sh`), and checks that the comment check and its workflow step fail a disallowed comment (`ci/test-comment-check.sh`). Locally it needs `openwiz` on `PATH`, built from the OpenWiz commit `.github/workflows/checks.yml` pins (`OPENWIZ_REV`). A builder runs the red/green proof and the commands its change can affect, then opens the ready pull request.

## CI checks

| Check | Runs | Required on |
| --- | --- | --- |
| `checks` | Workflow `checks`, job `checks`: on a pull request, first the comment check (`sh ci/comment-check.sh HEAD^1`: the [comments contract](../../contracts/comments.v1.md)'s diff mode on the lines it adds, with `format/fixtures/` excluded because the loop format's fixtures are test data) and the carried comment-check drift check (`python3 -I tools/comment-check/drift.py`, verifying `tools/comment-check/check.py` matches its pinned OpenWiz source commit); then installs `openwiz` from the pinned OpenWiz commit, then `sh ci/check.sh`: no private identifiers, every catalog file valid, every fixture's result exactly as `expected.json` says, and the comment check failing a disallowed comment | `main`, by the repository ruleset `main: checks required` (WL7) |

The workflow runs for every pull request against `main` and every push to `main`, with read-only permissions, no secrets and no persisted checkout credentials. The OpenWiz commit is a full commit id on OpenWiz `main`, never a branch; moving it is a pull request that changes `OPENWIZ_REV`.

## GitHub identity

The OpenWiz App is not installed on this repository yet, so the fleet acts as the account it falls back to. Commits are authored and committed with a GitHub noreply address.

| Setting | Value |
| --- | --- |
| App | OpenWiz, when Jake installs it here; until then, the fallback account |
| Record authors | `openwiz[bot]`, `jparker2006` |

## Standing merge rules

| Pull request | Review | Merged by, and when |
| --- | --- | --- |
| A ticket in an approved plan graph, while no CI check is required on `main` | The reviewer above, on its exact head | The loop, as soon as the reviewer's APPROVE names that exact commit, the `checks` run on that commit is green, and the pull request has no conflict with `main`. Then the merge is read back. This row ends when WL7 makes a CI check required on `main`; the next row applies from then on |
| A ticket in an approved plan graph, once a ruleset requires CI checks on `main` | The reviewer above, on its exact head | The loop, as soon as the reviewer's APPROVE names that exact commit and every required CI check is green on it, it has no conflict with `main`, and `main` has moved since that CI run only by merges that were themselves green. Then the merge is read back |
| Any other pull request | None for docs-only changes by the orchestrator; otherwise the reviewer above | The orchestrator for docs-only changes, once CI is green; otherwise Jake only |
| Anything to a release, and every release or publication | None by rule | Jake only |

- **How a merge is done:** `gh pr merge <N> -R openwizdev/WizLoops --merge --match-head-commit <approved head>`, then read back: only `merged`, at the approved head, is a verified merge.
- **A pull request is never retargeted,** and nothing is ever force-pushed.

Source: Jake, 2026-11-15 (J87-P, Q4): reviewed merges until WL7 adds a required check, as WizPlugins did ([private record](https://github.com/jparker2006/ClosedWiz/issues/325#issuecomment-6902640937)); Jake, 2026-10-30: plans authorize ticket merges after exact-head review, and the loop performs the merge (OpenWiz ADR 0008; [private record](https://github.com/jparker2006/ClosedWiz/issues/1275#issuecomment-6704671951)).
