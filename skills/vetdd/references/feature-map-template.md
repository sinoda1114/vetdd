# Feature map template

`features/README.md` and `features/<feature>.md` inside a verify skill. Written for an agent that opens the file cold.

## features/README.md

````markdown
# <app> feature map

## Baseline preconditions
- <built: `<build command>` succeeded on this checkout>
- <data: fixture or seed present, e.g. `fixtures/*.json`>
- <env: variables or ports that must be free>

## Driving conventions
- Run scripts from the repository root.
- One feature per drive; call `scripts/doctor.sh` before the first drive and after any surprise.
- Never drive an instance you did not launch.

## Proof and skip reporting
- CLI proof: the exact command, stdout, stderr, exit code, saved under `.vetdd/artifacts/<feature>/<timestamp>/`.
- HTTP proof: request line, status, response body.
- UI proof: ARIA snapshot plus screenshot, before and after the action.
- A change-making feature is confirmed through a second read-only view (a `get`/`list` command, a fresh page load, a DB read).
- Unreachable: report `verified-unreachable` only with the command tried and the unmet precondition. A substitute check on another path is never reported as verified.

## Features
1. [<feature-1>](<feature-1>.md)
2. [<feature-2>](<feature-2>.md)
3. [<feature-3>](<feature-3>.md)
````

## features/<feature>.md

The H1 and the four H2s are fixed, in this order.

````markdown
# <feature name>

<one paragraph: what the user achieves with this feature and where it starts.>

## Sub-features
- <variant or option 1>
- <variant or option 2>

## How to get to it (user POV)
1. <the first thing a user does: command typed, page opened, menu chosen>
2. <the next step>
3. <what the user sees when it worked, as a literal>

## Driving it with <driver>
```bash
scripts/verify-<feature>.sh            # expects "<literal>" from <source>
scripts/verify-<feature>.sh --expect X # calibration: must exit 1
```
Observes: <stdout line | response field | ARIA node>. Artifacts: <what is saved>.

## Gotchas
- <a precondition that is easy to miss>
- <a known flake and how the script waits it out>
````

Example (fixture ts-kata, CLI):

````markdown
# Compute a payment schedule from the command line

A user runs `due` with an invoice date and gets the closing date and the payment due date.

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
scripts/verify-due.sh --expect "closing: 2026-02-01"    # calibration red
scripts/verify-due.sh --expect-due "due: 2026-03-03"    # calibration red
```
Observes: exit code, stdout line count (exactly 2), line 1, line 2. Artifacts: stdout, stderr, exit code.

## Gotchas
- `tsx` starts in about a second; the script does not need a server.
- A bad date exits 2 with a usage line; that is the product's behavior, not an infrastructure error.
````
