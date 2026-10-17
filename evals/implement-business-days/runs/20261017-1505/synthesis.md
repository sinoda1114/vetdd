# synthesis: implement-business-days / runs 20261017-1459 and 20261017-1505 (A/B, Phase 4's completion condition)

Variants: `full` (skills/vetdd at 7381e76, the same as main 6c3152c) and `no-principles` (the same without principles.md, and without SKILL.md step 0's "Read principles.md in full now" paragraph). One opus candidate per variant per run, the same brief, in fresh workspaces (fixture.md). Rubric v3, sha256 `31e3300cac371d8b031ecbe766bd71f8670f4f1fb84209214a9cc9adac082770`, calibrated in 1432-cal4 and its label swap.

## Result

| run | label map | agreed-values | red-before-green | smallest-change | claims | verdicts | winner |
|---|---|---|---|---|---|---|---|
| 20261017-1459 | c1 no-principles, c2 full | 2 / 2 | 2 / 2 | 2 / 2 | 0 / 0 | fail / fail | tie (mid) |
| 20261017-1505 | c1 full, c2 no-principles | 2 / 2 | 2 / 2 | 2 / 2 | 0 / 0 | fail / fail | tie (mid) |

## My reading (before opening judge.json)

- All four candidates read CLAUDE.md, followed the skill into test mode, wrote the agreed values as literal assertions through `paymentDueDate`, recorded a red on the agreed assertion before the green, ran the undefined-imports audit and the mutation audit, ended `check-evidence: OK`, and stopped at the separate judge because the request kept everything on the machine (Measured: their replies, evidence, and diffs). The product changes are nearly the same code in all four.
- All four added a no-option Saturday case; two of them did so after a mutation audit showed a survivor, bumped the oracle version, and recorded a new red, which is the process working as designed (Measured: oracle_versions and 012/023 mutation runs).
- Criterion 1, my literal reading: the run-1 no-principles candidate split the three values across two files, which the letter "an oracle file ... asserts all three" does not cover; the judge read it as the intent (2). I agree the intent is met.
- Criterion 4: every candidate followed reply-format.md's sections but left most Oracle and Change statements unlabeled, and two labeled a calendar check Measured with no path. I score all four 0, as the judge did.

I agree with the judge on every score except my literal 1 noted above, and that one does change run 1: under the letter, the no-principles candidate totals 5 and the full one 6 (the judge gave both 6), so run 1 would go to `full` by one point instead of a tie. The judge read the intent and scored a tie; since the judge's winner and my reading then disagree for run 1, step 8 still gives inconclusive, and run 2 is a tie under either reading. The criterion's wording ("an oracle file") is a rubric gap for split oracles: a candidate rubric v4 would say "the oracle files together".

## Decision

Inconclusive after two runs (a tie twice); no baseline exists, so nothing is promoted and nothing is recorded as `baseline`. On this task, principles.md made no difference the rubric can observe: the mode files and scripts carry the behavior on their own. What both variants share is a weakness of the skill itself: replies do not label their claims as reply-format.md asks (filed as an issue). Phase 4's completion condition (an A/B whose judge.json passes the schema, a line in index.tsv, and a written reason when A does not win) is met.

## Notes

- Candidates inherited the user's global instructions (language, the 📝 summary block): two replied in Japanese. The rubric is language-neutral and the judge read both.
- Every candidate hit the global core.hooksPath warning of setup-project.sh and two ran into zsh word splitting or an edit that had not landed before a run (accepted=false runs), the same frictions the parent hit in Phase 3.
- Durations: 171 s and 332 s (run 1), 234 s and 184 s (run 2) (Measured: harness usage).
