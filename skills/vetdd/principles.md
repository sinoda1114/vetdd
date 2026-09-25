# vetdd principles

Read this file in full at the start of every vetdd task. Cite a principle by its bold name only after reading it here. Ten principles, one rule each. When two conflict, the earlier one wins. Mode files (`modes/*.md`) add detail; they never relax a principle.

## 1. oracle-first

No oracle, no product code. The order is fixed: (a) agree with the human on the acceptance criteria, the seam the oracle sits on, the source the expected values come from, what the oracle covers, what is out of scope, and its known blind spots; (b) implement the oracle (test, verify script, or rubric); (c) calibrate it (principle 2); (d) only then change the product. When the criteria, the seam, or the expected-value source change later, go back to (a), and all earlier evidence is void.

## 2. calibrate-the-oracle

An oracle is trusted only after it has returned green on a known-good case and red on the targeted defect. Every run has one of four outcomes: `pass`, `target_failure`, `infrastructure_error`, `inconclusive`. Only `target_failure` counts as red; a crash, a missing dependency, or an expired login is never evidence. When a check fails, suspect the observation method before the system.

## 3. red-before-green

For a defect or a new behavior, reproduce red on the product first, then make it green with the smallest change. For a behavior-preserving change (refactor, config, wiring, glue), the calibration red from principle 2 stands in, and the oracle must be green both before and after the change. Record every run through `scripts/evidence.sh`; the evidence binds to the exact tree it ran on and is void once that tree changes. The recording is the proof; the claim is not.

## 4. test-behavior-not-implementation

Call the code the way its users do. Assert either a literal expected value from an independent source (a worked example, the spec, a known-good output) or a property the spec guarantees (round-trip, element preservation, an invariant). Hollow assertions (only `toBeDefined`, only `toHaveBeenCalled`, expected values recomputed from the code under test) observe nothing; a quick check is whether the test would still pass if every import returned `undefined`. Rewrite or delete such a test, and name what replaces the lost coverage before deleting.

## 5. prove-it-works

Verify against the real artifact: run the feature, read the actual value, inspect the integrated diff. In the reply, map each agreed requirement to its evidence path, and label every claim as Measured, inferred, or guess. Never claim "proven" beyond what the oracle observed. "It compiles", "CI is green", and "the subagent said so" are not verdicts.

## 6. separate-author-and-judge

The author runs the oracle as often as needed while iterating, but never issues the final verdict. The final judge is a different model family (Codex when the author is Claude), sees the artifact and the evidence, and is blind to the candidates' origin, the expected winner, and the author's self-assessment. When judges disagree, first confirm they saw the same artifact under the same conditions; only then suspect the rubric. A rubric change gets a version and a regrade of every candidate. An eval verdict is a comparison, not a pass: the eval mode defines the pass threshold, the repetitions, and the inconclusive state.

## 7. one-oracle-per-unit

Split work so each unit ends in its own observable pass or fail, and deliver in the order that proves itself: failing test first, fix on top. Fan out only when the units' oracles are independent and the units share no files, contracts, or runtime resources; otherwise keep one writer. One writer per worktree; readers may share. The parent integrates from a common base, runs every oracle on the integrated tree, obtains the separate judge's verdict on that tree, and copies each worker's evidence into the main repository before removing its worktree. Completion is judged on the integrated tree, never on a worker's slice.

## 8. stop-only-for-oracle-and-irreversible

Ask the human to agree on the oracle (principle 1a), and ask before any irreversible action (schema change, publish, send, delete). Hold a hearing before fanning out to two or more writers. For everything else, run the experiment, present the result, and let the human correct it afterwards. When progress is impossible (the required judge is unavailable, the environment is unreachable, the oracle stays `inconclusive` after the retry cap), end in `blocked` or `inconclusive` with the evidence so far. Never report done without evidence.

## 9. encode-in-structure

When a rule can be a script, a schema, or a check, make it one and delete the prose. An instruction repeated twice is a symptom; the fix is structural.

## 10. no-redelegation

A subagent brief executes directly: no Skill tool calls, no further agents. Reading a file by path and following it (a mode file, a generated verify skill) is allowed and is how a worker runs a procedure. Context travels by file pointer, never inline. Results come back as summaries with evidence paths, never as raw transcripts.
