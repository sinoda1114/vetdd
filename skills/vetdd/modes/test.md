# test mode

Oracle: a failing test at the agreed seam. Governing principles: 1, 2, 3, 4, 6, 7. Read `references/test-quality.md` before writing any test.

`$VETDD` is this skill's base directory (see SKILL.md step 0). Every script below is called as `$VETDD/scripts/<name>` and run from the target project's root. The Bash tool keeps no variables between calls: start each command with `VETDD='<absolute path>' &&` (single quotes: the path may contain spaces), or write the absolute path in place of `$VETDD`.

Work in vertical slices: one test → the smallest change that passes it → next test. Each slice has its own slice id (`<topic>-<n>`) and its own evidence directory.

## Per slice

1. **Propose the seam** (once per task, in step 2 of SKILL.md) using `references/seam-proposal.md`. No test is written at a seam the human did not agree to.
2. **Write the test.** One test, one behavior, expected value from the agreed source. Check it against the five hollow shapes in `references/test-quality.md`. Give each slice its own test file where the project allows it: the slice's oracle is that file's hash, so a later slice that adds a test to a shared file changes the earlier slice's oracle, and check-evidence rule 8 then asks for a new version and a new red for it.
3. **Record `before`.**
   ```
   "$VETDD/scripts/evidence.sh" <slice> before --seam '<seam>' --oracle-version 1 \
     --oracle-file <test file> -- <test command for this slice>
   ```
   It must end `target_failure` for the intended reason (read the log: the assertion on the agreed behavior failed, not a syntax error, not a missing module you forgot to import). If it passed, the test observes nothing; fix the test, not the product. If it failed for another reason, fix that first and record again. When the command uses a name filter, the log must show the targeted test ran (for vitest, a count such as `1 failed`); a filter that matches nothing can exit either way without running anything.
   For a defect, also prove the oracle is not always red before changing the product: run the same command on a known-good case at the same seam (a passing test in the same file, selected with the runner's name filter, or the new test's function called with an input the spec says is already handled) and record it as `calibration`; it must end `pass`. Principle 2 needs both halves before the fix. Put the known-good case in the test file before the `before` run: adding it afterwards changes the slice's oracle, and check-evidence rule 8 then asks for a new version and a new red.
   When one fix will cover several slices, write every slice's test and record every slice's `before` first; the later slices would otherwise never go red. Write all of those tests before the first `before` run when they share a file: adding a test to the file after a slice's `before` changes that slice's oracle, and check-evidence rule 8 then fails it. This is the one exception to vertical slicing, and it applies only to slices that share one fix. Run one slice at a time with the runner's name filter (vitest `-t "<test name>"`, jest `-t`, pytest `-k`).
   To record the runner's passed, failed, skipped, and todo counts, add `--test-report jest-json:<path under .vetdd/reports/>` and have vitest or jest write its JSON report there: vitest `... --test-report jest-json:.vetdd/reports/<slice>.json -- npx vitest run --reporter=default --reporter=json --outputFile.json=.vetdd/reports/<slice>.json`, jest `... -- npx jest --json --outputFile=.vetdd/reports/<slice>.json`. Both paths are relative to the current directory (from a package directory, use `../.vetdd/reports/<slice>.json` or an absolute path; vitest resolves its own against its config `root`; pass an absolute path when that differs), and one path per slice keeps runs from reading each other's report. The counts never change the outcome; tests left out by a name filter count as skipped. `check-evidence.sh` rule 9b fails a test that ran (passed or failed) in an earlier run of the same command and is skipped or todo in the latest one. The skipped and todo counts of the latest green, and a latest green with no report when an earlier run recorded one (give the `integrated` runs the same `--test-report`), are `WARN (9c: ...)` lines: they never fail the slice, but each goes into the reply's Attention.
   Leave no `.only` (or `fdescribe`) in a JS or TS oracle file: it makes the runner skip every other test, and `check-evidence.sh` rule 9a fails the slice. Rule 9a is a tripwire for that accident, not a boundary: a renamed or wrapped focus, `fit(`, and files not named with `--oracle-file` pass it. Do not name a generated or minified file as an oracle file: a line over 20000 characters cannot be scanned and fails the slice.
