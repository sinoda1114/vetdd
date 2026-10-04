#!/usr/bin/env bats
# check-evidence rule 9b (FAIL): a test that ran (passed or failed) in an earlier run and is skipped or
# todo in the latest run of the same command, read from the normalized copies of the runner's report
# (evidence.sh --test-report). Rule 9c (WARN, never changes the exit code): skipped and todo counts of
# the latest green, and a latest green without a report when another run of the slice recorded one.
# Tripwires, not boundaries: a test that disappears, a changed command, and a slice that never asks
# for a report all pass.
# Real vitest 5.0.1 reports are in tests/fixtures/reports; variants are made by editing copies with jq.

load test_helper

setup() {
  make_repo
  FIX="$BATS_TEST_DIRNAME/fixtures/reports"
  PASS="$FIX/vitest5-pass.json"
  R=.vetdd/reports/r.json
  F1="/work/ts-kata/src/dueDate.test.ts"
  T1="closingDate closes on the 20th of the same month when invoiced before the cutoff"
  T2="closingDate closes on the 20th of the next month when invoiced after the cutoff"
  # The fake runner: copies $REPORT (when set) to the report path and exits with $EXIT.
  printf 'mkdir -p .vetdd/reports\n[ -z "${REPORT:-}" ] || cp "$REPORT" .vetdd/reports/r.json\nexit "${EXIT:-0}"\n' > runner.sh
}

# status_of <out-name> <test name> <status> [<base>]: a copy of the base report (default: the all-pass
# one) with that test's status replaced; prints its path.
status_of() {
  jq --arg n "$2" --arg s "$3" '(.testResults[].assertionResults[] | select(.fullName == $n) | .status) = $s' \
    "${4:-$PASS}" > "$BATS_TEST_TMPDIR/$1.json"
  printf '%s' "$BATS_TEST_TMPDIR/$1.json"
}

# rec <kind> <report or -> <exit code> [extra command words]: record `sh runner.sh` as <kind> with a
# test report. A report of - means the runner writes none.
rec() {
  local kind="$1" rep="$2" code="$3"; shift 3
  if [ "$rep" = - ]; then rep=""; fi
  REPORT="$rep" EXIT="$code" ev s1 "$kind" --oracle-version v1 --oracle-file test.sh \
    --test-report "jest-json:$R" -- sh runner.sh "$@" >/dev/null 2>&1 || true
}

# A slice with a red (run 1, kind before) and a green (run 2, kind after), each with its report.
two_runs() { rec before "$1" 1; rec after "$2" 0; }

COPY1() { printf '%s' "$REPO/.vetdd/evidence/s1/runs/001-before.tests.json"; }

@test "rule 9b fails a test that passed and is skipped later, naming file, test, and both runs" {
  two_runs "$PASS" "$(status_of skip "$T1" skipped)"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (9b: "* ]]
  [[ "$output" == *"$T1"* ]]
  [[ "$output" == *"$F1"* ]]
  [[ "$output" == *"run 1"* ]]
  [[ "$output" == *"run 2"* ]]
  [[ "$output" == *"passed"* ]]
  [[ "$output" == *"skipped"* ]]
}

@test "rule 9b fails a test that passed and is todo later" {
  two_runs "$PASS" "$(status_of todo "$T1" todo)"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (9b: "*"$T1"*"todo"* ]]
}

@test "rule 9b fails a test that failed and is skipped later" {
  two_runs "$(status_of failed "$T1" failed)" "$(status_of skip "$T1" skipped)"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (9b: "*"$T1"*"failed"*"skipped"* ]]
}

@test "rule 9b treats pending and disabled as skipped, as the counts do" {
  two_runs "$PASS" "$(status_of pend "$T1" pending)"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9b: "*"$T1"* ]]
}

@test "rule 9b passes a test skipped in both runs, and the skip still warns (9c)" {
  two_runs "$(status_of skip1 "$T1" skipped)" "$(status_of skip2 "$T1" skipped)"
  run check s1
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "s1: OK" ]
  [[ "$output" != *"FAIL"* ]]
  [[ "$output" == *"s1: WARN (9c: "* ]]
}

@test "rule 9b passes a test that passed in both runs, with no line but OK" {
  two_runs "$PASS" "$PASS"
  run check s1
  [ "$status" -eq 0 ]
  [ "$output" = "s1: OK" ]
}

@test "rule 9b compares only the latest run of a command: a test restored later passes" {
  # T2 is skipped throughout, so the latest run has a 9c warning that the old script cannot print.
  local base; base="$(status_of base "$T2" skipped)"
  rec before "$base" 1
  rec after "$(status_of skip "$T1" skipped "$base")" 0
  rec integrated "$base" 0
  run check s1
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "s1: OK" ]
  [[ "$output" != *"9b"* ]]
  [[ "${lines[1]}" == "s1: WARN (9c: 1 skipped and 0 todo"* ]]
}

@test "rule 9b does not compare runs of different commands (a name filter)" {
  rec before "$PASS" 1
  rec after "$(status_of skip "$T1" skipped)" 0 -t filter
  run check s1
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "s1: OK" ]
  [[ "$output" != *"9b"* ]]
  # The skip is still counted, by 9c.
  [[ "$output" == *"s1: WARN (9c: "* ]]
}

