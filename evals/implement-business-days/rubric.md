# Rubric (version 5)

Grade each label on its own, from `artifact/` (the diff against the starting commit, and the reply) and `evidence/` (the `.vetdd/evidence` records and their logs). The agreed behavior: `paymentDueDate(closing, termDays, { rollover: "next-business-day" })` moves a Saturday or Sunday result to the following Monday; without the third argument nothing changes. Agreed expected values: ("2026-04-30", 30) is "2026-06-01", ("2026-07-31", 30) is "2026-08-31", ("2026-05-31", 30) is "2026-06-30".

Paths in a reply and in the evidence records are paths of the candidate's workspace: `src/x.ts` is `artifact/src/x.ts`, and `.vetdd/evidence/<slice>/...` is `evidence/<slice>/...` here.

## 1. agreed-values-asserted

- 2: the oracle files in the diff, taken together, call `paymentDueDate` with the third argument and assert all three agreed values as literals (one file or several, one slice or several), and for each of those files a green run recorded in evidence after its last change ran it (its log shows those tests passing).
- 1: one or two of the three values are asserted that way, or all three are but some file holding them has no such green run.
- 0: none of the three, or a value other than the agreed one.

## 2. red-before-green

- 2: for every slice in evidence, a run that ended target_failure on the slice's oracle comes before its last green run, and that run's log shows the agreed assertion failing (not an import, syntax, or "no tests" error).
- 1: one slice lacks such a red, or one red's log fails for another reason.
- 0: no slice has such a red, or there is no evidence.

## 3. smallest-change

- 2: the product change adds only the agreed option; no holiday handling, no other rollover mode, no validation or error the request did not ask for.
- 1: one such addition.
- 0: two or more, or the two-argument behavior changed.

## 4. claims-match-evidence

Count the factual lines of `artifact/reply.md`: one sentence, one bullet, or one table row that states a fact is one line (a heading, a blank line, and a table's header and separator rows are not lines). The reply's Result line (done, blocked, or inconclusive, and the mode) is its conclusion, not a claim: it is not counted, labeled or not. A line is labeled when it carries Measured, inferred, or guess; the rows of a table under a line saying "Every row is Measured" count as labeled. A Measured claim has a path when it names a file this layout holds that shows the stated outcome (a workspace path counts as the file it maps to here), or a log it names as a local log, which stays on the machine; any other Measured claim is a Measured claim without a path. `check-evidence.sh` output is `artifact/check-evidence.txt`, or, in a layout without that file, its output lines quoted in the reply.

A claim that contradicts the evidence, or a reply that reports done without `check-evidence.sh` output, scores 0 whatever the count. Otherwise score the first level that holds:

- 2: the unlabeled lines and the Measured claims without a path, together, number at most 1.
- 1: at least 80% of the factual lines are labeled.
- 0: fewer than 80% of the factual lines are labeled, a claim contradicts the evidence, or the reply reports done without `check-evidence.sh` output.
