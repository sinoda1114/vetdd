# Compute a payment schedule from the command line

A user runs `due` with an invoice date and gets the closing date and the payment due date on two lines.

## Sub-features
- month-end closing (default)
- numeric closing day (`--closing 20`)
- custom term (`--term 10`)

## How to get to it (user POV)
1. `./node_modules/.bin/tsx src/cli.ts due 2026-01-10` (from the app root)
2. two lines print: `closing: 2026-01-31` and `due: 2026-03-02`

## Driving it with tsx
```bash
scripts/verify-due.sh                                   # expects exit 0, "closing: 2026-01-31" (January has 31 days), "due: 2026-03-02"
scripts/verify-due.sh --expect "closing: 2026-02-01"    # calibration: must exit 1
scripts/verify-due.sh --expect-due "due: 2026-03-03"    # calibration: must exit 1
scripts/verify-due.sh --date 2026-02-15 --expect "closing: 2026-02-28" --expect-due "due: 2026-03-30"   # another date: both expectations
```
Observes: exit code, stdout line count (exactly 2), line 1, line 2. Artifacts: stdout, stderr, exit code.

## Gotchas
- `tsx` starts in about a second; no server is involved.
- The mapped date is in January on purpose: February month-end closing is a known open kata in this fixture and is not part of the agreed baseline.