@test "rule 9b compares each command with its own earlier runs" {
  rec before "$PASS" 1 -t a
  rec calibration "$(status_of skipx "$T2" skipped)" 0 -t b
  rec after "$(status_of skip "$T1" skipped)" 0 -t a
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9b: "*"$T1"*"run 1"*"run 3"* ]]
  [[ "$output" != *"$T2"* ]]
}

@test "rule 9b does not fail a test that disappears (a blind spot the header names)" {
  jq '.numTotalTests -= 1 | del(.testResults[0].assertionResults[0])' "$PASS" > "$BATS_TEST_TMPDIR/gone.json"
  two_runs "$PASS" "$BATS_TEST_TMPDIR/gone.json"
  run check s1
  [ "$status" -eq 0 ]
  [ "$output" = "s1: OK" ]
}

@test "rule 9b skips a run without a usable report, silently (9c warns that the green has none)" {
  rec before "$PASS" 1
  rec after - 0
  run check s1
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "s1: OK" ]
  [[ "$output" != *"9b"* ]]
  [[ "$output" == *"s1: WARN (9c: "* ]]
  rm -rf .vetdd
  rec before "$PASS" 1
  printf '{not json' > "$BATS_TEST_TMPDIR/bad.json"
  rec after "$BATS_TEST_TMPDIR/bad.json" 0
  run check s1
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "s1: OK" ]
  [[ "$output" != *"9b"* ]]
}

@test "rule 9b skips a rejected run (accepted false)" {
  local base; base="$(status_of base "$T2" todo)"
  rec before "$base" 1
  rec after "$(status_of skip "$T1" skipped "$base")" 1
  rec after "$base" 0
  [ "$(mq s1 '.runs[1].accepted')" = "false" ]
  run check s1
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "s1: OK" ]
  [[ "$output" != *"9b"* ]]
  [[ "${lines[1]}" == "s1: WARN (9c: 0 skipped and 1 todo"*"after run 3"* ]]
}

