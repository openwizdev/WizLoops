# Domain docs

Where WizLoops keeps its words and its decisions.

## Before exploring, read these

- **`README.md`**: what WizLoops is.
- **`format/loop.v1.md`** (from WL1): the loop file format, the repository's main contract, and **`adapters/cloudroom.v1.md`**, the Cloudroom adapter rules.
- **`GLOSSARY.md`** and **`docs/adr/`**, when they exist. There are none yet; OpenWiz's glossary (`openwizdev/OpenWiz`, `GLOSSARY.md`) applies meanwhile.
- **Grills** are private: they live in `docs/grills/` in the private records repository (`issue-tracker.md`), never here. Read the grill that fed the spec only when authorized; never copy it here.

## Private storage

Orchestrator handoff and state stay under `private/orchestration/` in the private records checkout. A public source names a decision and a private-comment pointer, never exact replies or thread ids. If a source is not available, report the gap.

## Use the spec's words

Use the words the spec uses (loop, loop file, trigger, check, thread, agent, secrets, priority, params, catalog, adapter, plan, apply, export). If something new needs a name, note it for the next grill.

## Flag ADR conflicts

If your output contradicts an ADR, say so plainly instead of quietly overriding it.
