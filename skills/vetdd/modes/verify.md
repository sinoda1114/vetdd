# verify mode

Oracle: a project-local verify skill that drives the real surface (CLI, HTTP, UI) the way a user would and exits non-zero when the agreed behavior is not observed. Governing principles: 1, 2, 3, 5, 6. Sources: pstack `create-verification-skill` and `maintain-verification-skill`, adapted to record through `$VETDD/scripts/evidence.sh`.

Use it when the agreed behavior lives on a surface a unit test cannot reach, or when a change is exempt from unit tests (config, wiring, glue, type annotations) and still needs a judge. It runs after test mode when a task needs both.

## The verify skill

Lives in the target project at `.claude/skills/verify-<app>/`:

```
SKILL.md                 Launch / Doctor / Drive / Evidence / Cleanup / Helpers (references/verify-skill-template.md)
features/README.md       baseline preconditions, driving conventions, proof and skip reporting
features/<feature>.md    one per feature, the product's main features, at most 5 (references/feature-map-template.md)
scripts/verify-<feature>.sh   executable; drives one feature; exit 0 = observed, 1 = not observed, 2 = could not observe
scripts/doctor.sh        read-only; exit 0 = this instance is worth driving
scripts/cleanup.sh       kills only what launch started; never deletes artifacts
```

Every `verify-<feature>.sh` accepts `--expect <literal>` so its expectation can be overridden for calibration, writes its artifacts (screenshots, response bodies, stdout, exit codes) under `${VETDD_ARTIFACTS:-.vetdd/artifacts}/<feature>/<timestamp>/`, and prints those paths on stdout. Exit 2 means the script could not observe the surface (a missing tool, a usage error), which principle 2 says is never red. `evidence.sh` runs the script itself and cannot see the exit code in advance, so every verify run declares it: `"$VETDD/scripts/evidence.sh" <slice> <kind> --infra-exit 2 ... -- scripts/verify-<feature>.sh`. Without `--infra-exit 2`, exit 2 would be recorded as `target_failure`.

## Procedure

### A. Generate the skill (once per project, or when none fits)

