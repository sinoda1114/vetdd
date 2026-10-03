# Feedback loop ladder

How to build an oracle when the obvious one is not available. Try the rungs in order (rung 11 is the exception: it sits beside them); stop at the first that yields a loop that is red-capable, deterministic, fast, and agent-runnable. Source: mattpocock `diagnosing-bugs` Phase 1, adapted.

Every rung must produce ONE command whose exit code says pass or fail. When the verdict is in the output (one line, a `KEY=VALUE`), wrap the command so the exit code carries it (`grep -q`, `test`): a red forced with `--outcome` on an exit 0, or on a command that could not run (126, 127), does not count for check-evidence rule 8. Record it through `$VETDD/scripts/evidence.sh`.

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
| 11 | types, proofs, model checking: `// @ts-expect-error` under `tsc --noEmit`, or a formal tool the project already has | the agreed property is about every input or every state, not one run | type error, failed proof, counterexample |

Rung 10 is the last resort and the only case where the human is asked to observe something; the script states why rungs 1–9 do not apply. Rung 11 sits beside the order, not after rung 10: it complements a driving rung (below).

## Rung 11: types, proofs, model checking

- TypeScript first: a type-level test is a `// @ts-expect-error` line on an invalid state the type must reject (`export const d: ClosingDay = "start";`), run with `tsc --noEmit` or the project's typecheck script. If the type widens, the directive goes unused and tsc fails. Export the value (or use it): the directive is satisfied by any error on its line, so under `noUnusedLocals` an unused local's own error keeps it green forever. A misspelled type name satisfies it the same way, and only calibration catches that. Use `expectTypeOf` or tsd only when the project already has them.
- The project must be type-clean first (plain `tsc --noEmit` exits 0). Then plain `tsc --noEmit` is the oracle, with no wrapper: any error is red, and a project tsc cannot check (a syntax error, a bad option) is red too, never green. While other type errors exist, rung 11 is not usable: fix them first or pick another rung.
- Calibrating a type test: plant a widening of the type with calibrate.sh, which restores the file afterwards: `calibrate.sh plant <slice> --file <file defining the type> --oracle-file <type test> --oracle-file tsconfig.json`, widen the type, then `calibrate.sh planted <slice> --oracle-file <type test> --oracle-file tsconfig.json -- ./node_modules/.bin/tsc --noEmit` (the project's own tsc: `npx tsc` would fetch a package when typescript is missing, so a missing tool would not exit 127). It must end `target_failure`, and its log must show the type test's own TS2578 (`Unused '@ts-expect-error' directive`). That is the intended reason, read in the log as for every red (modes/test.md step 3); errors the widening causes in other files are expected alongside it.
- The type test is only checked when tsconfig includes it, and `noUnusedLocals` changes what satisfies the directive: name the type test, the tsconfig the check uses, and every tsconfig it `extends` (`--oracle-file <type test> --oracle-file tsconfig.json`), so editing any of them needs a new oracle version (check-evidence rule 8).
- Order exception: when the agreed behavior is itself a type property (an invalid state is rejected by the type), rung 11 may be the first candidate, and the type test may be the slice's final record: tsc runs on the real source. The pairing rule below is for formal tools, which judge a model.
- Formal tools (Lean, Rocq, Dafny, Verus, TLA+) only when the project already has them; a new one only after the human agrees in principle 1a. They judge a model, not the real artifact: always pair them with a rung that drives the real thing (1–6). A formal result alone is never the final record.
- Calibrating a model checker: plant the defect in the model (or the spec) and see a counterexample. A defect planted in the implementation does not change the model, so it proves nothing about the checker.

| checker result | exit | outcome |
|---|---|---|
| the agreed property is violated (the type test's TS2578, a failed proof, a counterexample) | the checker's failure code | `target_failure` |
| checks clean | 0 | `pass` |
| tool missing (126, 127), or a crash with an exit code of its own declared with `--infra-exit` | that code | `infrastructure_error` |
| timeout, out of memory, unknown | its code | `inconclusive`: record `--outcome inconclusive`, or declare the code with `--infra-exit` (then `infrastructure_error`); never red |

The verdict goes through the exit code, as on every rung; never read it from the output by eye. Any other non-zero exit is recorded as `target_failure` unless declared with `--infra-exit` beforehand: evidence.sh treats only 126 and 127 as infrastructure by default, so a run that can be killed (137, 143) or time out (124) needs those codes declared. calibrate.sh takes neither `--infra-exit` nor `--outcome`, so a calibration relies on the next rule alone. Read the log of every red for its reason (modes/test.md step 3): a red recorded for another reason (a crash, a timeout) stays in the record, so when it is the only red, bump `--oracle-version` and record a red for the intended reason.

## Tightening

After the loop exists, ask three questions and act on each:

1. Faster? Move from e2e to integration to unit, cache setup, narrow the input.
2. Sharper? Assert the reported symptom, not "no error".
3. Deterministic? Freeze time, seed randomness, isolate the file system, disable the network. For a flaky defect the target is a HIGH reproduction rate (loop 100 times, add load, inject sleeps), not a clean single run; a 50% flake is debuggable, a 1% flake is not.

## When no loop can be built

Stop with `blocked`. List the rungs tried and why each failed, and ask for one of: access to a reproducing environment, a redacted artifact (HAR, log, core dump, recording), or permission for temporary instrumentation. Do not proceed to hypotheses without a red-capable command.