4. **Make it green with the smallest change.** No speculative generality, no second behavior, no cleanup yet. Do not weaken or edit the test to match the implementation.
5. **Record `after`** with the same command. It must end `pass`.
6. **Run the coverage oracles** the agreement named (the full suite, the type check) and record them as `after` on the same slice, without `--oracle-file` and `--oracle-version` so the slice keeps its own oracle binding. They must pass. If a coverage oracle fails, the slice is not done.
7. Next slice. The next slice's change makes this slice's `after` stale; that is expected, and the Close step records every slice again on the final tree.

## Calibration red without losing work

vetdd does not commit while it works, so the fix lives only in the working tree. Never `git checkout`, `git restore`, or `git stash` to get the pre-fix state. Use `calibrate.sh`, which parks the fix (staged, unstaged, and newly created files) in `<git dir>/vetdd-calib/<slice>/`, runs the oracle through `evidence.sh <slice> calibration`, and puts the fix back byte for byte. The parked state survives a killed run, and its path is the first line printed.

Defect or new behavior, with the fix already in the working tree:

```
VETDD='<absolute path>' && "$VETDD/scripts/calibrate.sh" unfix <slice> --file <product file> [--file ...] \
  --seam '<seam>' --oracle-version <n> --oracle-file <test file> -- <test command>
```

Behavior-preserving change (refactor, config, wiring, glue), where there is no defect to put back:

```
VETDD='<absolute path>' && "$VETDD/scripts/calibrate.sh" plant <slice> --file <file> --oracle-file <test file>
<edit <file>: one minimal mutation the oracle covers, e.g. flip a comparison>
VETDD='<absolute path>' && "$VETDD/scripts/calibrate.sh" planted <slice> \
  --seam '<seam>' --oracle-version <n> --oracle-file <test file> -- <test command>
```

- Run it from the directory the test command runs in; paths are relative to it. `--file` and `--oracle-file` take regular files (no directories, no symlinks), compared by real path. The oracle is required and is never parked: a red on reverted tests proves "old tests", not "the defect is back". `planted` refuses if the oracle or any file outside the saved set changed since `plant` (content or executable bit), or if nothing was planted. Files ignored by git are not covered by that check: if the oracle reads any, name them with `--oracle-file`.
- `calibrate.sh` exits 0 only when the calibration ended `target_failure`, and 1 when it did not (the oracle does not see the defect: fix the test). Exit 0 is necessary, not sufficient: read the calibration log and confirm the red comes from the agreed assertion. A red from an import error (for example because a new module was parked), "no tests", a syntax error, or a crash of the runner is not a calibration; fix the setup and run it again. Then record the oracle as `after`; for a behavior-preserving change, record `after` before the change and again after it.
- The known-good `calibration` pass in step 3 is recorded with `evidence.sh` directly; `calibrate.sh` is only for the red half.
- Give the Bash call a timeout longer than the suite. If a calibration was interrupted anyway, the next `calibrate.sh` for that slice refuses to start; run `"$VETDD/scripts/calibrate.sh" restore <slice>` before anything else.

## After all slices are green: refactor by a separate agent

Refactoring is not part of the loop, and the author does not do it (both source projects observed that authors skip it or drift). Spawn a refactorer:

- model: `"$VETDD/scripts/models.sh" refactorer`
- brief: `references/subagent-brief.md` with Task = "refactor the changed code for clarity; behavior must not change; run only the listed oracle", Scope = the files changed in this task except every slice's oracle files (the tests stay as they are: an edited test changes that slice's oracle, and check-evidence rule 8 fails it), Oracle = the full test command, Record = "record only `after`; do not record `before`".
- Before spawning, record a `calibration` red for the refactor slice (`<topic>-refactor`) with `calibrate.sh plant` and `planted`, so the suite is proven red-capable on this tree, then record the full suite as `after` on that slice so the pre-refactor green is on file.

