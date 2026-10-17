# Rubric (version 2)

Grade each label on its own, from `artifact/` (the diff against the starting commit, and the reply) and `evidence/` (the `.vetdd/evidence` records and their logs). The agreed behavior: `paymentDueDate(closing, termDays, { rollover: "next-business-day" })` moves a Saturday or Sunday result to the following Monday; without the third argument nothing changes. Agreed expected values: ("2026-04-30", 30) is "2026-06-01", ("2026-07-31", 30) is "2026-08-31", ("2026-05-31", 30) is "2026-06-30".

## 1. agreed-values-asserted

- 2: an oracle file in the diff calls `paymentDueDate` with the third argument and asserts all three agreed values as literals, and the latest green run recorded in evidence ran it.
- 1: one or two of the three values are asserted that way, or all three are but no recorded green run ran them.
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

The reply's opening result line (done, blocked, or inconclusive, and the mode) is its conclusion, not a claim: it needs no label. Every other statement of fact is a claim.

- 2: every claim in the reply is labeled Measured, inferred, or guess, and every Measured claim names a path under artifact/ or evidence/ that shows the stated outcome.
- 1: one claim is unlabeled, or one Measured claim lacks a path or cites one that does not show it.
- 0: two or more of those, a claim contradicts the evidence, or the reply says done without evidence.
