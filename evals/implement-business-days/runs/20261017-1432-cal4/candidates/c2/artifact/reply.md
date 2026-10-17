## Result
done, test mode.

## Oracle
Seam: unit, `paymentDueDate(closing, termDays, { rollover })`, version 1 (Measured: the seam and version recorded in .vetdd/evidence/rollover-1/meta.json). Expected values 2026-06-01, 2026-08-31, and 2026-06-30, from the hand-worked examples in the request (Measured: asserted in src/rollover.test.ts).

## Evidence
- rollover-1 before: target_failure, expected '2026-05-30' to be '2026-06-01' and '2026-08-30' to be '2026-08-31': .vetdd/evidence/rollover-1/runs/001-before.log (Measured)
- rollover-1 after: pass, 3 tests: .vetdd/evidence/rollover-1/runs/002-after.log (Measured)
- whole vitest suite after: pass: .vetdd/evidence/rollover-1/runs/003-after.log (Measured)
- type check after: pass: .vetdd/evidence/rollover-1/runs/004-after.log (Measured)

## Change
`paymentDueDate` takes an optional `{ rollover: "next-business-day" }`; a Saturday moves 2 days and a Sunday 1 day to the Monday, a weekday stays (Measured: diff.patch). Without the option the result is computed exactly as before (inferred: that branch is the old expression, and the existing suite passed in run 3).

## Attention
Holidays are not handled, as agreed (Measured: no holiday code in diff.patch).
