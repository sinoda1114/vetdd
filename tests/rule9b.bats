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
  ! printf '%s' "$output" | LC_ALL=C grep -q "$(printf '[\001-\010\013-\037\177]')" || false
  ! printf '%s\n' "$output" | grep -qx 's1: OK' || false
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

@test "rule 9b stays fast on a large filtered suite: two runs of 5000 tests, one passed then skipped (perf)" {
  jq -n '{numTotalTests: 5000, testResults: [{name: "/work/big.test.ts", status: "passed",
        assertionResults: [range(0; 5000) | {fullName: ("case \(.)"), title: ("case \(.)"), status: (if . == 0 then "passed" else "skipped" end)}]}]}' > "$BATS_TEST_TMPDIR/big1.json"
  jq '(.testResults[0].assertionResults[0].status) = "skipped"' "$BATS_TEST_TMPDIR/big1.json" > "$BATS_TEST_TMPDIR/big2.json"
  two_runs "$BATS_TEST_TMPDIR/big1.json" "$BATS_TEST_TMPDIR/big2.json"
  SECONDS=0
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9b: test \"case 0\""* ]]
  [ "$SECONDS" -le 5 ] || { echo "took $SECONDS s"; false; }
}

# --- review round 1: a large suite is compared in linear time -------------------------------------

# big_report <name> <n> <from> <to>: n tests; those with from <= index < to passed, the rest skipped.
big_report() {
  jq -n --argjson n "$2" --argjson from "$3" --argjson to "$4" '
    {numTotalTests: $n, testResults: [{name: "/work/big.test.ts", status: "passed", assertionResults:
      [range(0; $n) | {fullName: "test \(.)", title: "t\(.)", status: (if . >= $from and . < $to then "passed" else "skipped" end)}]}]}' \
    > "$BATS_TEST_TMPDIR/$1.json"
  printf '%s' "$BATS_TEST_TMPDIR/$1.json"
}

@test "rule 9b compares two runs of 20000 tests each in linear time, not quadratic (codex review)" {
  # Earlier: only the last test ran; latest: nothing ran. Every skipped test of the latest run used to
  # be searched for in the whole earlier run (13 seconds for 5000 tests with the codex reviewer's jq; a
  # little over a second for 20000 with jq 1.8.1, where the old search is not the bottleneck: this test
  # guards the index against a regression, it was not red before it).
  two_runs "$(big_report earlier 20000 19999 20000)" "$(big_report latest 20000 0 0)"
  start=$SECONDS
  run check s1
  elapsed=$((SECONDS - start))
  [ "$status" -eq 1 ]
  [[ "$output" == *"test 19999"* ]]
  [ "$elapsed" -lt 5 ] || { echo "took ${elapsed}s"; false; }
}

# --- review round 2 ---------------------------------------------------------------------------

# recv <version> <kind> <report or -> <exit code>: like rec, under a given oracle version.
recv() {
  local ver="$1" kind="$2" rep="$3" code="$4"
  if [ "$rep" = - ]; then rep=""; fi
  REPORT="$rep" EXIT="$code" ev s1 "$kind" --oracle-version "$ver" --oracle-file test.sh \
    --test-report "jest-json:$R" -- sh runner.sh >/dev/null 2>&1 || true
}

@test "rule 9b compares only runs of the same oracle version, so a bump is the way out of a deliberate skip (round 2 #1)" {
  recv v1 before "$PASS" 1
  recv v1 after "$PASS" 0
  recv v2 calibration "$(status_of skipv2 "$T1" skipped)" 1
  recv v2 after "$(status_of skipv2b "$T1" skipped)" 0
  run check s1
  [[ "$output" != *"9b: "* ]] || { echo "$output"; false; }
  # The same skip under the same version still fails.
  rm -rf .vetdd
  recv v1 before "$PASS" 1
  recv v1 after "$(status_of skipv1 "$T1" skipped)" 0
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9b: "* ]]
}

@test "the 9b message names the way out: bump the oracle version, not a note in the reply (round 2 #1)" {
  two_runs "$PASS" "$(status_of skipmsg "$T1" skipped)"
  run check s1
  [[ "$output" == *"bump --oracle-version"* ]]
  [[ "$output" != *"say in the reply"* ]]
}

@test "9c does not say another run recorded a report when only the latest run asked for one (round 2 #2)" {
  rec before - 1
  rec after - 0
  run check s1
  [[ "$output" == *"s1: WARN (9c: "* ]]
  [[ "$output" != *"another run of this slice recorded one"* ]]
  [[ "$output" == *"asked for a test report"* ]]
}

@test "9c says tests left out by a name filter count as skipped (round 2 #4)" {
  rec before "$PASS" 1
  rec after "$(status_of skipwarn "$T1" skipped)" 0 || true
  run check s1
  [[ "$output" == *"name filter"* ]]
}

@test "modes/test.md gives the Close example the same --test-report (round 2 #3)" {
  # The command example in the Close step (not the paragraph that explains the option).
  sed -n '/^## Close/,/^2\. /p' "$BATS_TEST_DIRNAME/../skills/vetdd/modes/test.md" | grep -q -- '--test-report'
}

# --- review round 3 ---------------------------------------------------------------------------

