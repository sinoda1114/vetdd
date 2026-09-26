---
name: verify-ts-kata
description: "Drive ts-kata (cli) the way a user does and prove a feature behaves as agreed. Use after a change to ts-kata, before reporting done, and when vetdd verify mode names this skill. Not a unit test runner."
---

# verify-ts-kata

Surface: cli. Driver: tsx (`npx tsx src/cli.ts`). Isolation: each drive is a fresh short-lived process; any number can run side by side.

## Launch

Nothing stays running. Build check once per checkout:

```bash
npm run typecheck
```

Ready when: `tsc --noEmit` exits 0. Teardown: `scripts/cleanup.sh` (nothing to kill; it removes stale run files only).

## Doctor

`scripts/doctor.sh` is read-only: `node` is on PATH, `node_modules/.bin/tsx` exists (dependencies installed), and `src/cli.ts` exists. Exit 0 = drive, 1 = do not drive (the message says why; usually `npm ci` is missing).

## Drive

- due: `npx tsx src/cli.ts due 2026-01-10`, observes stdout line 1, expects `closing: 2026-01-31` (January has 31 days; invoiced on the 10th, before the cutoff)
- usage: `npx tsx src/cli.ts due` with no date, observes the exit code and stderr, expects exit `2` and a line starting with `usage`

Scripts: `scripts/verify-due.sh [--expect <line>]`, `scripts/verify-usage.sh [--expect <exit code>]`.

## Evidence

Every drive runs the real command a user would type and saves stdout, stderr, and the exit code under `${VETDD_ARTIFACTS:-<repo root>/.vetdd/artifacts}/<feature>/<timestamp>/`, printing those paths on stdout. Exit 0 = expectation observed, 1 = observed and not met, 2 = could not observe (node or tsx missing).

## Cleanup

`scripts/cleanup.sh` removes `.vetdd/run/ts-kata.pid` if a previous launch left one. It never touches `.vetdd/artifacts/`.

## Helpers

- `scripts/doctor.sh`
- `scripts/verify-due.sh`
- `scripts/verify-usage.sh`
- `scripts/cleanup.sh`

All executable. Run them from `fixtures/ts-kata/` (the app root); they locate the app root from their own path, so any cwd works.

## Feature map

`features/README.md`, `features/due.md`, `features/usage.md`. Read the README first.
