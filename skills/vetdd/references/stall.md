# Stall

A slice is stalled when retrying the same design stops paying: K+1 failed attempts in a row (K = 2 by default; the agreement's Q3 can change it) whose failure counts never fall. An attempt is an `after` run that ended `target_failure`; its count is the runner's `tests.failed` when the run took `--test-report`, else 1. An `infrastructure_error` never counts (the environment, not the design, failed: principle 8 says `blocked`), and a green run or a new oracle version starts over. `"$VETDD/scripts/stall.sh" <slice>` says so: exit 3 is a stall. In an arena, `arena-layout.sh` exit 5 (no lane green) is a stall of the arena's task.

Run `stall.sh` after each failed attempt. Before the next attempt on a stalled slice, take these steps.

## 1. Write the handover

Write a draft with these headings, each on a line of its own, and record it with `"$VETDD/scripts/handover.sh" <slice> --file <draft>` (it becomes `.vetdd/evidence/<slice>/handover-<n>.md`; in an arena, one per red lane, under that lane's slice):

- `## Unmet requirement`: which agreed criterion (Q1) is still red.
- `## Expected and actual`: the literal expected value and what came back, from the logs.
- `## Minimal reproduction`: the smallest command or input that shows it.
- `## Hypotheses tried`: each one, what was changed for it, and what the run then showed.
- `## Why it failed`: the cause, not the symptom: why this design cannot reach the expected value.
- `## Reusable results`: what the next design keeps (tests, helpers, findings), with paths.

Pass/fail alone is not a handover: the next design needs the reasons. `check-evidence.sh` rule 11 asks for one handover per stall in the record, each with every heading.

## 2. Take one of the two exits

The handover's "Why it failed" decides which.

- **Redesign** when the cause is in the design or the implementation and the agreement still holds. Same oracle, same agreement, so no stop: start a fresh subagent (role author, or new arena lanes when the budget allows) whose brief holds every handover of the slice. It must answer, in its report or design note, which failure cause it avoids and by what change; a retry of the same design is not a redesign. Its attempts count anew. At most 2 redesigns per slice by default (Q3 can change it).
- **Back to 1a** when the cause is in the agreement: the expected value contradicts the spec, the seam cannot observe the behavior, or two criteria conflict. Stop and ask the human with `AskUserQuestion` (principle 8), the handover attached. A changed oracle is a new version: `oracle-version.sh <slice> --version <new> --change meaning` with the new agreement, then its red before any green.

A stall past the redesign budget (a third one by default) ends the task `blocked`, with every handover and the evidence so far.
