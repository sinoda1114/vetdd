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

@test "index.tsv has a rubric_sha256 column, of the run's copy of the rubric (M5)" {
  grep -q 'index.tsv .*promoted  rubric_sha256' "$EVAL"
  grep -q 'runs/<run-id>/rubric.md`, in `synthesis.md` and in the `rubric_sha256` column' "$EVAL"
}
