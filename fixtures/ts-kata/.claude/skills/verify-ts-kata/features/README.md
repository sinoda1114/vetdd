# ts-kata feature map

## Baseline preconditions
- built: `npm run typecheck` exits 0 on this checkout
- deps: `npm ci` has been run (`node_modules/.bin/tsx` exists and the doctor's tsx probe passes)
- env: none; no ports

## Driving conventions
- Scripts locate the app root themselves; run them from anywhere.
- One feature per drive; call `scripts/doctor.sh` before the first drive and after any surprise.

## Proof and skip reporting
- CLI proof: the exact command, stdout, stderr, exit code, saved under `.vetdd/artifacts/<feature>/<timestamp>/` at the repository root (at the app root outside git).
- Nothing here changes state, so no second read-only view is needed.
- Unreachable: report `verified-unreachable` only with the command tried and the unmet precondition (for example `npm ci` not run, or the tsx probe failed).

## Features
1. [due](due.md)
2. [usage](usage.md)
