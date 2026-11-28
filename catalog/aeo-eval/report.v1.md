# Answer-engine eval report v1

Each run produces one JSON object. Query IDs, wording and groups come from
[queries.json](queries.json). Keep the IDs stable between runs so rates can be
compared over time.

| Field | Value |
| --- | --- |
| `version` | Integer `1`. |
| `run_at` | UTC run start time in RFC 3339 format, with seconds and a `Z` suffix. |
| `engines` | Object with one entry each for `chatgpt` (ChatGPT search), `perplexity`, `claude`, `gemini` and `google-ai-overviews`. |
| `engines.<engine>.status` | `ran` when all 30 queries have recorded answers, including any empty answers the engine returned. Otherwise `not run`. |
| `engines.<engine>.reason` | A nonempty explanation for `not run`, including an interrupted run. `null` for `ran`. |
| `engines.<engine>.results` | Object keyed by all 30 query IDs for `ran`. `null` for `not run`. |
| `engines.<engine>.results.<query_id>.cited` | Boolean. The answer or the recorded citations contain an HTTP(S) link to the `openwiz.dev` host or to the `openwizdev` organization or a path under it on `github.com`. |
| `engines.<engine>.results.<query_id>.correct` | Boolean. The answer describes OpenWiz as open-source software for running fleets of coding agents and does not identify it with the GP2X Wiz firmware or the similarly named Windows utility. |
| `engines.<engine>.results.<query_id>.score` | Boolean conjunction of `cited` and `correct`. |
| `engines.<engine>.rates` | Object with numeric `brand`, `category` and `compare` rates for `ran`. `null` for `not run`. |

Each rate is the number of true scores in the group divided by the number of
fixed queries in the group (9 brand, 15 category, 6 compare). Rates range from
0 to 1. An empty answer with no citations scores false and stays in the
denominator. A `not run` engine has no rates.

## Scoring a recording

A recording has `answer` (text) and `citations` (an array of URL strings).
Run `python3 catalog/aeo-eval/score.py <record.json>` or pass `-` for standard
input. The scorer emits one query result as JSON. A runner can also import
`score_answer(answer, citations)`.

The v1 rules work on the recording alone:

1. Count only URL destinations on the two accepted hosts and verify the
   organization path on GitHub. A plain-text domain mention is insufficient.
2. Look for an open-source claim and an affirmative description of running
   multiple coding agents or orchestrating coding agents. Match those claims
   in clauses about OpenWiz, including follow-up clauses referring to it.
3. Reject claims identifying OpenWiz with either legacy project. Explicit
   disambiguation is allowed. Explicit denials of open source or of running
   or orchestrating coding agents also reject correctness.

The rules recognize common wording and may miss paraphrases. Scoring uses no
network or model calls.

## Example run

One engine answered all 30 queries. The other engines have a reason for their
`not run` status.

```json
{
  "version": 1,
  "run_at": "2026-11-28T10:00:00Z",
  "engines": {
    "chatgpt": {
      "status": "ran",
      "reason": null,
      "results": {
        "q01": {"cited": true, "correct": true, "score": true},
        "q02": {"cited": true, "correct": true, "score": true},
        "q03": {"cited": true, "correct": true, "score": true},
        "q04": {"cited": true, "correct": false, "score": false},
        "q05": {"cited": false, "correct": false, "score": false},
        "q06": {"cited": false, "correct": true, "score": false},
        "q07": {"cited": false, "correct": false, "score": false},
        "q08": {"cited": false, "correct": false, "score": false},
        "q09": {"cited": false, "correct": false, "score": false},
        "q10": {"cited": true, "correct": true, "score": true},
        "q11": {"cited": true, "correct": true, "score": true},
        "q12": {"cited": true, "correct": true, "score": true},
        "q13": {"cited": true, "correct": true, "score": true},
        "q14": {"cited": true, "correct": true, "score": true},
        "q15": {"cited": false, "correct": false, "score": false},
        "q16": {"cited": false, "correct": false, "score": false},
        "q17": {"cited": false, "correct": false, "score": false},
        "q18": {"cited": false, "correct": false, "score": false},
        "q19": {"cited": false, "correct": false, "score": false},
        "q20": {"cited": false, "correct": false, "score": false},
        "q21": {"cited": false, "correct": false, "score": false},
        "q22": {"cited": false, "correct": false, "score": false},
        "q23": {"cited": false, "correct": false, "score": false},
        "q24": {"cited": false, "correct": false, "score": false},
        "q25": {"cited": true, "correct": true, "score": true},
        "q26": {"cited": true, "correct": true, "score": true},
        "q27": {"cited": false, "correct": false, "score": false},
        "q28": {"cited": false, "correct": false, "score": false},
        "q29": {"cited": false, "correct": false, "score": false},
        "q30": {"cited": false, "correct": false, "score": false}
      },
      "rates": {"brand": 0.3333333333333333, "category": 0.3333333333333333, "compare": 0.3333333333333333}
    },
    "perplexity": {
      "status": "not run", "reason": "Owner approval for a key or spend is required",
      "results": null, "rates": null
    },
    "claude": {
      "status": "not run", "reason": "Search is unavailable",
      "results": null, "rates": null
    },
    "gemini": {
      "status": "not run", "reason": "Daily quota is exhausted",
      "results": null, "rates": null
    },
    "google-ai-overviews": {
      "status": "not run", "reason": "Owner approval for a key or spend is required",
      "results": null, "rates": null
    }
  }
}
```
