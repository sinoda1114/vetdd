# vetdd principles

Read this file in full at the start of every vetdd task. Cite a principle by its bold name only after reading it here. Each principle states one rule, its exceptions, and when it stops the work. Operational detail (record formats, scripts, sanitization steps) lives in `modes/*.md` and `parallel/*.md`; those files never relax a principle. When two principles conflict, the earlier one wins.

The backbone every mode follows: agree on the oracle → build and calibrate it → measure before the change → change → measure after, on the integrated tree.

## 1. oracle-first

No oracle, no product code. The order is fixed: (a) agree with the human on the acceptance criteria, the seam the oracle sits on, the source of expected values, what the oracle covers, what is out of scope, and its known blind spots; (b) implement the oracle (test, verify script, or rubric); (c) calibrate it (principle 2); (d) only then change the product. Every oracle change gets a version and a reason. If the agreed scope changes, return to (a). If the oracle's behavior changes, recalibrate and rerun what depended on it.

## 2. calibrate-the-oracle

An oracle is trusted only after it has returned green on a known-good case and red on the targeted defect. When no known-good case exists yet, a hand-worked example from the spec serves as one; the uncalibrated oracle never labels its own cases. Every run has one outcome: `pass`, `target_failure` (the subject was observed and failed the agreed criterion, whatever the symptom, including a crash when the crash is the defect), `infrastructure_error` (the observation itself did not happen), or `inconclusive`. Only `target_failure` counts as red. When a check fails, suspect the observation method before the system.

## 3. red-before-green

For a defect or a new behavior, reproduce red on the product first, then make it green with the smallest change. For a behavior-preserving change (refactor, config, wiring, glue), the calibration red from principle 2 stands in, and the oracle must be green both before and after the change. Record every run through `scripts/evidence.sh`, with its kind: `calibration`, `before`, `after`, or `integrated`. Each record binds to the tree, the oracle version, and the run conditions it ran under; earlier kinds stay valid as history, and only the final `after` or `integrated` record must match the tree being delivered. The recording is the proof; the claim is not.

## 4. test-behavior-not-implementation

Call the code the way its users do. Assert either a literal expected value from an independent source (a worked example, the spec, a known-good output) or a property the spec guarantees (round-trip, element preservation, an invariant). Hollow assertions (only `toBeDefined`, only `toHaveBeenCalled`, expected values recomputed from the code under test) observe nothing; a quick check is whether the test would still pass if every import returned `undefined`. Rewrite or delete such a test, and name what replaces the lost coverage before deleting.

## 5. prove-it-works

Verify against the real artifact: run the feature, read the actual value, inspect the integrated diff. In the reply, map each agreed requirement to its evidence path, and label every claim as Measured, inferred, or guess. Never claim "proven" beyond what the oracle observed. "It compiles", "CI is green", and "the subagent said so" are not verdicts.

## 6. separate-author-and-judge

The author runs the oracle as often as needed while iterating, but never issues the final verdict. The final judge is a different model family (Codex when the author is Claude), sees a sanitized copy of the artifact and evidence, and is blind to the candidates' origin, the expected winner, and the author's self-assessment. Agreement and disagreement between judges are material for investigation, not verdicts: on disagreement, first confirm both saw the same artifact under the same conditions; if they did and still disagree, either fix the rubric (new version, regrade all) or end `inconclusive`. Never weaken a rubric after seeing the result it would change.

## 7. one-oracle-per-unit

Split work so each unit ends in its own observable pass or fail, and each unit follows principle 3 in full. Arena (several candidates for one task) shares the contract and the oracle, and isolates each candidate's write target and mutable runtime resources. Swarm (units of one task) additionally requires that units touch different files and change no contract another unit depends on; otherwise keep one writer. One writer per worktree; readers may share. The parent integrates from a common base, obtains `integrated` evidence and the separate judge's verdict on that tree, and completion is judged there, never on a worker's slice.

## 8. stop-only-for-oracle-and-irreversible

Work autonomously within the agreed scope, environment, and budget. Stop for the human at three points: agreeing on the oracle (principle 1a), before any action whose effect reaches outside the workspace or cannot be restored (production state, external sends or publishes, data that has no backup), and before fanning out to two or more writers. Everything else is an experiment: run it, present the result, let the human correct it afterwards. When progress is impossible (the required judge is unavailable, the environment is unreachable, the oracle stays `inconclusive` after the retry cap), end in `blocked` or `inconclusive` with the evidence so far. Never report done without evidence.

## 9. encode-in-structure

When a rule can be a script, a schema, or a check, make it one and delete the prose. An instruction repeated twice is a symptom; the fix is structural.

## 10. no-redelegation

A subagent brief executes directly: no Skill tool calls, no further agents. Reading a file by path and following it (a mode file, a generated verify skill) is allowed and is how a worker runs a procedure. Context travels by file pointer, and results come back as a summary with evidence paths.
