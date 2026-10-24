# synthesis: rubric-calibration, rubric v2 (#53, #60): calibration and the regrade of both runs

## Rubric v2

v2 (sha256 `204ab11a795b1b36c014dd3e6d2027141cd808500a332a2543f724e20454e988`) replaces v1's claims-match-evidence with the share-graded text shared with the final judge's rubric v7 and implement-business-days v5 (human decision 2026-10-24; #53's gap, an unlabeled claim that is not a Measured claim, now has a level). Principle 6: both runs of this eval graded again, and the calibration taken again with the empty candidate and the label swap.

## Regrade of the two runs (the same hand-made pair, byte for byte)

| run | c1 known-good: red, claims | c2 known-bad | winner |
|---|---|---|---|
| 20260926-0930 (v1, baseline) | 2, 2 pass | 0, 0 fail | c1 |
| 20261017-1228 (v1) | 2, 1 partial | 0, 0 fail | c1 |
| 20260926-0930-v2 | 2, 0 fail | 0, 0 fail | c1 |
| 20261017-1228-v2 | 2, 2 pass | 0, 0 fail | c1 |

My reading: c1's reply has four factual lines; its Oracle line holds two sentences ("Seam: closingDate() unit." and "Expected 2026-02-28, from the calendar ..."), both unlabeled, and v2 counts one sentence as one line. Two unlabeled of four is 50%: 0 by the letter, as 0930-v2 scored it. 1228-v2 took the Oracle line as one line (one fault: 2). The same input got 0 and 2: with four lines the count sits on the edge between "at most 1" and "below 80%", and the judge splits a two-sentence line one way or the other. The winner and the known-bad's fail do not move. The baseline's known-good (c1 pass under v1) is not a pass under v2 by the letter.

## Calibration (step 2)

The known-good's reply was remade with its expected-value sentence labeled (inferred: the calendar is not sent), leaving exactly one unlabeled sentence ("Seam: closingDate() unit."): 3 of 4 lines labeled, 75%, one fault, so the "at most 1" level applies before the 80% one. The known-bad is the pair's c2; the empty candidate has an empty reply.md and diff.patch and no evidence.

| artifact | expected | 20261025-0028-v2-cal | 20261025-0028-v2-cal-swap |
|---|---|---|---|
| known-good, one unlabeled sentence | 2, 2 pass | c1: 2, 2 pass | c2: 2, 2 pass |
| known-bad | 0, 0 fail | c2: 0, 0 fail | c1: 0, 0 fail |
| empty | 0, 0 fail | c3: 0, 0 fail | c3: 0, 0 fail |
| winner | known-good | c1, mid | c2, high |

Audits: empty candidate 0 on both criteria (Measured: both judge.json); label swap: verdicts kept per artifact and the winner stayed the known-good (Measured); rubric pin above, the same sha256 in each v2 run's rubric.md and index.tsv line. The disagreement in each run is the known-bad's "Verified ... Done" against its single after run, already scored 0.

## Decision

Step 8 (the human's acceptance) is pending; nothing is promoted (index.tsv promoted = no) and the baseline stays 20260926-0930. For it: v2 orders the pair correctly in every run, the remade known-good passes in both orders, and the original known-good is graded 0 or 2 on claims depending on how the judge splits its two-sentence line (by the letter, 0). Keeping the original pair as this eval's baseline would need either the remade known-good (a new baseline from 20261025-0028-v2-cal) or acceptance of that edge.

Judge time: 4 calls, 128 s (Measured, local log: the parent's timing file).
