# WizLoops

Loop file format (`format/`), Cloudroom adapter (`adapters/`), starter loops (`catalog/`). The code that reads them is `openwiz loop ...` in `openwizdev/OpenWiz`.

- Fleet settings (tracker, labels, reviewers, merge rules): `docs/agents/`. Read them; never guess.
- Every change is a branch and pull request to `main`. Never force-push or rewrite history.
- Commits: author and committer email are your GitHub `users.noreply.github.com` address.
- Public repository: no thread ids, exact decision words, or personal or machine details; examples use made-up names.
- Run `sh ci/check.sh` (needs `openwiz` built at `OPENWIZ_REV` in `.github/workflows/checks.yml`).
- Tests (openwizdev/OpenWiz#687): each protects a supported behaviour, a contract or a safety invariant and names the bug it catches; otherwise the pull request says why no test is needed.
