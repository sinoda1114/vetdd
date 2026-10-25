# synthesis: final-judge-dogfood, final judge rubric v7 with v6's requirement condition restored

## Rubric v7 as accepted

Before accepting v7 (2026-10-25), the human restored the condition final v6 had in claims-match-evidence: every requirement in the reply maps to an evidence path that exists in the layout (or is named as a local log) and shows the stated outcome. It sits in its own subsection ("### Requirements (this rubric only)") after the shared text, so the shared claims text stays byte-identical with implement-business-days v5 and rubric-calibration v2 (`tests/rubric-claims.bats`): a 2 also needs that condition, otherwise the criterion scores at most 1. The version number stays 7; the text, and so the pin, changed: sha256 `77bda0e22a904b908abbcc6eac16843f79910ee405b910b1029bf43f6a87603f` (the runs of 20261025-0028, `fef43ff5...`, were graded under the earlier text; see 20261025-0028-v7-cal1/synthesis.md).

## Calibration again (the human asked for the calibration only, 2 or 3 calls)

| run | artifact | criteria (red, final-evidence, test-observes, smallest, claims, conditions) | verdict |
|---|---|---|---|
| 20261025-1033-v7-cal1 | the 1229 layout with the relabeled reply (the same files as 20261025-0028-v7-cal1) | 2,2,2,2,2,2 | pass, confidence mid |
| 20261025-1033-v7-cal2 | empty (the same files as 20261025-0028-v7-cal2) | 0,0,0,0,0,0 | inconclusive, every score 0 |
| 20261017-1229-v7r | the original layout of 1229 (byte-identical with the baseline 20260926-1750's) | 2,2,2,2,0,2 | fail |

My reading of the relabeled reply's Requirements section: its three requirements each name a red log under evidence/ and the after runs in a meta.json (lines 27-29), so the restored condition holds; the judge said the same ("maps requirements at lines 27-29 to recorded red and after runs"). It found one Measured claim whose citation does not show it ("the refactor pass by a separate agent changed nothing", cited to the refactor slice's meta.json, which shows passing runs, not who ran them or that nothing changed): one fault, so still 2, and the confidence drops to mid (a disagreement). I agree: that citation shows the green runs, not the claim. The original reply still fails on claims (35% labeled), and the empty candidate scores 0 on every criterion (Measured: the three judge.json). 20260926-1750 was not graded again: its layout is byte-identical with 1229's (`diff -r`, Measured), so 1229-v7r stands for both.

Audits: empty candidate 0 everywhere (Measured); label swap not applicable (one label); rubric pin above, in each of the three runs' rubric.md and index.tsv line.

## Decision (step 8)

The human accepted v7 with the condition restored on 2026-10-25 and set this run, 20261025-1033-v7-cal1, as the baseline of final-judge-dogfood (`evals/final-judge-dogfood/baseline`, replacing 20260926-1750; index.tsv promoted = yes). The carry-overs in #95 are left for the next version.

Judge time: 3 calls, 103 s (Measured, local log: the parent's timing file).