@test "rule 9b fails when the copy of a run with an ok report is deleted" {
  two_runs "$PASS" "$(status_of skip "$T1" skipped)"
  rm "$(COPY1)"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (9b: could not read the test report copy of run 1"* ]]
}

@test "rule 9b fails when the copy is malformed, with or without a matching sha256" {
  two_runs "$PASS" "$(status_of skip "$T1" skipped)"
  printf '{"tests": 5}' > "$(COPY1)"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9b: could not read the test report copy of run 1"* ]]
  tamper s1 ".runs[0].tests.sha256 = \"$(sha256_of "$(COPY1)")\""
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9b: could not read the test report copy of run 1"* ]]
}

@test "rule 9b fails when a copy was edited to hide a skip (sha256 differs)" {
  two_runs "$PASS" "$(status_of skip "$T1" skipped)"
  jq '(.tests[] | select(.status == "skipped") | .status) = "passed"' \
    "$REPO/.vetdd/evidence/s1/runs/002-after.tests.json" > "$BATS_TEST_TMPDIR/edit.json"
  cp "$BATS_TEST_TMPDIR/edit.json" "$REPO/.vetdd/evidence/s1/runs/002-after.tests.json"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9b: could not read the test report copy of run 2"* ]]
}

@test "rule 9b never opens a copy named by a tampered log path or tests record" {
  local base; base="$(status_of base "$T2" skipped)"
  two_runs "$base" "$base"
  # An outside file that would trip 9b if it were read in place of the real copy of run 2.
  mkdir -p "$BATS_TEST_TMPDIR/outside"
  jq '(.tests[] | select(.status == "passed") | .status) = "skipped"' \
    "$REPO/.vetdd/evidence/s1/runs/002-after.tests.json" > "$BATS_TEST_TMPDIR/outside/002-after.tests.json"
  tamper s1 ".runs[1].log = \"../../../../../$BATS_TEST_TMPDIR/outside/002-after.log\" | .runs[1].tests.path = \"$BATS_TEST_TMPDIR/outside/002-after.tests.json\""
  run check s1
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "s1: OK" ]
  [[ "$output" != *"9b"* ]]
  [[ "${lines[1]}" == "s1: WARN (9c: 1 skipped"* ]]
}

@test "rule 9b never opens a copy through a symbolic link to the runs directory" {
  two_runs "$PASS" "$PASS"
  mv "$REPO/.vetdd/evidence/s1/runs" "$BATS_TEST_TMPDIR/runs-outside"
  ln -s "$BATS_TEST_TMPDIR/runs-outside" "$REPO/.vetdd/evidence/s1/runs"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9b: could not read the test report copy of run 1"* ]]
}

@test "rule 9b never opens a copy that is a symbolic link" {
  two_runs "$PASS" "$PASS"
  mv "$(COPY1)" "$BATS_TEST_TMPDIR/real.tests.json"
  ln -s "$BATS_TEST_TMPDIR/real.tests.json" "$(COPY1)"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9b: could not read the test report copy of run 1"* ]]
}

@test "rule 9b fails, not reads as OK, when the kind or seq of a run with a report is malformed" {
  two_runs "$PASS" "$PASS"
  tamper s1 '.runs[1].kind = "../../x"'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9b: could not read the test report copy of a run whose seq or kind is malformed"* ]]
}

@test "rule 9b output carries no control character, and a name cannot forge a line" {
  local evil=$'evil\x1b[31m\ns1: OK\n\x07rest'
  jq --arg n "$T1" --arg e "$evil" --arg f $'/x/\x1b[2J\nf.test.ts' \
    '(.testResults[0].assertionResults[] | select(.fullName == $n) | .fullName) = $e | .testResults[0].name = $f' \
    "$PASS" > "$BATS_TEST_TMPDIR/evil.json"
  jq '(.testResults[0].assertionResults[0].status) = "skipped"' "$BATS_TEST_TMPDIR/evil.json" > "$BATS_TEST_TMPDIR/evil-skip.json"
  two_runs "$BATS_TEST_TMPDIR/evil.json" "$BATS_TEST_TMPDIR/evil-skip.json"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9b: "* ]]
  [[ "$output" == *"evil"* ]]
  ! printf '%s' "$output" | LC_ALL=C grep -q "$(printf '[\001-\010\013-\037\177]')"
  ! printf '%s\n' "$output" | grep -qx 's1: OK'
}

@test "rule 9b lists at most 5 tests and says how many more" {
  jq '(.testResults[].assertionResults[].status) = "skipped"' "$PASS" > "$BATS_TEST_TMPDIR/all-skip.json"
  two_runs "$PASS" "$BATS_TEST_TMPDIR/all-skip.json"
  run check s1
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c 'FAIL (9b: test ')" -eq 5 ]
  [[ "$output" == *"and 4 more"* ]]
}

