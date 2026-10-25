## Result
done (test mode, single)

## Oracle
Seam: closingDate() unit, src/dueDate.test.ts, version 1 (Measured: evidence/feb-end-1/meta.json).
Expected values: closingDate("2026-02-15", "end") is 2026-02-28 and closingDate("2028-02-15", "end") is 2028-02-29 (Measured: asserted in src/dueDate.test.ts).
The values come from the calendar: February 2026 has 28 days and 2028 is a leap year (inferred: the calendar is not among the files sent).
Covers: month-end closing in February, common and leap year (Measured: src/dueDate.test.ts).
Existing oracles that stay green: `npm test` (11 tests) and `npm run typecheck` (Measured, local log: evidence/feb-end-1/runs/003-after.log and 004-after.log).
Out of scope: CLI output format, numeric closing days (inferred: the agreement).
Blind spots: CLI wiring is not tested (inferred: no CLI test in the diff).
Environment: this machine, repository root as cwd, node v24 (Measured: the run conditions in evidence/feb-end-1/meta.json).

## Evidence
| slice | kind | outcome | path |
|---|---|---|---|
| feb-end-1 | before | target_failure | evidence/feb-end-1/runs/001-before.log |
| feb-end-1 | after (file, npm test, typecheck) | pass | evidence/feb-end-1/runs/002-after.log to 004-after.log (local log) |
| feb-end-2 | before | target_failure | evidence/feb-end-2/runs/001-before.log |
| feb-end-2 | after (file, npm test, typecheck) | pass | evidence/feb-end-2/runs/002-after.log to 004-after.log (local log) |
| feb-end-refactor | calibration (001) | recorded target_failure, but not a valid calibration: the module was moved aside, so the log shows "no tests" | evidence/feb-end-refactor/runs/001-calibration.log |
| feb-end-refactor | calibration (002) | target_failure on the agreed assertions (the defect reintroduced) | evidence/feb-end-refactor/runs/002-calibration.log |
| feb-end-refactor | after x2 | pass | evidence/feb-end-refactor/runs/003-after.log and 004-after.log (local log) |
Every row is Measured. check-evidence: feb-end-1: OK, feb-end-2: OK, feb-end-refactor: OK, exit 0 (Measured: artifact/check-evidence.txt).

## Requirements -> evidence
- closingDate("2026-02-15","end") === "2026-02-28": red in evidence/feb-end-1/runs/001-before.log, then the after runs in evidence/feb-end-1/meta.json (Measured)
- closingDate("2028-02-15","end") === "2028-02-29": red in evidence/feb-end-2/runs/001-before.log, then the after runs in evidence/feb-end-2/meta.json (Measured)
- existing tests stay green: the npm test after runs in evidence/feb-end-1/meta.json and evidence/feb-end-2/meta.json (Measured)

## Change
`.gitignore` gains `.vetdd/` (Measured: artifact/diff.patch).
That line is written by vetdd's setup-project.sh so the evidence stays out of commits; it is tooling, not part of the fix (inferred: setup-project.sh adds it).
lastDayOfMonth probed day 31 and fell back to day 30, so February rolled into March (Measured: evidence/feb-end-1/runs/001-before.log shows 2026-03-31 and evidence/feb-end-2/runs/001-before.log shows 2028-03-31).
It now reads day 0 of the following month (Measured: artifact/diff.patch and the after runs in evidence/feb-end-1/meta.json).
The refactor pass by a separate agent changed nothing (Measured: its after runs pass in evidence/feb-end-refactor/meta.json).

## Attention
Only calibration 002 counts for the refactor slice; 001 is kept in the record as history (Measured: evidence/feb-end-refactor/runs/001-calibration.log and 002-calibration.log).
