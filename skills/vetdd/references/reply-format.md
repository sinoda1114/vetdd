# Reply format

The final reply of a vetdd task. Every claim carries its label in the same sentence: **Measured** (you ran it and read the result), **inferred** (derived from something measured), or **guess** (not observed). Write the reply in the user's language; keep this structure.

```
## Result
<one line: done | blocked | inconclusive, and the mode used>

## Oracle
Seam: <seam>, version <n>. Expected value <literal>, from <source>.
Covers: <what>. Out of scope: <what>. Blind spots: <what>.

## Evidence
| slice | kind | outcome | path |
|---|---|---|---|
| <id> | before | target_failure | .vetdd/evidence/<id>/runs/001-before.log |
| <id> | after | pass | .vetdd/evidence/<id>/runs/002-after.log |
check-evidence: <exact output line(s)>

## Requirements → evidence
- <requirement 1>: <evidence path> (Measured)
- <requirement 2>: <evidence path> (Measured)

## Change
<what changed and why, 3–6 lines; the diff is the source, do not restate it>

## Judge
<verdict from the separate judge, or "not run: <reason>">

## Attention
<anything the human should look at: a guess, a skipped step with its reason, a blind spot that matters>
```

A `blocked` or `inconclusive` result keeps the same sections and states, under Attention, what was tried and what would unblock it.

Never write "should work", "verified" without a path, or "all tests pass" without the command's output line.
