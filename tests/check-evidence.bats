#!/usr/bin/env bats
# check-evidence.sh: history rules (1)-(4) and final-evidence rules (5)-(6) from plan §2.4

load test_helper

setup() { make_repo; }

@test "a before-red then after-green slice is OK" {
  record_good_slice s1
  run check s1
  [ "$status" -eq 0 ]
  [ "$output" = "s1: OK" ]
}

# --- rule 1: red precedes green -------------------------------------------

@test "rule 1 fails when no red run precedes the after run" {
  printf '42\n' > value.txt
  ev s1 after --oracle-file test.sh -- sh test.sh
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == "s1: FAIL (1: "* ]]
}

@test "rule 1 passes with a calibration red for a behavior-preserving change" {
  ev s1 calibration --oracle-file test.sh -- sh test.sh
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh
  run check s1
  [ "$status" -eq 0 ]
  [ "$output" = "s1: OK" ]
}

@test "rule 1 fails when a red before run comes after the last after run" {
  record_good_slice s1
  printf '0\n' > value.txt
  ev s1 before -- sh test.sh
  printf '42\n' > value.txt
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (1: "* ]]
}

# --- rule 2: before is target_failure ----------------------------------------

@test "rule 2 fails when an accepted before run ended pass" {
  record_good_slice s1
  tamper s1 '.runs[0].outcome = "pass"'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (2: "* ]]
}

@test "rule 2 passes when a rejected passing before attempt stays in history" {
  printf '42\n' > value.txt
  run ev s1 before --oracle-file test.sh -- sh test.sh
  [ "$status" -ne 0 ]
  record_good_slice s1
  run check s1
  [ "$status" -eq 0 ]
  [ "$output" = "s1: OK" ]
}

# --- rule 3: after / integrated are pass -------------------------------------

@test "rule 3 fails when an accepted after run ended target_failure" {
  record_good_slice s1
  tamper s1 '.runs[1].outcome = "target_failure"'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (3: "* ]]
}

@test "rule 3 fails when the latest after attempt failed on the same tree" {
  record_good_slice s1
  run ev s1 after --outcome target_failure -- true
  [ "$status" -ne 0 ]
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (3: "* ]]
}

@test "rule 3 passes when a failed after attempt is followed by a passing one" {
  ev s1 before --oracle-file test.sh -- sh test.sh
  run ev s1 after -- sh test.sh
  [ "$status" -ne 0 ]
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh
  run check s1
  [ "$status" -eq 0 ]
  [ "$output" = "s1: OK" ]
}

@test "rule 3 also covers integrated runs" {
  record_good_slice s1
  ev s1 integrated -- sh test.sh
  tamper s1 '.runs[2].outcome = "target_failure"'
  run check s1
  [[ "$output" == *"s1: FAIL (3: "* ]]
}

# --- rule 4: infrastructure_error / inconclusive count as neither -------------

@test "rule 4 fails when an accepted before run is infrastructure_error" {
  record_good_slice s1
  tamper s1 '.runs[0].outcome = "infrastructure_error"'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (4: "* ]]
}

@test "rule 4: an inconclusive calibration is not counted as red" {
  ev s1 calibration --outcome inconclusive --oracle-file test.sh -- sh test.sh
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (1: "* ]]
}

@test "rule 4 passes when an infrastructure_error calibration sits in history" {
  ev s1 calibration --outcome infrastructure_error --oracle-file test.sh -- true
  record_good_slice s1
  run check s1
  [ "$status" -eq 0 ]
  [ "$output" = "s1: OK" ]
}

# --- rule 5: final evidence matches the current tree -------------------------

@test "rule 5 fails when a tracked file changed after the last after run" {
  record_good_slice s1
  printf 'drift\n' > sub/keep.txt
  run check s1
  [ "$status" -eq 1 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == "s1: FAIL (5: "*")" ]]
  [[ "$output" == *"tree"* ]]
}

@test "rule 5 fails when there is no after or integrated run" {
  ev s1 before --oracle-file test.sh -- sh test.sh
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (5: "* ]]
}

@test "rule 5 passes after committing the verified tree and touching only .vetdd" {
  record_good_slice s1
  git add -A . ':(exclude).vetdd' && git commit -q -m fix
  printf 'noise\n' > .vetdd/note.txt
  run check s1
  [ "$status" -eq 0 ]
  [ "$output" = "s1: OK" ]
}

# --- rule 6: oracle files unchanged ------------------------------------------

@test "rule 6 fails when an oracle file hash no longer matches" {
  record_good_slice s1
  tamper s1 '.oracle.files[0].sha256 = ("0" * 64)'
  run check s1
  [ "$status" -eq 1 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == "s1: FAIL (6: "*")" ]]
  [[ "$output" == *"test.sh"* ]]
}

@test "rule 6 fails when the oracle has no files" {
  ev s1 before -- sh test.sh
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (6: "* ]]
}

@test "rule 6 fails when an oracle file was deleted" {
  printf 'expected\n' > oracle-data.txt
  record_good_slice s1
  ev s1 after --oracle-file test.sh --oracle-file oracle-data.txt -- sh test.sh
  git add -A . ':(exclude).vetdd' && git commit -q -m data
  git rm -q oracle-data.txt
  run check s1
  [[ "$output" == *"s1: FAIL (6: "*"oracle-data.txt"* ]]
}

@test "every failing rule of a slice is reported on its own line" {
  record_good_slice s1
  printf '\n# edited after green\n' >> test.sh
  run check s1
  [ "$status" -eq 1 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == "s1: FAIL (5: "* ]]
  [[ "${lines[1]}" == "s1: FAIL (6: "* ]]
}

# --- selection, exit code, repo option ---------------------------------------

@test "no slice ids checks every slice; exit code counts failing slices" {
  record_good_slice good
  ev bad1 calibration --oracle-file test.sh -- true
  ev bad2 calibration --oracle-file test.sh -- true
  run check
  [ "$status" -eq 2 ]
  [[ "$output" == *"good: OK"* ]]
  [[ "$output" == *"bad1: FAIL (5: "* ]]
  [[ "$output" == *"bad2: FAIL (5: "* ]]
}

@test "named slice ids limit the check" {
  record_good_slice good
  ev bad1 calibration --oracle-file test.sh -- true
  run check good
  [ "$status" -eq 0 ]
  [ "$output" = "good: OK" ]
}

@test "unknown slice id fails" {
  run check nothing-here
  [ "$status" -eq 1 ]
  [[ "$output" == "nothing-here: FAIL ("* ]]
}

@test "no evidence at all exits 0 with a message" {
  run check
  [ "$status" -eq 0 ]
  [[ "$output" == *"no evidence"* ]]
}

@test "--repo checks another repository from any cwd" {
  record_good_slice s1
  cd "$BATS_TEST_TMPDIR"
  run check --repo "$REPO" s1
  [ "$status" -eq 0 ]
  [ "$output" = "s1: OK" ]
}

@test "malformed meta.json is reported as a schema failure" {
  mkdir -p .vetdd/evidence/broken && printf '{not json' > .vetdd/evidence/broken/meta.json
  run check broken
  [ "$status" -eq 1 ]
  [[ "$output" == "broken: FAIL (schema: "* ]]
}

@test "slice_id that does not match its directory is a schema failure" {
  record_good_slice s1
  tamper s1 '.slice_id = "other"'
  run check s1
  [[ "$output" == *"s1: FAIL (schema: "* ]]
}
