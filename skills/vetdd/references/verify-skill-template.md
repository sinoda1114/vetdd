# verify skill template

Generates `.claude/skills/verify-<app>/SKILL.md`. Replace every `<...>`; delete a section only if the surface truly has no such step, and say so in its place. The reader is an agent that has never seen this app and opens this file in the middle of a task.

````markdown
---
name: verify-<app>
description: "Drive <app> (<surface>: cli | http | ui) the way a user does and prove a feature behaves as agreed. Use after a change to <app>, before reporting done, and when vetdd verify mode names this skill. Not a unit test runner."
---

# verify-<app>

Surface: <cli | http | ui>. Driver: <tsx / curl / Playwright / Browser pane>. Isolation: <two instances can run side by side on different ports | single shared instance: never drive one you did not launch>.

## Launch

```bash
<the repo's own command, e.g. npm run dev -- --port "${PORT:-3000}">
```
Ready when: <a log line, an open port, a prompt string>. Launch records the PID in `.vetdd/run/<app>.pid`. For a short-lived CLI, build once (`<build command>`) and run each drive in a fresh process; there is nothing to keep alive.
Teardown: `scripts/cleanup.sh`.

## Doctor

`scripts/doctor.sh` is read-only and answers "is this instance worth driving": <process alive from the recorded PID | version or build id matches HEAD | the port is ours | auth is valid>. Exit 0 = drive, 1 = do not drive (the message says why).

## Drive

One script per mapped feature, `scripts/verify-<feature>.sh [--expect <literal>]`. Each uses only selectors and commands that exist in the repo:
- <feature-1>: `<exact command or route>`, observes `<what>`, expects `<literal>` from `<source>`
- <feature-2>: ...
Prefer ARIA roles, `data-*` attributes, routes, and prompt strings; never coordinates or tab order.

## Evidence

Every drive takes the real user path (no internal setters, no test-only endpoints) and records both the action and the resulting state: <stdout + stderr + exit code | response status + body | ARIA snapshot + screenshot before and after>. Side effects (files written, rows changed, messages sent) are confirmed through a second, read-only view. Artifacts go under `${VETDD_ARTIFACTS:-.vetdd/artifacts}/<feature>/<timestamp>/` and their paths are printed on stdout. Exit 0 = expectation observed, 1 = observed and not met, 2 = could not observe (infrastructure).

## Cleanup

`scripts/cleanup.sh` kills only the PID launch recorded, removes `.vetdd/run/<app>.pid`, and never touches `.vetdd/artifacts/`.

## Helpers

- `scripts/doctor.sh`
- `scripts/verify-<feature>.sh`
- `scripts/cleanup.sh`
All executable. Run them from the repository root.

## Feature map

`features/README.md` and one file per feature. Read the README first; it holds the baseline preconditions and how to report proof or a skip.
````

Checklist before handing the skill over (verify mode step A.4):

- [ ] Launch → Doctor → one Drive with `--expect <wrong>` → `target_failure` recorded through `evidence.sh`
- [ ] the same Drive with the agreed expectation → `pass` recorded
- [ ] Cleanup ran, and the artifact paths printed by the drive still exist
- [ ] every command and selector in Drive was copied from the repo, not invented
