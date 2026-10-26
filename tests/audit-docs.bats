#!/usr/bin/env bats
# PR8: the audits verify and eval modes can run (owner decision 2026-10-03: in modes with nothing to
# plant a defect into, as far as each can). Docs only; the measured facts behind them are in the PR.

load test_helper

VERIFY="$BATS_TEST_DIRNAME/../skills/vetdd/modes/verify.md"
EVAL="$BATS_TEST_DIRNAME/../skills/vetdd/modes/eval.md"

@test "verify mode has an Audits step: a dead surface must not pass" {
  sed -n '/^### B\./,/^### C\./p' "$VERIFY" | grep -q 'Dead surface'
  grep -q 'with the app stopped' "$VERIFY"
  grep -q 'must not end `pass`' "$VERIFY"
}

@test "verify mode runs the mutation audit through Stryker's command runner when the script starts the program itself" {
  grep -q '"testRunner": "command"' "$VERIFY"
  grep -q 'commandRunner' "$VERIFY"
  grep -q -- '--audit mutation' "$VERIFY"
  # A server the script only connects to keeps serving the unmutated code.
  grep -q 'connects to a server' "$VERIFY"
}

@test "verify mode plants one agreed defect with calibrate.sh plant when Stryker cannot run" {
  grep -q 'calibrate.sh plant' "$VERIFY"
  grep -q 'calibrate.sh planted' "$VERIFY"
  grep -q 'principle 1a' "$VERIFY"
  grep -q -- '--kind mutation --not-applicable' "$VERIFY"
}

@test "verify mode still records why the undefined-imports audit does not apply" {
  grep -q -- '--kind undefined-imports --not-applicable' "$VERIFY"
}

@test "verify mode asks the judge to check the artifacts show the agreed surface was driven" {
  grep -q 'agreed surface' "$VERIFY"
}

@test "eval mode has an Audits section: an empty candidate and a label swap in the rubric calibration" {
  grep -q '^## Audits' "$EVAL"
  sed -n '/^## Audits/,/^## /p' "$EVAL" | grep -q 'empty'
  sed -n '/^## Audits/,/^## /p' "$EVAL" | grep -q 'swap'
  # The rubric calibration step points to it.
  grep -q '^2\. \*\*Calibrate the rubric\*\*.*Audits' "$EVAL"
}

@test "eval mode pins the rubric by its sha256 in synthesis.md, so a change after a result shows" {
  sed -n '/^## Audits/,/^## /p' "$EVAL" | grep -q 'sha256'
}

# --- review round 1 ------------------------------------------------------------------------------

@test "the planted defect restarts the app on the planted code and checks the doctor, and the log shows a mismatch (M2)" {
  local p; p="$(grep 'Planted defect' "$VERIFY")"
  [[ "$p" == *"restart the app"* ]]
  [[ "$p" == *"doctor.sh"* ]]
  [[ "$p" == *"not a connection error"* ]]
}

@test "the dead surface audit is for a script that connects to a running app, and runs last (M2)" {
  local d; d="$(grep 'Dead surface' "$VERIFY")"
  [[ "$d" == *"connects to an app already running"* ]]
  [[ "$d" == *"last"* ]]
}

@test "the command runner: exit 2 counted as survived, one at a time on a fixed port, a path relative to the project root (M3, M4)" {
  local m; m="$(grep -- '- \*\*Mutation\.\*\*' "$VERIFY")"
  [[ "$m" == *"turns its exit 2 into 0"* ]]
  [[ "$m" == *'"concurrency": 1'* ]]
  [[ "$m" == *"sh .claude/skills/verify-<app>/scripts/"* ]]
  [[ "$m" == *"an absolute path runs the original"* ]]
}

@test "index.tsv has a rubric_sha256 column, and the Audits name the run's copy of the rubric (M5)" {
  grep -q 'index.tsv .*promoted  rubric_sha256' "$EVAL"
  sed -n '/^## Audits/,/^## /p' "$EVAL" | grep -q 'runs/<run-id>/rubric.md'
}

@test "#102: the rubric pin copies rubric_sha256 from judge.json.meta.json and checks the run's copy against it" {
  local pin layout
  pin="$(grep -- '- \*\*Rubric pin\.\*\*' "$EVAL")"
  [[ "$pin" == *'`rubric_sha256` in `judge.json.meta.json`'* ]]
  [[ "$pin" == *'in `synthesis.md` and in the `rubric_sha256` column of its `index.tsv` line'* ]]
  [[ "$pin" == *'`runs/<run-id>/rubric.md`'* ]]
  [[ "$pin" == *"changed after the judge graded it, or was not the file passed as \`--rubric\`"* ]]
  # A meta file from before the field: the run's copy, as before.
  [[ "$pin" == *"has no \`rubric_sha256\`"* ]]
  # judge.sh exit 8 writes no meta file and prints the sha256 instead.
  [[ "$pin" == *"exit 8"* ]]
  layout="$(grep '^      judge.json.meta.json ' "$EVAL")"
  [[ "$layout" == *"rubric_sha256"* ]]
}

# --- review round 2 ------------------------------------------------------------------------------

@test "the mutation item says a timed-out mutant counts as caught and must be read, and Stryker gets more time than the script (N1)" {
  local m; m="$(grep -- '- \*\*Mutation\.\*\*' "$VERIFY")"
  [[ "$m" == *"Timeout"* ]]
  [[ "$m" == *"timeoutMS"* ]]
  [[ "$m" != *"never as killed"* ]]
}

@test "the planted defect names the slice's oracle files, not only the verify scripts (N2)" {
  local p; p="$(grep 'Planted defect' "$VERIFY")"
  [[ "$p" == *"the slice's oracle files"* ]]
  [[ "$p" != *"<the verify scripts>"* ]]
}

@test "the wrapper and the Stryker config are made before the first run and named as oracle files; the audits are run again after the final integrated runs (N4, N5)" {
  local m; m="$(grep -- '- \*\*Mutation\.\*\*' "$VERIFY")"
  [[ "$m" == *"before step 1"* ]]
  [[ "$m" == *"--oracle-file"* ]]
  sed -n '/^### B\./,/^### C\./p' "$VERIFY" | grep -q 'after the final `integrated`'
}

@test "the label swap is graded under its own run id, so the first grading is kept" {
  sed -n '/^## Audits/,/^## /p' "$EVAL" | grep -q -- '-swap'
}

@test "calibrate.sh names --infra-exit in its usage and in the unknown-option message (N3), and --test-report there too (#5)" {
  grep -q 'unknown option: $1 (--file, --oracle-file, --seam, --oracle-version, --infra-exit, --test-report)' "$SCRIPTS/calibrate.sh"
  sed -n 13,14p "$SCRIPTS/calibrate.sh" | grep -q -- '--infra-exit'
}

@test "verify mode takes the mutation ranges from mutate-ranges.sh, not by hand (#71)" {
  local m; m="$(grep -- '- \*\*Mutation\.\*\*' "$VERIFY")"
  [[ "$m" == *'mutate-ranges.sh" <app>-verify'* ]] || { echo "$m"; false; }
  [[ "$m" != *"on the changed lines"* ]] || { echo "$m"; false; }
  [[ "$m" == *'--mutate "$r"'* ]] || { echo "$m"; false; }
  # B.1: the pre-change green is for an exempt or behavior-preserving change only (review r4).
  local b; b="$(grep -- '^1\. Record `before` for each feature' "$VERIFY")"
  [[ "$b" == *'after a defect'*'record no `after` before the change'* ]] || { echo "$b"; false; }
}
