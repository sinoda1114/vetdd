# synthesis: final-judge-dogfood / 20260926-1750

Purpose: prove the final-judge rubric can reach `pass` from the materials its Layout defines (ai-review E4), using the evidence of the Phase 3 dogfooding (fixture ts-kata, February month-end fix, three slices).

## Runs (codex gpt-6-sol, effort medium)

| run | rubric | verdict | criteria below 2 | cause |
|---|---|---|---|---|
| 1730 | v2 | fail | final-evidence 0, smallest-change 0, claims 0 | the assembly left out invoice.test.ts; the reply did not explain the .gitignore line and presented the invalid first calibration as a valid red |
| 1740 | v2 | partial | smallest-change 1, claims 1 | the rubric counted vetdd's own .gitignore line as an unrelated change; the reply's Change section had unlabeled claims |
| 1750 | v3 | pass | none | rubric v3 exempts vetdd setup changes; the reply labels every claim |

## Reading

Every score below 2 in runs 1730 and 1740 pointed at a real defect in what was sent (the assembly, the reply) or in the rubric (setup changes), never at a material the Layout does not provide. The judge also found, unprompted, the invalid "no tests" calibration that the Phase 3 log had flagged by hand.

The rubric changed after run 1740 had been seen. Per principle 6 this is a new version (v3) agreed by the human's decision to fix E4, and judge.sh refused to reuse the v2 rubric.md in the candidates directory until the run was restarted as v3.

The candidates directory was built by hand for this check; a scratch path in the vitest logs contained a model family name and was redacted by hand, which the sanitize step will do once it accepts an assembled directory.