1. **Ask the repo, not the human.** Read package manifests, run scripts, Dockerfiles, CI, existing e2e or harness code. Determine: Surface (UI / CLI / TUI / HTTP / library), Run (the repo's own dev command, port, env, seed, auth), Drive (an existing harness first; otherwise Playwright or the Browser pane for web, a PTY for CLI/TUI, curl for HTTP), Observe (screenshot, ARIA snapshot, response body, stdout/stderr/exit code, log line, DB row), Isolate (can two instances run side by side; if not, say so and never drive a shared instance). If the checkout does not build, fix that first or end `blocked`.
2. **Agree** (principle 1a) on which features the map covers (the main ones, at most 5; a small CLI may have two), the expected value and its source for each, and the run conditions (port, env, fixture data). Present the feature list through `AskUserQuestion` in the seam-proposal format (what each feature's script catches, misses, costs).
3. **Write the skill** from `references/verify-skill-template.md` and the feature files from `references/feature-map-template.md`. Selectors and commands must exist in the repo; prefer ARIA roles, `data-*` attributes, route paths, and prompt strings over coordinates and tab order.
4. **Calibrate** (principle 2). For one mapped feature: run `doctor.sh`, then `verify-<feature>.sh --expect <wrong literal>` through `evidence.sh <app>-verify calibration --infra-exit 2 --oracle-version 1` with every verify script of the map and each file of their shared library as `--oracle-file` (must end `target_failure`; this names the slice's oracle, as B below expects), then `verify-<feature>.sh` with the agreed expectation through `evidence.sh <app>-verify calibration` (must end `pass`), then `cleanup.sh`, then confirm the artifact paths printed still exist. A generated skill that was never executed is a draft, not a deliverable, and a cleanup that deletes the proof fails this step.
5. Hand over: the skill directory is committed with the project. Tell the human `verify-<app>` exists and how to run one feature.

### B. Use the skill as the oracle for a change

The slice's oracle is the set of verify scripts the agreement names (every `verify-<feature>.sh` it covers, plus each file of the shared library they source; `--oracle-file` takes files, not directories): pass all of them with `--oracle-file` on the first run and let later runs inherit them, whichever feature a run drives. Naming only the driven feature's script makes each run a different oracle, and check-evidence rule 8 then fails the slice. A feature that must be judged on its own gets its own slice (`<app>-verify-<feature>`).

1. Record `before` for each feature the change touches: for a defect, `verify-<feature>.sh` must end `target_failure`; for an exempt or behavior-preserving change, the calibration red from A.4 counts only if it named the same oracle files and version as the runs you record now; otherwise record a fresh one with `--expect <wrong>` under a new `--oracle-version`, recorded first with `"$VETDD/scripts/oracle-version.sh" <app>-verify --version <new> --change implementation --reason-file .vetdd/notes/<name>` (check-evidence rule 8d wants the entry before the red, once the slice has a log). Then record the current green as `after` so the pre-change state is on file.
2. Make the change.
3. Record `after` for every touched feature and for every feature the agreement said must stay green. All must end `pass`. Artifacts land under `.vetdd/artifacts/`, referenced from the logs.
   **Audits**, after the last `after` (principle 2: an oracle is trusted only once it has gone red on a targeted defect). Verify mode has no import to stub, so it runs what it can:
   - **Mutation.** When the script starts the program itself (a CLI, a script that launches the server for each run), run StrykerJS with its command runner, which runs one shell command per mutant in a sandbox copy of the project and reads only its exit code (0 = survived, anything else = killed). Give it a small wrapper in the skill's `scripts/` that runs the feature script and turns its exit 2 into 0, so a run that could not observe counts as survived (the audit then fails and you look, instead of passing on runs that saw nothing). A mutant whose run outlasts Stryker's time limit is reported as `Timeout` and counted as caught, though the script may have observed nothing: give Stryker a `timeoutMS` well above the script's own wait for the app, and read the log of every timed-out mutant. Write the wrapper and the Stryker config before step 1 and name the wrapper with the verify scripts as `--oracle-file` on the slice's first run (it decides what counts as caught); made after the last green, they change the tree and rule 5 fails. The config: `"testRunner": "command"`, `"commandRunner": {"command": "sh .claude/skills/verify-<app>/scripts/<wrapper>"}` (relative to the project root, which is the sandbox's root; an absolute path runs the original, unmutated tree), `"coverageAnalysis": "off"`, `"concurrency": 1` when the script launches a server on a fixed port (sandboxes run side by side), and the reporters of test mode "Audits" › "Mutation". Record it with `evidence.sh <app>-verify calibration --audit mutation --mutation-report stryker-json:<its jsonReporter.fileName> -- npx --no-install stryker run <that config> --mutate '<file>:<first>-<last>,...'` on the changed lines; check-evidence rule 10c then judges it as in test mode. Every mutant runs the whole script (measured on ts-kata under load: a CLI verify script over all of `dueDate.ts`, 90 mutants, 47 killed and 43 survived in about 50 seconds), so keep the ranges to the change. A script that connects to a server already running keeps exercising the unmutated code: do not use the command runner there.
   - **Planted defect.** When the mutation audit cannot run, agree one defect in the changed lines with the human (principle 1a: what is broken and which feature must catch it). Plant it with `calibrate.sh plant <app>-verify --file <product file> --oracle-file <the slice's oracle files>` (every file B names: the verify scripts and their shared library, and the wrapper when there is one) and make the edit; restart the app so it serves the planted code and check `doctor.sh` exits 0; then run `calibrate.sh planted <app>-verify --oracle-file <the slice's oracle files> --infra-exit 2 -- <script>`. It must end `target_failure`, and its log must show the agreed value mismatched, not a connection error; it puts the product files back, so restart the app once more. Then record why the mutation audit did not apply, naming the planted run, with `audit-note.sh <app>-verify --kind mutation --not-applicable --reason-file <path>`.
   - **Dead surface**, last, for a script that connects to an app already running (one that starts the program itself is covered by the mutation audit). Stop the app (`cleanup.sh`), then run one `verify-<feature>.sh` with the app stopped through `evidence.sh <app>-verify calibration --infra-exit 2 -- <script>`. It must not end `pass`; a pass means the script reads something other than the live app (a cached artifact, a fixture, a mock).
   - **Undefined imports** do not apply: the oracle drives the running app, not an import. Record why once per slice with `"$VETDD/scripts/audit-note.sh" <app>-verify --kind undefined-imports --not-applicable --reason-file <path>` (one line in a file under `.vetdd/notes/`, as for `oracle-version.sh`).
   Rule 10c takes only a mutation run recorded after the slice's last green run: when SKILL.md step 5 records the slice again, run the mutation audit again after the final `integrated` runs. An eval of a skill or prompt has no evidence slice; its audits are in `modes/eval.md` "Audits".
4. `$VETDD/scripts/check-evidence.sh <app>-verify` on the delivered tree.
5. Judge: `$VETDD/scripts/judge.sh` with `artifact/` = the diff plus the artifact paths, `evidence/` = the slice's evidence, rubric = `references/final-judge-rubric.md`, in the directory its "Layout" defines (build it with `$VETDD/scripts/judge-layout.sh`, as test mode's Close step 4 does) (the verify artifacts' paths go in the reply draft, each with the URL or command line it shows, so the judge can check the agreed surface was driven and not a mock or an internal setter). If the judge cannot run (the script fails, the judge's CLI is not logged in, the service fails), end `blocked` with all evidence and say the separate verdict is the only missing step (principle 8).
6. Reply per `references/reply-format.md`; each feature maps to its artifact paths.

### C. Maintain the skill (when the map may have drifted)

Result is one of `clean` (nothing changed), `changed` (proven fixes to the skill directory only), `blocked` (what stopped the pass). Never edit product code during a maintenance pass.

1. Source wave: one read-only subagent per feature file (brief from `references/subagent-brief.md`; model `$VETDD/scripts/models.sh explorer`), returning `summary / source entry points / drift or none / one recipe`. Subagents do not drive the app.
2. Reconcile: merge recipes, spot-check drift, look for surfaces added since the map was written (a concrete source path is required to claim one).
3. Live pass, required even when source looks clean: the parent alone drives; never drive an instance that has not passed `doctor.sh` since the last surprise; artifacts survive every cleanup; nothing a drive launched outlives that drive. `verified-unreachable` needs the exact command tried and the unmet precondition.
4. Triage each finding as doc drift (fix the map), harness gap (fix the script), or product gap (report, do not fix).
5. Ship the skill changes as one commit, or stop with `blocked`.

## Traps

- Driving through an internal setter, a test-only endpoint, or a mock instead of the user's path. Mock only where production itself isolates an external boundary.
- Trusting a dry-run flag by its name. Observe what it skips.
- Killing by process name. Kill only the PID launch recorded.
- Reporting a substitute check as verified. If the mapped path was unreachable, say so with the command and the missing precondition.
