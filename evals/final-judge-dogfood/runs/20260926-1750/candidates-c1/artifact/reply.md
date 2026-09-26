## Result
done (test mode, single)

## Oracle
Seam: closingDate() unit, src/dueDate.test.ts, version 1. Expected values from the calendar: February 2026 has 28 days, so closingDate("2026-02-15", "end") is 2026-02-28; 2028 is a leap year, so closingDate("2028-02-15", "end") is 2028-02-29.
Covers: month-end closing in February (common and leap year). Existing oracles that stay green: `npm test` (11 tests) and `npm run typecheck`.
Out of scope: CLI output format, numeric closing days. Blind spots: CLI wiring is not tested.
Environment: this machine, repository root as cwd, node v24.

## Evidence
| slice | kind | outcome | path |
|---|---|---|---|
| feb-end-1 | before | target_failure | evidence/feb-end-1/runs/001-before.log |
| feb-end-1 | after (file, npm test, typecheck) | pass | local logs 002-004 |
| feb-end-2 | before | target_failure | evidence/feb-end-2/runs/001-before.log |
| feb-end-2 | after (file, npm test, typecheck) | pass | local logs 002-004 |
| feb-end-refactor | calibration (001) | recorded target_failure, but not a valid calibration: the module was moved aside, so the log shows "no tests" | evidence/feb-end-refactor/runs/001-calibration.log |
| feb-end-refactor | calibration (002) | target_failure on the agreed assertions (the defect reintroduced) | evidence/feb-end-refactor/runs/002-calibration.log |
| feb-end-refactor | after x2 | pass | local logs 003-004 |
check-evidence: see artifact/check-evidence.txt (Measured)

## Requirements -> evidence
- closingDate("2026-02-15","end") === "2026-02-28": feb-end-1 before red, then after pass (Measured)
- closingDate("2028-02-15","end") === "2028-02-29": feb-end-2 before red, then after pass (Measured)
- existing tests stay green: npm test after runs in each slice's meta.json (Measured)

## Change
`.gitignore` gains `.vetdd/`, written by vetdd's setup-project.sh so the evidence stays out of commits; it is tooling, not part of the fix.
lastDayOfMonth probed day 31 and fell back to day 30, so February rolled into March (Measured: the before logs show 2026-03-31 and 2028-03-31). It now reads day 0 of the following month (Measured: the diff and the after runs). The refactor pass by a separate agent changed nothing (Measured: its after runs pass on the same tree hash).

## Attention
Only calibration 002 counts for the refactor slice; 001 is kept in the record as history (Measured from the logs).
