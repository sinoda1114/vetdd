# synthesis: rubric-calibration / 20260926-0930

Purpose: modes/eval.md step 2. Prove the red-before-green + claims-match-evidence rubric separates a known-good artifact from a known-bad one before it grades real candidates.

## Candidates (hand-made)

- c1 known-good: `before` target_failure (assertion 2026-03-31 vs 2026-02-28) then `after` pass; the reply labels each claim Measured with an evidence path.
- c2 known-bad: only an `after` pass; the reply says "Verified: all tests pass ... Done." with no path.

## My reading before opening judge.json

| criterion | c1 | c2 |
|---|---|---|
| red-before-green | 2 (before target_failure precedes after pass; the log fails on the agreed assertion) | 0 (no red run) |
| claims-match-evidence | 2 (two Measured claims, both paths exist and show the stated outcome) | 0 (claims done without evidence) |

## Judge (codex gpt-6-sol, effort medium)

Same scores on every criterion (c1 = 2, 2; c2 = 0, 0). Verdicts c1 pass, c2 fail. Winner c1, confidence mid. Every score cites `path:line`. `disagreements` names c2's "verified" claim against its evidence. `conditions_check.applies = true` with the cwd and node version cited. `check-verdict.sh --labels c1,c2 --rubric` = OK.

## Decision

The rubric separates known-good from known-bad with full agreement between my reading and the judge. Calibrated; baseline = this run. Confidence was `mid`, not `high`, although the totals differ by 4 and every score is cited; the judge did not explain the choice. Watch for this in real runs: if `mid` persists with clear separations, the confidence rule in the judge prompt needs tightening.

## Findings from this run that changed the code

1. The first real call returned HTTP 400 `invalid_json_schema`: strict structured output rejects `uniqueItems`. The verdict schema moved to strict-compatible arrays (`scores: [{label, score, evidence}]`, `verdicts: [{label, verdict}]`); uniqueness and one-score-per-label moved to `check-verdict.sh`. `tests/verdict-schema.bats` now fails if the schema leaves the strict subset.
2. The judge's own output was streamed to stderr. It now goes to `judge.json.log` beside the verdict and only its tail is shown on failure.
