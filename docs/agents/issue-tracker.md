# Issue tracker: GitHub

WizLoops' versions, specs and tickets live in this GitHub repository, `openwizdev/WizLoops`. Use the `gh` CLI (2.94 or later, for sub-issues and "blocked by" links) for everything, with `-R openwizdev/WizLoops`.

## Where things live

| Thing | On GitHub |
| --- | --- |
| Version | A milestone, named after the version |
| Spec | An issue in that milestone; its body is the spec |
| Ticket | A sub-issue of its spec, with "blocked by" links to the tickets it waits for, including tickets in `openwizdev/OpenWiz` |
| A ticket's work | Its pull request here, against `main` |
| The user's approval of a spec or a plan graph | A public-form comment on the spec issue: the decision, date and private-comment pointer, naming the revision approved |

A ticket is ready when it has the `ready-for-agent` label and every ticket blocking it has a verified merge: a closed blocker alone is not enough. A ticket closes only on a verified merge (a person's ticket on its completion record), a spec only when all its tickets are closed.

**Blockers in another repository** show by bare number. A ticket's `## Links` line names the repository beside the reason; GitHub's native link points at the right issue.

## Repositories

- **Development tracker:** `openwizdev/WizLoops` (public).
- **Related code:** `openwizdev/OpenWiz` (public): the `openwiz loop` commands.
- **Private records:** `jparker2006/ClosedWiz` (private): grills, exact replies and orchestration state.

## Private records and approval forms

Nothing private goes in this repository: no thread ids, no exact words of a decision, no personal or machine details. Save and read back an exact confirmation or approval in a private ClosedWiz comment first; the public comment keeps the `Spec confirmed by`, `Plan graph approved by` or `Approved on its own by` opening, the date and the decision in plain words, with `Private record: <full ClosedWiz comment URL>` as its very next line.

## Commands

- **Create an issue:** `gh issue create -R openwizdev/WizLoops --title "..." --body-file body.md`.
- **Blocking:** GitHub's own "blocked by" links: `gh issue create -R openwizdev/WizLoops --blocked-by <n>,<n> ...`, or afterwards `gh issue edit <ticket> -R openwizdev/WizLoops --add-blocked-by <blocker>`.
- **List a ticket's blockers:** `gh issue view <n> -R openwizdev/WizLoops --json blockedBy --jq '.blockedBy.nodes[] | {number, state}'`. A closed blocker still needs its verified merge.
- **Read an issue:** `gh issue view <n> -R openwizdev/WizLoops --json number,title,body,labels,comments,blockedBy`.
- **Comment:** `gh issue comment <n> -R openwizdev/WizLoops --body-file comment.md`.
- **Labels:** `gh issue edit <n> -R openwizdev/WizLoops --add-label "..."` and `--remove-label "..."`.
- **Close:** post the reason with `gh issue comment`, then `gh issue close <n> -R openwizdev/WizLoops`.

## Pull requests as triage input

**Outside pull requests count as requests: no.**

## When a skill says

- **"Publish to the issue tracker":** create a GitHub issue here.
- **"Fetch the ticket":** read it as in **Read an issue** above.
