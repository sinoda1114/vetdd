# synthesis: rubric-calibration / 20261017-1228

Purpose: Phase 7 regression. The same hand-made pair as baseline 20260926-0930 (c1 known good, c2 known bad), the same rubric (v1, sha256 `fdfa7e4343faa8338292ce7b64047c96bcd574a113681de9dfe705390e8b9688`), graded again by the judge as it runs after #2 (private CODEX_HOME and HOME, ephemeral, no user config) from a fresh install (install.sh).

## Result

| run | judge | c1 | c2 | winner |
|---|---|---|---|---|
| 20260926-0930 (baseline) | gpt-6-sol, effort medium | red-before-green 2, claims 2: pass | 0, 0: fail | c1 |
| 20261017-1228 | gpt-6-sol, effort high | red-before-green 2, claims 1: partial | 0, 0: fail | c1 |

## Reading

My own reading before opening judge.json: c1's reply labels its two Evidence lines Measured with existing logs, but its Oracle line "Expected 2026-02-28, from the calendar" carries no label. Level 2 asks for every claim labeled, so c1 is not a 2 by the letter. Level 1 ("one Measured claim lacks a path") and level 0 do not describe this case either: the rubric's scale has a gap, and the judge, now at effort high, took the middle. I would have scored it the same way under the letter; the baseline's 2 was the more lenient reading.

The calibration's purpose holds: the known-good beats the known-bad, and the known-bad fails on both criteria with the same reasons as the baseline. The judge did not regress; the hand-made known-good is not perfectly good under its own rubric.

## Decision

Keep the baseline. No rubric change after this result (principle 6). The scale gap (an unlabeled claim that is not a Measured claim) and the known-good's unlabeled line go to an issue as a candidate rubric v2, which would need re-agreement and a regrade of every run of this eval.
