# Set up docs-truth

Apply [the loop](../docs-truth.md) on a runner that has Python 3 and a GitHub CLI login with read access to the sources and issue write access to the docs repositories. The check uses that login. Set one loop per set of docs sources so its runs take turns. The default configuration is a synthetic example.

Set the `sources` param to a one-line JSON object. `docs` maps each source repository to Markdown files and directory prefixes ending in `/`. `help` maps each documented program to a repository and the path of its machine-readable help catalogue. A help repository can also provide docs. List the docs files from the site source selection you want to check. For example, one source and the OpenWiz help catalogue can be configured as follows.

```json
{"docs":{"openwizdev/WizLoops":["README.md","format/loop.v1.md"]},"help":{"openwiz":["openwizdev/OpenWiz","crates/cli/src/agent-catalogue.json"]}}
```

Each read uses a snapshot of `main` pinned to its commit for that run. Command claims use inline code, such as `example-cli show <id>`. Help catalogues supply `commands` entries with `argv` and optional `aliases` and `arguments`, as emitted by `openwiz help --agent`. The check compares command names and subcommands. Fenced examples belong to the separate docs command check. Use relative Markdown links, inline paths under a tracked directory, or a phrase like “the path `file.md`” to name repo paths clearly. Named contracts use inline versioned names such as `example.v1` next to the word “contract”, or links and paths to contract files.

A drift issue names the claim and its source line at the checked commit. Repeat runs reuse the issue's title key, including closed issues. When a complete check finds an open issue's claim resolved or removed, it comments with the checked commit and closes the issue. Removing a docs selector or a help source leaves issues outside the new coverage alone. On a failed read, the run refuses before writing any issues. The check prints no standard output.

Run the synthetic proof with `python3 -I catalog/docs-truth/test.py`. It uses a fake GitHub CLI and makes no network calls.
