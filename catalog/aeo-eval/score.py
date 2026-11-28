"""Score one recorded answer using the version 1 rules."""

import argparse
import json
import re
import sys
from urllib.parse import urlsplit


URL = re.compile(r"""\bhttps?://[^\s<>"'\[\]()`]+""", re.IGNORECASE)
CLAUSE = re.compile(r"[.!?;]+\s*|\n+|\b(?:but|whereas|while)\b")
OPENWIZ = re.compile(r"\bopenwiz\b")
PROJECT_REFERENCE = re.compile(r"^\s*(?:it|its|this tool|the (?:tool|project|software|platform))\b")
OPEN_SOURCE = re.compile(r"\bopen[- ]source\b")
SOURCE_DENIAL = re.compile(r"\b(?:closed[- ]source|not (?:an? )?open[- ]source)\b")
LEGACY_PROJECT = r"(?:gp2x(?: wiz)?(?: (?:handheld|firmware))?|windows utilit(?:y|ies))"
LEGACY = re.compile(rf"\b{LEGACY_PROJECT}\b")
LEGACY_DISTINCTION = re.compile(
    r"\b(?:not (?:to be confused with )?|unlike |unrelated to |different from |distinct from |"
    r"separate from )"
    rf"(?:the |a )?{LEGACY_PROJECT}\b(?: (?:or|and) (?:the |a )?{LEGACY_PROJECT}\b)?"
)
CODING_AGENT = r"(?:(?:ai )?coding|software (?:development|engineering)|programming)[ -]agent"
FLEET = r"(?:fleets?|teams?|groups?|multiple|many|several|parallel|concurrent(?:ly)?)"
RUN = r"(?:run(?:s|ning)?|(?:launch|deploy|spawn)(?:es|s|ing)?|operat(?:e|es|ing))"
ORCHESTRATE = r"(?:orchestrat|coordinat|manag)(?:e|es|ing)"
CAPABILITY = re.compile(
    rf"\b(?:{CODING_AGENT} orchestrator|orchestrat(?:or|ion) (?:of|for) {CODING_AGENT}s)\b"
    rf"|\b{ORCHESTRATE}\b[^.;]*\b{CODING_AGENT}s\b"
    rf"|\b{RUN}\b(?=[^.;]*\b{FLEET}\b)[^.;]*\b{CODING_AGENT}s\b"
)
CAPABILITY_DENIAL = re.compile(
    rf"\b(?:not|never|cannot|can't|unable to)\b[^,.;]*\b(?:{RUN}|{ORCHESTRATE})\b"
)


def _is_openwiz_url(url):
    try:
        target = urlsplit(url.rstrip(".,;:!?"))
        if target.username is not None:
            return False
        if target.hostname == "openwiz.dev":
            return True
        first_segment = target.path.lower().split("/")[1:2]
        return target.hostname == "github.com" and first_segment == ["openwizdev"]
    except ValueError:
        return False


def _describes_openwiz(answer):
    text = URL.sub("", answer).lower().replace("’", "'").replace("*", "").replace("`", "")
    about_openwiz = False
    open_source = False
    runs_fleets = False
    for clause in CLAUSE.split(text):
        if OPENWIZ.search(clause):
            about_openwiz = True
        elif not (about_openwiz and PROJECT_REFERENCE.match(clause)):
            about_openwiz = False
        if not about_openwiz:
            continue

        clause = LEGACY_DISTINCTION.sub("", clause)
        if LEGACY.search(clause):
            return False
        if SOURCE_DENIAL.search(clause) or CAPABILITY_DENIAL.search(clause):
            return False
        open_source |= bool(OPEN_SOURCE.search(clause))
        runs_fleets |= bool(CAPABILITY.search(clause))
    return open_source and runs_fleets


def score_answer(answer, citations=()):
    """Return the cited, correct and score booleans for answer text and citation URLs."""
    cited = any(
        _is_openwiz_url(match.group())
        for text in (answer, *citations)
        for match in URL.finditer(text)
    )
    correct = _describes_openwiz(answer)
    return {"cited": cited, "correct": correct, "score": cited and correct}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("record", help="path to a JSON answer record, or - for standard input")
    args = parser.parse_args()
    try:
        if args.record == "-":
            record = json.load(sys.stdin)
        else:
            with open(args.record, encoding="utf-8") as source:
                record = json.load(source)
        answer = record["answer"]
        citations = record["citations"]
        if not isinstance(answer, str) or not isinstance(citations, list) or not all(
            isinstance(url, str) for url in citations
        ):
            parser.error("expected answer text and a list of citation URLs")
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.error(f"cannot read answer record: {error}")
    print(json.dumps(score_answer(answer, citations)))


if __name__ == "__main__":
    main()
