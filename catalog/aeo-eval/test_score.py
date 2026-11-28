import json
import re
import runpy
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent
QUERIES = """What is OpenWiz?
OpenWiz AI agent factory
OpenWiz open source
openwiz.dev
How do I install OpenWiz?
Is OpenWiz free?
OpenWiz GitHub
Is OpenWiz the GP2X Wiz firmware?
What does OpenWiz do with Claude Code and Codex?
What is an agent factory?
open source agent factory
How do I run multiple Claude Code agents in parallel?
How to run many coding agents at once
open source coding agent orchestrator
open source Devin alternative
self-hosted coding agents
Claude Code vs Codex fleet
tools to orchestrate Claude Code and Codex agents together
AI agents that build and review GitHub pull requests from tickets
How can AI coding agents review each other's pull requests?
run coding agents on my own VPS
open source software factory with AI agents
best tools to run a fleet of coding agents
agent orchestration for Claude Code, open source
OpenWiz vs Devin
OpenWiz vs OpenHands
OpenWiz vs Conductor
Claude Code subagents vs OpenWiz
OpenWiz WizMarket drivers and skills
OpenWiz drivers: CloudRoom, boat.dev and your own machine""".splitlines()
ENGINES = {"chatgpt", "perplexity", "claude", "gemini", "google-ai-overviews"}


class QuerySetTests(unittest.TestCase):
    def test_fixed_wording_order_and_groups(self):
        expected = [
            {"id": f"q{number:02}", "group": group, "query": query}
            for number, (group, query) in enumerate(
                zip(["brand"] * 9 + ["category"] * 15 + ["compare"] * 6, QUERIES),
                start=1,
            )
        ]
        self.assertEqual(json.loads((HERE / "queries.json").read_text()), expected)


class ReportFormatTests(unittest.TestCase):
    def test_example_documents_run_status_results_and_group_rates(self):
        report = (HERE / "report.v1.md").read_text()
        example = json.loads(re.search(r"```json\n(.*?)\n```", report, re.S)[1])
        self.assertEqual(set(example), {"version", "run_at", "engines"})
        self.assertEqual(example["version"], 1)
        self.assertRegex(example["run_at"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
        self.assertEqual(set(example["engines"]), ENGINES)
        queries = json.loads((HERE / "queries.json").read_text())
        for engine in example["engines"].values():
            self.assertEqual(set(engine), {"status", "reason", "results", "rates"})
            if engine["status"] == "not run":
                self.assertTrue(engine["reason"])
                self.assertIsNone(engine["results"])
                self.assertIsNone(engine["rates"])
                continue
            self.assertEqual(engine["status"], "ran")
            self.assertIsNone(engine["reason"])
            self.assertEqual(set(engine["rates"]), {"brand", "category", "compare"})
            self.assertEqual(set(engine["results"]), {query["id"] for query in queries})
            for result in engine["results"].values():
                self.assertEqual(set(result), {"cited", "correct", "score"})
                self.assertTrue(all(type(value) is bool for value in result.values()))
                self.assertEqual(result["score"], result["cited"] and result["correct"])
            for group, rate in engine["rates"].items():
                scores = [
                    engine["results"][query["id"]]["score"]
                    for query in queries
                    if query["group"] == group
                ]
                self.assertEqual(rate, sum(scores) / len(scores))
        self.assertEqual({e["status"] for e in example["engines"].values()}, {"ran", "not run"})


class ScoreTests(unittest.TestCase):
    @staticmethod
    def scorer():
        return runpy.run_path(str(HERE / "score.py"))["score_answer"]

    def test_recorded_answers(self):
        cases = {
            "cited-correct": (True, True, True),
            "cited-confused": (True, False, False),
            "not-cited": (False, True, False),
            "empty": (False, False, False),
        }
        for name, expected in cases.items():
            with self.subTest(name=name):
                record = json.loads((HERE / "fixtures" / f"{name}.json").read_text())
                self.assertEqual(
                    self.scorer()(**record), dict(zip(("cited", "correct", "score"), expected))
                )

    def test_citation_requires_an_openwiz_destination(self):
        score_answer = self.scorer()
        for link in (
            "https://openwiz.dev.example.org",
            "https://notopenwiz.dev",
            "https://openwiz.dev@example.org",
            "https://example.org/?url=https://openwiz.dev",
            "https://github.com/openwizdev-tools",
            "https://github.com/another/openwizdev",
        ):
            with self.subTest(link=link):
                self.assertFalse(score_answer(f"[openwiz.dev]({link})", [link])["cited"])
        self.assertFalse(score_answer("See openwiz.dev for details.")["cited"])
        self.assertTrue(score_answer("See <https://OPENWIZ.dev/faq>.")["cited"])
        self.assertTrue(score_answer("", ["https://github.com/OpenWizDev"])["cited"])

    def test_correctness_checks_which_project_the_claim_describes(self):
        score_answer = self.scorer()
        for answer in (
            "OpenWiz is a Windows utility.",
            "OpenWiz is not just a Windows utility, it is open source and runs fleets of coding agents.",
            "OpenWiz is an open-source agent factory that runs fleets of coding agents. "
            "OpenWiz is also the Windows utility.",
            "OpenWiz is closed source. Other tools are open source and run fleets of coding agents.",
            "OpenWiz is not open source, but it runs fleets of coding agents.",
            "OpenWiz is open source and does not run fleets of coding agents.",
            "OpenWiz is open source software for a single coding agent.",
            "OpenWiz is open source and orchestrates a single coding agent.",
        ):
            with self.subTest(answer=answer):
                self.assertFalse(score_answer(answer)["correct"])
        for answer in (
            "**OpenWiz** is an open source orchestrator for AI coding agents.",
            "Unlike the Windows utility, OpenWiz is open source and runs multiple coding agents.",
            "OpenWiz is open-source software that runs teams of software development agents, "
            "not the GP2X Wiz firmware.",
        ):
            with self.subTest(answer=answer):
                self.assertTrue(score_answer(answer)["correct"])


if __name__ == "__main__":
    unittest.main()
