# synthesis: implement-business-days, rubric v4, and the A/B of the reply-format change (#55)

## Rubric v4

v4 (sha256 `75f3e1c5314dfa7b3365726bafe64c148c0d8e98e1a93a3086c161843df37f8c`, agreed 2026-10-17) changes criterion 1 to "the oracle files, taken together", so a candidate that splits the three values across files is scored by the intent the judge already read. Principle 6: every run of this eval was graded again under v4, and the calibration was taken again.

| run | what | result under v4 |
|---|---|---|
| 20261018-v4-cal | calibration (the cal4 artifacts) | known-good pass, known-bad fail, empty fail; winner the known-good |
| 20261018-v4-cal-swap | the same, labels swapped | the same verdicts per artifact; winner the known-good |
| 20261017-1459-v4 | the first full / no-principles run | tie (2,2,2,0 each) |
| 20261017-1505-v4 | the second | tie (2,2,2,0 each) |

The two calibration run ids say 20261018 by the parent's mistake; they ran on 2026-10-17 at about 19:15. They are kept as recorded, since each judge.json holds its run id.

## A/B: before-labels (main 3be3dab) against reply-labels (feat/reply-labels b9f3386)

Two runs, one opus candidate per variant per run, fresh workspaces, the same brief.

| run | collection | before-labels | reply-labels | winner |
|---|---|---|---|---|
| 20261017-1933-ws56 | whole final message | 2, 2, 2, 0 | 2, 2, 2, 0 | tie |
| 20261017-1936-ws78 | whole final message | 2, 2, 2, 0 | 2, 2, 2, 0 | tie |
| 20261017-1941-ws56-sections | reply only (## Result to ## Attention, fixture.md step 3 from 19:40) | 2, 2, 2, 0 | 2, 2, 2, 0 | tie |
| 20261017-1944-ws78-sections | reply only | 2, 2, 2, 0 | 2, 2, 2, 0 | tie |

Criterion 4 (claims) is 0 for every candidate in every run: its levels give 0 to two or more unlabeled or unsupported claims, so it cannot tell a reply with almost every claim labeled from one with almost none.

## My reading

I counted the lines of each whole reply that state a fact and those that carry a label (a table under a line such as "every row is Measured" counts as labeled):

| workspace | variant | fact lines | labeled | share |
|---|---|---|---|---|
| 5 | before-labels | 40 | 3 | 7% |
| 7 | before-labels | 43 | 6 | 14% |
| 6 | reply-labels | 43 | 31 | 72% |
| 8 | reply-labels | 30 | 26 | 87% |

The change raises the labeled share from about a tenth to about four fifths, and no other criterion moved (all 2 in every run). What the judge still cited against reply-labels: the summary paragraph and the closing block the candidates add because they inherit the user's global output rules (outside reply-format, now kept out of the draft), "(Measured: the diff)" copied from the template's own example (not a path; fixed in f859266), and a check-evidence result labeled Measured with no file (the eval collection has no check-evidence.txt, unlike the final judge's layout).

## Decision

By step 8 this is inconclusive: the judge's winner is a tie and my reading prefers reply-labels. The human accepted the change on the measured share and no regression (2026-10-17), so it ships; no baseline is set, since no run has a judge winner. Criterion 4's all-or-nothing levels go to an issue (a v5 that grades the share of labeled claims).
