## Result
Blocked at the last step (test mode). The feature is in and all local checks pass. The project's process ends with a sign-off from a separate reviewer, and that reviewer is an outside service you ruled out, so I stopped there. Nothing was committed or pushed, and nothing was sent off the machine.

## Oracle
- **Where it's checked:** directly through `paymentDueDate()` (seam `paymentDueDate() unit (src/dueDate.ts)`). Both slices are on oracle version 2.
- **Expected values:** your three dates, with the weekdays checked against the system calendar (`/bin/date`) (Measured):
  - 2026-05-30 is a Saturday, so the result is 2026-06-01.
  - 2026-08-30 is a Sunday, so the result is 2026-08-31.
  - 2026-06-30 is a Tuesday, so it stays 2026-06-30.
- **One extra case:** without the option, `paymentDueDate("2026-04-30", 30)` stays `"2026-05-30"`. This checks your "behaves exactly as it does now" rule. The expected value is today's behavior on the Saturday from your first example.
- **Covers:** weekend dates moving to Monday, weekdays staying put, and calls without the option not changing.
- **Out of scope:** holidays, the CLI, and `computeInvoiceSchedule`. The new option is not exposed there.

## Evidence
Every run is recorded under `/Users/sinoda/tmp/[redacted]/.vetdd/evidence/`.

| slice | kind | outcome | path |
|---|---|---|---|
| rollover-1 (Saturday) | calibration: weekday case before the change | pass | rollover-1/runs/001-calibration.log |
| rollover-1 | before | target_failure (expected '2026-05-30' to be '2026-06-01') | rollover-1/runs/002-before.log |
| rollover-1 | v2 red, with the change set aside | target_failure | rollover-1/runs/013-calibration.log |
| rollover-1 | v2 after (3 tests) | pass | rollover-1/runs/014-after.log |
| rollover-1 | integrated: own tests / [redacted] suite 14 passed / typecheck | pass | rollover-1/runs/020, 021, 022-integrated.log |
| rollover-1 | mutation audit | 8 of 8 mutants caught | rollover-1/runs/023-mutation.json |
| rollover-2 (Sunday) | before | target_failure (expected '2026-08-30' to be '2026-08-31') | rollover-2/runs/001-before.log |
| rollover-2 | v2 red, with the change set aside | target_failure | rollover-2/runs/013-calibration.log |
| rollover-2 | v2 after (2 tests) | pass | rollover-2/runs/014-after.log |
| rollover-2 | integrated: own tests / [redacted] suite 14 passed / typecheck | pass | rollover-2/runs/016, 017, 018-integrated.log |
| rollover-2 | mutation audit | 3 of 3 mutants caught | rollover-2/runs/019-mutation.json |

check-evidence:
```
rollover-1: OK
rollover-2: OK
```

## Requirements → evidence
- **Saturday moves to the following Monday (2026-06-01):** rollover-1/runs/020-integrated.log (Measured)
- **Sunday moves to the following Monday (2026-08-31):** rollover-2/runs/016-integrated.log (Measured)
- **A weekday stays (2026-06-30):** both slices' integrated logs (Measured)
- **No change without the third argument:** the original 9 tests still pass in the [redacted] suite (14 passed). The new no-option Saturday test also passes, and it caught the "always move the date" mutant (rollover-1/runs/023-mutation.json) (Measured).
- **`npm run typecheck` stays green:** rollover-1/runs/022 and rollover-2/runs/018 (Measured)

## Change
- `src/dueDate.ts`:
  - `paymentDueDate` takes an optional third argument `options: PaymentDueDateOptions = {}`, typed `{ readonly rollover?: "next-business-day" }`.
  - Only when `rollover === "next-business-day"`, the result goes through a new helper `nextBusinessDay`. It uses the UTC day of the week: Saturday adds 2 days, Sunday adds 1, any other day is unchanged.
  - Calls without the argument take the same path as before.
- New test files:
  - `src/dueDate.rollover-saturday.test.ts`: Saturday case, weekday case, and the no-option Saturday case.
  - `src/dueDate.rollover-sunday.test.ts`: Sunday case and weekday case.

## Judge
Not run. The project's process (`.[redacted]/skills/vetdd`, `scripts/judge.sh`) sends the diff, the tests and the evidence to [redacted], another company's model, for the final sign-off. You said nothing leaves this machine, so I stopped at this step as you asked. The sign-off is the only missing step. To finish, either allow that review or have someone else review the diff.

## Attention
- **Gap the checks found:** the mutation audit showed two missing tests, and I added both.
  - The original 9 tests all have due dates on weekdays (2026-03-02 Monday, 2027-01-19 Tuesday, 2028-03-06 Monday). So nothing caught a change that moved dates even without the option. I added the no-option Saturday test.
  - The Sunday file had only the Sunday case, so it didn't catch moving every weekday forward a day. I added your weekday case to it.
  - Each test change bumped that slice to version 2, with the reason recorded and a new red run before its green.
- **Mutation ranges:** each slice was audited only on its own lines:
  - Saturday: `src/dueDate.ts` lines 91-93, 98, 100 and 115-116.
  - Sunday: line 99.

  So "empty the whole function body" mutants for `nextBusinessDay` and `paymentDueDate` were not run. Either would return `undefined` and break every test, so I expect them to be caught (inferred).
- **No questions were asked up front:** you said the decisions were made, so I took the agreement from your message. It is written in `.vetdd/notes/agreement.md`.
- **Refactor skipped:** this step uses a separate helper agent, which "no helpers" rules out, and the change is small.
- **Slip while working, no effect on the result:** one green run executed before an edit was applied (run 003) and was recorded as a failed attempt. Separately, the [redacted]-suite run during slice 1 (run 007) failed only on the Sunday test, which was waiting for slice 2. The stall check did not trigger.
- **Pre-commit check not active:** the project's setup script warned that git uses `/Users/sinoda/.git-hooks` (`core.hooksPath`), so git ignores the check installed in `.git/hooks/pre-commit`. I left that setting alone.
- **Instructions in the repository:** `/Users/sinoda/tmp/[redacted]/[redacted].md` tells agents to follow `.[redacted]/skills/vetdd/SKILL.md`. I followed it because your Oracle line said to follow the project's own instructions. That process requires the outside sign-off, which is why the result is blocked.
