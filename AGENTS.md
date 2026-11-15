# WizLoops

WizLoops holds the loop file format, the Cloudroom adapter rules and a catalog of starter loops. The code that reads and applies loop files is the OpenWiz CLI (`openwiz loop ...`), in `openwizdev/OpenWiz`.

- **Settings for agents** are in `docs/agents/`: the issue tracker, the triage labels, where words and decisions live, and the fleet settings (builders, reviewers, CI checks, merge rules). Read them; never guess them.
- **Skills** come from OpenWiz's skills (WizSkills): `plan-graph`, `launch-fleet`, `build-ticket`, `review-ticket`.
- **Commits:** author and committer email must be your GitHub `users.noreply.github.com` address.
- **Public repository:** nothing private goes here: no thread ids, no exact words of a decision, no personal or machine details. Examples use made-up names.
- **The test rule (openwizdev/OpenWiz#687):** every test protects a supported behaviour, a contract others rely on or a safety invariant, and names the bug it catches; otherwise the pull request says why no test is needed.
