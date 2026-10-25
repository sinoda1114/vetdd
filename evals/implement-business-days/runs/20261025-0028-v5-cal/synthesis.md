# synthesis: implement-business-days, rubric v5 (#60): calibration and the regrade of every A/B run

## Rubric v5

v5 (sha256 `53c78b824f6ab3b60f2b933307cf7568dacb26cc9142b9c20230406f08e59f2a`) grades claims-match-evidence by the share of labeled lines, with the same text as the final judge's rubric v7 and rubric-calibration v2. Decided by the human on 2026-10-24 after the ties of v4 had been seen (principle 6: a new version, re-agreed, and every run of this eval graded again); the human accepted that it is made after seeing a tie. Two wording fixes from the pre-push review went in before any v5 grading (the "Every row is Measured" line may follow the table, as reply-format's template puts it; a reply with no factual line scores 0, which the empty-candidate audit needs).

## Calibration (step 2), before any regrade

Hand-made replies with a known labeled share, on the known-good artifact of 1432-cal4 (its diff and evidence unchanged, only reply.md replaced). Each reply has 20 factual lines (Result line not counted): 5 Oracle, 5 table rows under "Every row is Measured", 2 Evidence sentences (one cites a local log), 4 Requirements bullets, 2 Change, 1 Judge, 1 Attention. The 95% reply leaves one sentence unlabeled, the 85% one three, the 50% one ten (the table's every-row line removed plus five sentences). The known-bad and the empty (request echoed) are 1432-cal4's own copies. The replies' Result is "blocked" (the request keeps the judge off the machine), so no level-0 "done without check-evidence" applies to them; the known-bad says "Done" without it.

| artifact | expected (agreed values, red, smallest, claims) | 0028-v5-cal | 0028-v5-cal-swap |
|---|---|---|---|
| share 95% | 2,2,2,2 pass | c2: 2,2,2,2 pass | c3: 2,2,2,2 pass |
| share 85% | 2,2,2,1 partial | c5: 2,2,2,1 partial | c1: 2,2,2,1 partial |
| share 50% | 2,2,2,0 fail | c4: 2,2,2,0 fail | c2: 2,2,2,0 fail |
| known-bad | fail | c1: 1,0,0,0 fail | c4: 1,0,0,0 fail |
| empty | 0,0,0,0 fail | c3: 0,0,0,0 fail | c5: 0,0,0,0 fail |
| winner | share 95% | c2 (share 95%), mid | c3 (share 95%), mid |

The order comes out right in both runs (Measured: the two judge.json). The judge cited the same unlabeled lines the replies were built with (95%: line 32; 85%: lines 7, 32, 38; 50%: lines 7, 9, 14-18, 31, 34, 37) and accepted the local-log line as a Measured path in each. Audits: empty candidate 0 on every criterion (Measured); label swap: every artifact kept its verdict and the winner stayed the same artifact (Measured); rubric pin above, the same sha256 in every v5 run's rubric.md and its index.tsv line. The one disagreement in each run is the known-bad's "All tests pass" against its single-file log, already scored 0.

The older calibration runs (1243-cal to 1432-cal4-swap, 20261018-v4-cal and -swap) are not regraded: this calibration replaces them, as 20261018-v4-cal replaced cal4 under v4. Under v5 cal4's known-good would lose on claims for a reason of its own (its reply says "done" with no check-evidence output), which is why the share replies say "blocked".

## Regrade of every A/B run under v5

My reading first (before opening each judge.json): the labeled share by the v5 counting rule, counted with a script that splits paragraphs into sentences and takes bullets and table rows as one line each (approximate), and by hand for 20261017-1933-ws56 c1, which sits near the threshold.

| run | variant | my share | my claims | judge v4 | judge v5 (claims) | v5 winner |
|---|---|---|---|---|---|---|
| 20261017-1459-v5 | no-principles c1 / full c2 | 13% / 17% | 0 / 0 | 2,2,2,0 each, tie | 0 / 0 | tie |
| 20261017-1505-v5 | full c1 / no-principles c2 | 13% / 16% | 0 / 0 | tie | 0 / 0 | tie |
| 20261017-1933-ws56-v5 | reply-labels c1 / before-labels c2 (whole message) | 67% (hand: 31 of 46) / 6% | 0 / 0 | tie | 1 / 0 | c1 |
| 20261017-1936-ws78-v5 | before-labels c1 / reply-labels c2 (whole message) | 12% / 87% (26 of 30, the hand count in 20261017-1944-ws78-sections/synthesis.md) | 0 / 1 | tie | 0 / 1 | c2 |
| 20261017-1941-ws56-sections-v5 | reply-labels c1 / before-labels c2 | 91% / 6% | 1 / 0 | tie | 1 / 0 | c1 |
| 20261017-1944-ws78-sections-v5 | reply-labels c1 / before-labels c2 | 87% / 19% | 1 / 0 | tie | 1 / 0 | c1 |
| 20261017-2151-ws910-shipped-v5 | before-labels c1 / reply-labels as shipped c2 | 12% / 87% | 0 / 0 (contradiction) | tie | 0 / 0 | tie |

Every other criterion stayed 2 for every label in every run (Measured: the seven judge.json); no criterion regressed against v4.

Where the judge and I differ: 1933 c1. The whole message includes the summary paragraph above the reply (6 sentences), the Judge section (3 sentences), and the closing block of changes and to-dos (6 bullets), all unlabeled: 15 of 46 lines, 67%, so 0 by the letter. The judge gave 1 ("at least 80%"), most likely counting the summary paragraph and the Judge paragraph as one line each; even so the share is 79%. 1933 is a whole-message collection, which fixture.md replaced on 2026-10-17 19:40 with the reply part only (1941 is the same workspaces collected that way, and there we agree on 1).

2151 c2 (the shipped format, 87% by my count) scores 0 by the contradiction rule: its Change section says "(Measured: git diff の対象は src/dueDate.ts だけ)" while diff.patch also adds three test files (judge disagreement, judge.json). I read the same: the product change is only src/dueDate.ts, but the claim as written is false against the diff, and v5 makes any contradiction 0.

## Decision

Step 8: the human accepted rubric v5 on 2026-10-25 on these measurements (the calibration order, stable under the swap; v5 separates the reply-labels variant in 1936, 1941, and 1944, and in 1933 by the judge only), together with final v7 (with v6's requirement condition restored) and rubric-calibration v2. No variant is promoted and no baseline is set from these runs: no A/B run has a winner that the judge and my reading agree on for both pairs of variants, and the human set none (eval.md step 8). The open rubric questions (the 0-or-2 edge on short replies, the 1-point level not counting Measured claims without a path, local logs in the eval layouts) stay in #95 for the next version.

Judge time: 9 calls, 583 s in all (Measured, local log: the parent's timing file).
