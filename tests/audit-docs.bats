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
  sed -n '/^## Procedure/,/^## Regression/p' "$EVAL" | grep -q 'Audits'
}

@test "eval mode pins the rubric by its sha256 in synthesis.md, so a change after a result shows" {
  sed -n '/^## Audits/,/^## /p' "$EVAL" | grep -q 'sha256'
}
