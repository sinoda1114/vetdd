# Reject bad input with a usage message

A user who omits the date, or passes an invalid one, gets a usage line on stderr and exit code 2.

## Sub-features
- missing date
- impossible date (`2026-02-30`)
- closing day out of range (`--closing 31`)

## How to get to it (user POV)
1. `npx tsx src/cli.ts due`
2. stderr shows a line starting with `usage`; the shell reports exit code 2

## Driving it with tsx
```bash
scripts/verify-usage.sh              # expects exit 2 and a stderr line starting with "usage"
scripts/verify-usage.sh --expect 0   # calibration: must exit 1
```
Observes: exit code and stderr. Artifacts: stdout, stderr, exit code.

## Gotchas
- Exit 2 here is the product's behavior, not an infrastructure error; the script maps it to "observed".
