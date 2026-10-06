---
name: verify-ts-kata
description: "Drive ts-kata (cli) the way a user does and prove a feature behaves as agreed. Use after a change to ts-kata, before reporting done, and when vetdd verify mode names this skill. Not a unit test runner."
---

# verify-ts-kata

Surface: cli. Driver: the app's own tsx (`./node_modules/.bin/tsx src/cli.ts`, from the app root; never `npx`, which may fetch from the registry). Isolation: each drive is a fresh short-lived process; any number can run side by side.

## Launch

Nothing stays running. Build check once per checkout:

```bash
npm run typecheck
```

Ready when: `tsc --noEmit` exits 0. Teardown: `scripts/cleanup.sh` (nothing to kill; it removes stale run files only).

## Doctor

`scripts/doctor.sh` is read-only: `src/cli.ts` exists, `node` is on PATH, `node_modules/.bin/tsx` is executable (dependencies installed), and a probe run succeeds: `scripts/probe.ts` (a two-line file with a type annotation) goes through tsx and esbuild and must exit 0. It reports `tsx probe: ok` on success. Exit 0 = drive, 1 = do not drive (the message says why; usually `npm ci` is missing or esbuild is broken). Every drive runs the same check first.

## Drive

- due: `./node_modules/.bin/tsx src/cli.ts due 2026-01-10`, observes the exit code and all of stdout, expects exit `0` and exactly two lines: `closing: 2026-01-31` (January has 31 days; invoiced on the 10th, before the cutoff) and `due: 2026-03-02` (31 + 30 days)
- usage: `./node_modules/.bin/tsx src/cli.ts due` with no date, observes the exit code and stderr, expects exit `2` and a line starting with `usage` (lowercase, case-sensitive)

Scripts: `scripts/verify-due.sh [--date <YYYY-MM-DD> --expect <line 1> --expect-due <line 2>]` (`--date` drives another invoice date, default 2026-01-10, and needs both expectations), `scripts/verify-usage.sh [--expect <exit code>]`.

## Evidence

Every drive runs the real command a user would type and saves stdout, stderr, and the exit code under `${VETDD_ARTIFACTS:-<repo root>/.vetdd/artifacts}/<feature>/<timestamp>/`, printing that path on stdout as `artifacts: <dir>`. Outside a git repository the default is `<app root>/.vetdd/artifacts`. Exit 0 = expectation observed, 1 = observed and not met, 2 = could not observe or usage error. Could not observe means node is not on PATH, tsx is not installed, the tsx probe failed, or the artifacts cannot be written; the script prints `could not observe: <reason>` on stderr, prints no `artifacts:` line, and leaves no artifact directory.

## Cleanup

`scripts/cleanup.sh` removes `.vetdd/run/ts-kata.pid` if a previous launch left one. It never touches `.vetdd/artifacts/`. Exit 1 when the file cannot be removed (the message says why).

## Helpers

- `scripts/doctor.sh`
- `scripts/verify-due.sh`
- `scripts/verify-usage.sh`
- `scripts/cleanup.sh`

All executable; `scripts/probe.ts` is the doctor's probe, not a helper. Run them from `fixtures/ts-kata/` (the app root); they locate the app root from their own path, so any cwd and any invocation (`bash verify-due.sh` inside `scripts/`) works.

## Feature map

`features/README.md`, `features/due.md`, `features/usage.md`. Read the README first.
