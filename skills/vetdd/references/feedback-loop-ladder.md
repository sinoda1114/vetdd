# Feedback loop ladder

How to build an oracle when the obvious one is not available. Try the rungs in order; stop at the first that yields a loop that is red-capable, deterministic, fast, and agent-runnable. Source: mattpocock `diagnosing-bugs` Phase 1, adapted.

Every rung must produce ONE command whose exit code (or one line of output) says pass or fail. Record it through `$VETDD/scripts/evidence.sh`.

| # | rung | when | red signal |
|---|---|---|---|
| 1 | failing test (unit, integration, e2e) at the agreed seam | a seam exists and runs in seconds | assertion on the exact symptom |
| 2 | HTTP call against the dev server (`curl`, a script) | the behavior is an endpoint | status code or response body |
| 3 | CLI run on a fixture input, diffed against a known-good snapshot | the behavior is a command | non-empty diff |
| 4 | headless browser (Playwright, the Browser pane) asserting DOM, console, or network | the behavior is UI | assertion on the rendered state |
| 5 | recorded trace (requests, payloads, events) replayed from disk | the trigger is hard to reproduce live | assertion on the replayed result |
| 6 | throwaway harness: the smallest subset of the system with mocked dependencies, one call | the seam is buried | assertion on the one call |
| 7 | property or fuzz loop (hundreds of random inputs) | the defect is input-dependent | any counterexample |
| 8 | bisection harness runnable by `git bisect run` | the defect is a regression between two points | exit code per commit |
| 9 | differential loop: old vs new, or config A vs B, same input | the question is "did behavior change" | non-empty diff |
| 10 | human-in-the-loop script that drives a person step by step and parses a final `KEY=VALUE` line | the observation physically needs a person | the parsed value |

Rung 10 is the last resort and the only case where the human is asked to observe something; the script states why rungs 1–9 do not apply.

## Tightening

After the loop exists, ask three questions and act on each:

1. Faster? Move from e2e to integration to unit, cache setup, narrow the input.
2. Sharper? Assert the reported symptom, not "no error".
3. Deterministic? Freeze time, seed randomness, isolate the file system, disable the network. For a flaky defect the target is a HIGH reproduction rate (loop 100 times, add load, inject sleeps), not a clean single run; a 50% flake is debuggable, a 1% flake is not.

## When no loop can be built

Stop with `blocked`. List the rungs tried and why each failed, and ask for one of: access to a reproducing environment, a redacted artifact (HAR, log, core dump, recording), or permission for temporary instrumentation. Do not proceed to hypotheses without a red-capable command.