@test "rule 9b leaves an older oracle version alone: a skip under v1 is history once v2 is recorded (K1)" {
  recv v1 before "$PASS" 1
  recv v1 after "$(status_of k1skip "$T1" skipped)" 0
  recv v2 calibration "$PASS" 1
  recv v2 after "$PASS" 0
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"9b: "* ]]
}

@test "rule 9b does not compare a command whose latest run has no usable report (K3)" {
  recv v1 before "$PASS" 1
  recv v1 after "$(status_of k3skip "$T1" skipped)" 0
  recv v1 integrated - 0
  run check s1
  [[ "$output" != *"9b: "* ]] || { echo "$output"; false; }
  [[ "$output" == *"s1: WARN (9c: "*"asked for a test report"* ]]
}

@test "9c reads each command's own latest green: a type check recorded last does not hide the test counts (K2)" {
  rec before "$PASS" 1
  rec after "$(status_of k2skip "$T1" skipped)" 0
  # The coverage oracle: another command, no report, recorded after the slice's own tests.
  ev s1 after --oracle-version v1 --oracle-file test.sh -- sh -c 'exit 0' >/dev/null 2>&1
  run check s1
  [[ "$output" == *"s1: WARN (9c: 1 skipped and 0 todo tests in the latest after run 2"* ]] || { echo "$output"; false; }
  [[ "$output" != *"no test report was recorded"* ]]
}

@test "a bidirectional control character in a test name never reaches the output (K4)" {
  jq --arg n "$T1" --arg bad "$(printf 'evil\xe2\x80\xaetxt.exe')" \
    '(.testResults[].assertionResults[] | select(.fullName == $n) | .fullName) = $bad | (.testResults[].assertionResults[] | select(.fullName == $bad) | .title) = $bad' \
    "$PASS" > "$BATS_TEST_TMPDIR/bidi.json"
  jq --arg bad "$(printf 'evil\xe2\x80\xaetxt.exe')" '(.testResults[].assertionResults[] | select(.fullName == $bad) | .status) = "skipped"' \
    "$BATS_TEST_TMPDIR/bidi.json" > "$BATS_TEST_TMPDIR/bidi-skip.json"
  two_runs "$BATS_TEST_TMPDIR/bidi.json" "$BATS_TEST_TMPDIR/bidi-skip.json"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9b: "* ]]
  [[ "$output" != *$'\xe2\x80\xae'* ]]
}

# --- review round 4 ---------------------------------------------------------------------------

@test "9c does not say an earlier run asked for a report when the request came later (L1)" {
  EXIT=1 ev s1 before --oracle-version v1 --oracle-file test.sh -- sh runner.sh >/dev/null 2>&1 || true
  EXIT=0 ev s1 after --oracle-version v1 --oracle-file test.sh -- sh runner.sh >/dev/null 2>&1 || true
  REPORT="$PASS" EXIT=1 ev s1 calibration --oracle-version v1 --oracle-file test.sh --test-report "jest-json:$R" -- sh runner.sh >/dev/null 2>&1 || true
  run check s1
  [[ "$output" == *"9c: "* ]]
  [[ "$output" != *"an earlier run"* ]]
  [[ "$output" == *"another run of the same command asked for one"* ]]
}

@test "marks and invisible format characters are dropped from a shown name (round 4 #5)" {
  bad="$(printf 'ab\xe2\x80\x8ecd\xe2\x80\x8bef\xef\xbb\xbfgh\xd8\x9cij')"
  jq --arg n "$T1" --arg bad "$bad" '(.testResults[].assertionResults[] | select(.fullName == $n)) |= (.fullName = $bad | .title = $bad)' "$PASS" > "$BATS_TEST_TMPDIR/inv.json"
  jq --arg bad "$bad" '(.testResults[].assertionResults[] | select(.fullName == $bad) | .status) = "skipped"' "$BATS_TEST_TMPDIR/inv.json" > "$BATS_TEST_TMPDIR/inv-skip.json"
  two_runs "$BATS_TEST_TMPDIR/inv.json" "$BATS_TEST_TMPDIR/inv-skip.json"
  run check s1
  [[ "$output" == *"abcdefghij"* ]]
}

@test "a recorded sha256 that ends in a newline is not taken for a hash (round 4 #6)" {
  two_runs "$PASS" "$(status_of shanl "$T1" skipped)"
  good="$(jq -r '.runs[0].tests.sha256' .vetdd/evidence/s1/meta.json)"
  tamper s1 --arg h "$good"$'\n' '.runs[0].tests.sha256 = $h' 2>/dev/null || jq --arg h "$good"$'\n' '.runs[0].tests.sha256 = $h' .vetdd/evidence/s1/meta.json > m && mv m .vetdd/evidence/s1/meta.json
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9b: could not read the test report copy of run 1"* ]]
}

@test "modes/test.md says 9b compares within one oracle version and when 9c warns about a missing report (round 4 #2)" {
  # The paragraph that states rule 9b names the oracle version; the 9c one says when a missing report warns.
  awk 'BEGIN{RS=""} /rule 9b fails/' "$BATS_TEST_DIRNAME/../skills/vetdd/modes/test.md" | grep -q 'oracle version'
  awk 'BEGIN{RS=""} /WARN \(9c/' "$BATS_TEST_DIRNAME/../skills/vetdd/modes/test.md" | grep -q 'absent when another run of that command asked for one'
}