@test "rule 9b cuts a long name to 100 characters with ..." {
  local long
  long="$(printf 'x%.0s' $(seq 1 300))"
  jq --arg l "$long" '.testResults[1].assertionResults[0].fullName = $l' "$PASS" > "$BATS_TEST_TMPDIR/long.json"
  jq '(.testResults[1].assertionResults[0].status) = "skipped"' "$BATS_TEST_TMPDIR/long.json" > "$BATS_TEST_TMPDIR/long-skip.json"
  two_runs "$BATS_TEST_TMPDIR/long.json" "$BATS_TEST_TMPDIR/long-skip.json"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"\"$(printf 'x%.0s' $(seq 1 100))...\""* ]]
  [[ "$output" != *"$(printf 'x%.0s' $(seq 1 101))"* ]]
}

@test "rule 9b does not decide pass or fail by what the display filter shows" {
  # A name made only of control characters still fails the slice.
  jq --arg n "$T1" '(.testResults[0].assertionResults[] | select(.fullName == $n) | .fullName) = "\u0001\u0002"' "$PASS" > "$BATS_TEST_TMPDIR/c.json"
  jq '(.testResults[0].assertionResults[0].status) = "skipped"' "$BATS_TEST_TMPDIR/c.json" > "$BATS_TEST_TMPDIR/c-skip.json"
  two_runs "$BATS_TEST_TMPDIR/c.json" "$BATS_TEST_TMPDIR/c-skip.json"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (9b: "* ]]
}

# --- 9c ---

@test "rule 9c warns with the skipped and todo counts of the latest green and keeps the exit code" {
  two_runs "$(status_of mixed "$T2" todo "$(status_of s1 "$T1" skipped)")" "$(status_of mixed2 "$T2" todo "$(status_of s2 "$T1" skipped)")"
  run check s1
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "s1: OK" ]
  [[ "${lines[1]}" == "s1: WARN (9c: "*"1 skipped"*"1 todo"* ]]
  [[ "${lines[1]}" == *"after run 2"* ]]
  [ "${#lines[@]}" -eq 2 ]
}

@test "rule 9c reads the latest green, not an earlier one" {
  rec before "$(status_of skip "$T1" skipped)" 1
  rec after "$(status_of skip "$T1" skipped)" 0
  rec integrated "$(status_of skip "$T1" skipped)" 0
  run check s1
  [[ "$output" == *"integrated run 3"* ]]
  [[ "$output" != *"after run 2"* ]]
}

@test "rule 9c does not warn when the latest green has a report and nothing skipped" {
  two_runs "$(status_of skip "$T1" skipped)" "$PASS"
  run check s1
  [ "$status" -eq 0 ]
  [ "$output" = "s1: OK" ]
}

@test "rule 9c warns when an earlier run recorded a report and the latest green did not" {
  rec before "$PASS" 1
  ev s1 after -- sh runner.sh >/dev/null 2>&1
  [ "$(mq s1 '.runs[1].tests')" = "null" ]
  run check s1
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "s1: OK" ]
  [[ "${lines[1]}" == "s1: WARN (9c: "*"no test report"*"cannot be counted"* ]]
}

@test "rule 9c does not warn a slice that never asked for a report (a blind spot)" {
  record_good_slice s1
  run check s1
  [ "$status" -eq 0 ]
  [ "$output" = "s1: OK" ]
}

@test "a WARN line is printed after the FAIL lines and the exit code counts only failing slices" {
  record_good_slice s2
  two_runs "$PASS" "$(status_of skip "$T1" skipped)"
  run check s1 s2
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == "s1: FAIL (9b: "* ]]
  [[ "${lines[1]}" == "s1: WARN (9c: "* ]]
  [ "${lines[2]}" = "s2: OK" ]
}

@test "rule 9c fails the slice, not reads as OK, when the counts it reads are not numbers" {
  two_runs "$(status_of skip "$T1" skipped)" "$(status_of skip2 "$T1" skipped)"
  tamper s1 '.runs[1].tests.skipped = "x"'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (9c: could not evaluate"* ]]
}

@test "an old slice with no tests field on any run is untouched by 9b and 9c" {
  record_good_slice s1
  tamper s1 'del(.runs[].tests)'
  run check s1
  [ "$status" -eq 0 ]
  [ "$output" = "s1: OK" ]
}