Read the refactorer's diff yourself. Reject any change that alters an assertion, deletes a test, or adds behavior. If a test file has to change after all, bump `--oracle-version` for every slice whose oracle it is, record each bump with `oracle-version.sh` (`--change implementation --reason-file <path>`), and record a red for each new version before its green (`calibrate.sh plant` and `planted` for the refactor slice, `unfix` for the others). If the refactorer finds nothing to change, it says so and records the `after` run anyway; an empty refactor is a valid result.

## Close (see SKILL.md step 5)

1. **Record every slice again on the final tree.** For each slice id, including the refactor slice, run its own test command and every coverage oracle as `integrated`:
   ```
   "$VETDD/scripts/evidence.sh" <slice> integrated [--test-report jest-json:<the slice's report path>, when its earlier runs recorded one] -- <test command for this slice>
   ```
   Leave out `--oracle-version` and `--oracle-file`: the run keeps the slice's oracle, and naming another set or an earlier version fails check-evidence rule 8. All must end `pass`. Earlier `after` runs stay as history; only this last record has to match the delivered tree.
2. `"$VETDD/scripts/check-evidence.sh" <every slice id>` on the delivered tree, with no edits in between. Quote the output.
3. Judge: build the directory that `references/final-judge-rubric.md` "Layout" defines (diff, reply draft, `check-evidence.sh` output, oracle files, each slice's `meta.json` and red-run log) and run `"$VETDD/scripts/judge.sh"` on it with that file as the rubric. Only what the layout names leaves the machine; other run logs stay local. The judge's verdict goes in the reply as is. If the judge cannot run (the script is missing, the judge's CLI is not logged in, the service fails), end the task `blocked` with all evidence and say the separate verdict is the only missing step (principle 8). Never report done without it.
4. Reply in `references/reply-format.md`.

## Traps this mode guards against

- Reading the code to form a theory before a red command exists. If you catch yourself doing this, stop and go to step 2.
- A `before` that fails because the module does not exist yet, when the agreed behavior is a change to an existing module. That red is about the wrong thing.
- Changing a test after its green. That changes the oracle, and `check-evidence.sh` rule 8 fails the slice. Before the green, rule 8 accepts an edited test under the same version as long as a new red is recorded with it (that is how a syntax error in a new test gets fixed); going back to an earlier content of the file after that needs a new version, but bump the version anyway when the edit changes what the test checks, so the record says the oracle changed: every run records the oracle's version and file hashes, and the final green needs a red with the same oracle before it. Bump `--oracle-version` and record why with `"$VETDD/scripts/oracle-version.sh" <slice> --version <new> --change implementation --reason-file <path>`; when the meaning of the agreed behavior changed, use `--change meaning` plus the new agreement (`--agreement-via AskUserQuestion --question-file <path> --answer-file <path>`, asked through `AskUserQuestion` as in step 2 of SKILL.md; principle 1a). Record it before the new version's red: rule 8d wants the entry first. Then run `calibrate.sh unfix` for the new version (it takes the fix out, records the red, and puts the fix back), then record `after`. A weakening that stops the recorded test command going red fails this way, because its calibration never goes red; rule 8 is a tripwire, not a boundary, and it misses a weakening that still goes red, a red recorded from another command, and helpers or fixtures not named with `--oracle-file`. A slice recorded before rule 8 existed may name a file in another letter case than the one on disk; the next run that names `--oracle-file` records the on-disk spelling (ASCII letter case only), which rule 8 reads as a changed oracle, so bump the version and record a red for it once. Never touch `.vetdd/` by hand.
- "Tests pass" as the final claim. The final claim is the `check-evidence.sh` output plus the judge's verdict.
