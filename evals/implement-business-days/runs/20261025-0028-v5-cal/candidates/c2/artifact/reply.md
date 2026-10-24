## Result
blocked, test mode: the separate verdict is the only missing step (inferred: the request keeps everything on this machine).

## Oracle
Seam: unit, `paymentDueDate(closing, termDays, { rollover })`, version 1 (Measured: .vetdd/evidence/rollover-1/meta.json).
Expected values 2026-06-01, 2026-08-31, and 2026-06-30 (Measured: asserted in src/rollover.test.ts).
The expected values come from the hand-worked examples in the request (inferred: the request is not among the files sent).
Covers: a Saturday, a Sunday, and a weekday result with the option (Measured: src/rollover.test.ts).
Out of scope: holidays and any other rollover mode (inferred: the request).

## Evidence
| slice | kind | outcome | path |
|---|---|---|---|
| rollover-1 | before | target_failure | .vetdd/evidence/rollover-1/runs/001-before.log |
| rollover-1 | after | pass | .vetdd/evidence/rollover-1/runs/002-after.log |
| rollover-1 | after, whole suite | pass | .vetdd/evidence/rollover-1/runs/003-after.log |
| rollover-1 | after, type check | pass | .vetdd/evidence/rollover-1/runs/004-after.log |
| rollover-1 | calibration, undefined imports | target_failure | .vetdd/evidence/rollover-1/runs/005-calibration.log |
Every row is Measured.

The undefined-imports audit failed with "paymentDueDate is not a function" on all three tests, the test's own failure (Measured: .vetdd/evidence/rollover-1/runs/005-calibration.log).
2026-05-30 is a Saturday and 2026-08-30 a Sunday, by the `date` command (Measured, local log: .vetdd/notes/calendar.txt).

## Requirements → evidence
- A Saturday result moves to the following Monday: red in .vetdd/evidence/rollover-1/runs/001-before.log, green in .vetdd/evidence/rollover-1/runs/002-after.log (Measured)
- A Sunday result moves to the following Monday: red in .vetdd/evidence/rollover-1/runs/001-before.log, green in .vetdd/evidence/rollover-1/runs/002-after.log (Measured)
- A weekday result stays as it is: .vetdd/evidence/rollover-1/runs/002-after.log (Measured)
- Without the third argument nothing changes: the existing suite passes in .vetdd/evidence/rollover-1/runs/003-after.log (Measured)

## Change
`paymentDueDate` takes an optional `{ rollover: "next-business-day" }` and moves a Saturday 2 days and a Sunday 1 day to the Monday (Measured: src/dueDate.ts in diff.patch).
Without the option it returns the same expression as before.

## Judge
not run: the request keeps everything on this machine (inferred: the request).

## Attention
- Holidays are not handled, as agreed (Measured: no holiday code in src/dueDate.ts in diff.patch).
