# vetdd principles

Read this file in full at the start of every vetdd task. Cite a principle by its bold name only after reading it here. Ten principles, one rule each. When two conflict, the earlier one wins.

## 1. oracle-first

Build the judge before the change: a test, a verify script, or a rubric. No oracle, no implementation. When none exists, building it is the first task, and the human agrees on it before any code is written.

## 2. verify-the-oracle

Prove the oracle can go red on the failure it targets before trusting it. When a check fails, suspect the observation method before the system. An oracle that has never gone red has proved nothing.

## 3. red-before-green

Watch the oracle fail, then make it pass with the smallest change. Record both runs to the evidence directory through `scripts/evidence.sh`. The recording is the proof; the claim is not.

## 4. test-behavior-not-implementation

Call the code the way its users do, and assert a literal expected value from an independent source of truth (a worked example, the spec, a known-good output). A test that would still pass if every import returned `undefined` observes nothing: rewrite the assertion or delete the test. Prefer no test over a bad test.

## 5. prove-it-works

Verify against the real artifact: run the feature, read the actual value, inspect the diff. Label every claim in the reply as Measured, inferred, or guess. "It compiles", "CI is green", and "the subagent said so" are not verdicts.

## 6. separate-author-and-judge

The one who wrote the change never grades it. The judge is a different model family from the author. Agreement between independent judges is high signal; disagreement means the rubric is ambiguous or a model is biased, and the rubric is fixed first.

## 7. one-oracle-per-unit

Split work so each unit ends in its own observable pass or fail, and deliver in the order that proves itself: failing test first, fix on top. Parallelize only units whose oracles are independent. One writer per worktree; readers may share.

## 8. stop-only-for-oracle-and-irreversible

Ask the human to agree on the oracle, and ask before any irreversible action (schema change, publish, send, delete). Hold a hearing before fanning out to two or more writers. For everything else, run the experiment, present the result, and let the human correct it afterwards.

## 9. encode-in-structure

When a rule can be a script, a schema, or a check, make it one and delete the prose. An instruction repeated twice is a symptom; the fix is structural.

## 10. no-redelegation

A subagent brief executes directly: no Skill calls, no further agents. Context travels by file pointer, never inline. Results come back as summaries with evidence paths, never as raw transcripts.
