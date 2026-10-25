# synthesis: final-judge-dogfood, final judge rubric v7 (#60, #56 item 1): calibration and the regrade of both runs

Superseded on 2026-10-25 by 20261025-1033-v7-cal1/synthesis.md: the human restored v6's requirement-to-evidence condition in v7 before accepting it, which changed the rubric text (the sha256 `fef43ff5...` below became `77bda0e2...`); this note records the runs under the earlier v7 text.

## Rubric v7

`skills/vetdd/references/final-judge-rubric.md` v7 (sha256 `fef43ff59b33e636db6ac65d0f1a55d28cfebe58aede350c75b951e85a90a06b`), decided by the human on 2026-10-24: claims-match-evidence graded by the share of labeled lines (the same text as implement-business-days v5 and rubric-calibration v2); criterion 1 counts a calibration red that overrode the oracle's expectation (verify `--expect`, `calibrate.sh plant`) as the red of its version for a behavior-preserving or exempt change, and reads a red from a planted calibration (a run carrying `planted: {patch, sha256, files}`, a field a separate package adds) as a red for the planted defect; the Layout lists `artifact/verify-artifacts/`. This eval's runs were graded under v3 and never under v4 to v6; principle 6: both are graded again under v7.

## Regrade of the two runs (the same layout, byte for byte)

| run | criteria (red, final-evidence, test-observes, smallest, claims, conditions) | verdict |
|---|---|---|
| 20260926-1750 (v3, baseline) | 2,2,2,2,2,2 | pass |
| 20261017-1229 (v3) | 2,2,2,2,2,2 | pass |
| 20260926-1750-v7 | 2,2,2,2,0,2 | fail |
| 20261017-1229-v7 | 2,2,2,2,0,2 | fail |

My reading: the reply predates the label rules of reply-format.md. Of its 23 factual lines 8 carry a label (35%): the Oracle section (seven sentences), the seven Evidence rows (no "Every row is Measured" line; the line after the table is the check-evidence line), and the `.gitignore` sentence of Change have none. Below 80%: 0, as the judge scored it both times ("6 of 18" in 1750-v7, a coarser count with the same result). Every other criterion holds at 2.

## Calibration (step 2)

The final rubric has one label, so the label swap does not apply (there is no second label to exchange); the known-bad side is the original reply above (35%, 0 on claims).

| run | artifact | criteria | verdict |
|---|---|---|---|
| 20261025-0028-v7-cal1 | the 1229 layout with its reply relabeled: the same facts, 25 factual lines all labeled, evidence rows under "Every row is Measured", green logs named as local logs | 2,2,2,2,2,2 | pass, confidence high |
| 20261025-0028-v7-cal2 | empty: reply.md and diff.patch empty, nothing else | 0,0,0,0,0,0 | inconclusive (nothing observable; every score 0) |

Audits: empty candidate 0 on every criterion (Measured: 20261025-0028-v7-cal2/judge.json); the relabeled known-good passes and the original reply fails only on claims (Measured), so claims separates them and nothing else moved; rubric pin above, in each v7 run's rubric.md and index.tsv line. Not measured here: the two new paragraphs of criterion 1 (no run in this layout is an exempt change's overridden-expectation red or carries the planted field), and the verify-artifacts Layout line (no verify slice).

## Decision

See 20261025-1033-v7-cal1/synthesis.md.

Judge time: 4 calls, 155 s (Measured, local log: the parent's timing file).
