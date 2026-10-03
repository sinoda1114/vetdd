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

# --- rule 8: the oracle's version chain ------------------------------------------
# An oracle is identified by its version and the sha256 of its files. A change to the files needs a
# new version, a new version needs its own red before its green, and the final green uses the
# latest version.

@test "rule 8 fails when the test changed after before but the version stayed" {
  printf '0\n' > value.txt
  ev s1 before --oracle-version v1 --oracle-file test.sh -- sh test.sh
  printf '# edited after before\n' >> test.sh
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (8: "*"version"* ]]
}

@test "rule 8 fails when a new version has no red of its own before the green" {
  printf '0\n' > value.txt
  ev s1 before --oracle-version v1 --oracle-file test.sh -- sh test.sh
  printf '# v2\n' >> test.sh
  printf '42\n' > value.txt
  ev s1 after --oracle-version v2 -- sh test.sh
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (8: "*"v2"* ]]
}

@test "rule 8 fails when a weakened oracle is recalibrated: its calibration never goes red" {
  printf '0\n' > value.txt
  ev s1 before --oracle-version v1 --oracle-file test.sh -- sh test.sh
  printf '#!/bin/sh\nexit 0\n' > test.sh
  ev s1 calibration --oracle-version v2 -- sh test.sh
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (8: "*"v2"* ]]
}

@test "rule 8 passes when a new version is recalibrated red before its green" {
  printf '0\n' > value.txt
  ev s1 before --oracle-version v1 --oracle-file test.sh -- sh test.sh
  printf '# v2: same check, clearer message\n' >> test.sh
  ev s1 calibration --oracle-version v2 -- sh test.sh
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh
  run check s1
  [ "$status" -eq 0 ]
  [ "$output" = "s1: OK" ]
}

@test "rule 8 fails when a replaced version comes back (v1, v2, then v1 again)" {
  cp test.sh test.v1
  printf '0\n' > value.txt
  ev s1 before --oracle-version v1 --oracle-file test.sh -- sh test.sh
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh
  printf '# v2\n' >> test.sh
  printf '0\n' > value.txt
  ev s1 calibration --oracle-version v2 -- sh test.sh
  cp test.v1 test.sh
  printf '42\n' > value.txt
  ev s1 after --oracle-version v1 -- sh test.sh
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (8: "*"v1"* ]]
}

@test "rule 8 fails when a newer version was recorded after the final green" {
  record_good_slice s1
  printf '# v2\n' >> test.sh
  printf '0\n' > value.txt
  ev s1 calibration --oracle-version v2 -- sh test.sh
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (8: "*"v2"*"after the final green"* ]]
}

@test "rule 8 fails when an oracle file is added but the version stayed" {
  printf 'true\n' > extra.sh
  printf '0\n' > value.txt
  ev s1 before --oracle-version v1 --oracle-file test.sh -- sh test.sh
  printf '42\n' > value.txt
  ev s1 after --oracle-file test.sh --oracle-file extra.sh -- sh test.sh
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (8: "* ]]
}

@test "rule 8 passes an oracle that never names a version (null throughout)" {
  printf '0\n' > value.txt
  ev s1 before --oracle-file test.sh -- sh test.sh
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh
  run check s1
  [ "$status" -eq 0 ]
  [ "$output" = "s1: OK" ]
}

@test "rule 8 passes coverage oracles recorded with the inherited oracle (another command)" {
  record_good_slice s1
  ev s1 after -- sh -c 'true'
  run check s1
  [ "$status" -eq 0 ]
  [ "$output" = "s1: OK" ]
}

@test "rule 8 ignores a rejected run with another oracle" {
  printf '0\n' > value.txt
  ev s1 before --oracle-version v1 --oracle-file test.sh -- sh test.sh
  printf '42\n' > value.txt
  run ev s1 before --oracle-version v9 -- sh test.sh
  [ "$status" -ne 0 ]
  ev s1 after --oracle-version v1 -- sh test.sh
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "s1: OK" ]
}

# A shared test file: two slices whose tests live in one file (suite.sh <slice>).
write_suite() {
  {
    printf '#!/bin/sh\ncase "$1" in\n'
    printf '  s1) [ "$(cat value.txt)" = "42" ] ;;\n'
    [ "${1:-}" = both ] && printf '  s2) [ "$(cat other.txt)" = "7" ] ;;\n'
    printf 'esac\n'
  } > suite.sh
}

@test "rule 8 passes slices sharing one test file when every test is written before any before run" {
  printf '0\n' > value.txt; printf '0\n' > other.txt
  write_suite both
  ev s1 before --oracle-version v1 --oracle-file suite.sh -- sh suite.sh s1
  ev s2 before --oracle-version v1 --oracle-file suite.sh -- sh suite.sh s2
  printf '42\n' > value.txt; printf '7\n' > other.txt
  ev s1 after -- sh suite.sh s1
  ev s2 after -- sh suite.sh s2
  run check s1 s2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "s1: OK
s2: OK" ]
}

@test "rule 8 fails an earlier slice when a later slice's test is added to the shared file, and says why" {
  printf '0\n' > value.txt; printf '0\n' > other.txt
  write_suite one
  ev s1 before --oracle-version v1 --oracle-file suite.sh -- sh suite.sh s1
  write_suite both
  ev s2 before --oracle-version v1 --oracle-file suite.sh -- sh suite.sh s2
  printf '42\n' > value.txt; printf '7\n' > other.txt
  ev s1 after -- sh suite.sh s1
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (8: "*"another slice"*"same file"* ]]
}

@test "rule 8 recovers once the version is bumped and recalibrated after an edit without a bump (C1)" {
  printf '0\n' > value.txt
  ev s1 before --oracle-version v1 --oracle-file test.sh -- sh test.sh
  printf '# edited after before\n' >> test.sh
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh
  run check s1
  [ "$status" -eq 1 ]
  # The fix test.md gives: a new version, its own red, then the green.
  printf '0\n' > value.txt
  ev s1 calibration --oracle-version v2 -- sh test.sh
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "s1: OK" ]
}

@test "a run whose oracle record is malformed fails the slice instead of skipping rule 8 (O3)" {
  record_good_slice s1
  tamper s1 '.runs[0].oracle = 5'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (8: "* ]]
  [[ "$output" != *"s1: OK"* ]]
  tamper s1 '.runs[0].oracle = {"version": "v1", "files": "test.sh"}'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (8: "* ]]
  [[ "$output" != *"s1: OK"* ]]
}

@test "rule 8 passes a defect slice whose known-good case was in the test file before the before run (O2)" {
  printf '0\n' > value.txt; printf '7\n' > other.txt
  write_suite both
  ev s1 before --oracle-version v1 --oracle-file suite.sh -- sh suite.sh s1
  ev s1 calibration -- sh suite.sh s2
  printf '42\n' > value.txt
  ev s1 after -- sh suite.sh s1
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "s1: OK" ]
}

@test "an accepted run without an oracle record fails rule 8 instead of dropping out of the chain (D2)" {
  record_good_slice s1
  tamper s1 '.runs[1].oracle = null'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (8: run 2 has no oracle record"* ]]
  tamper s1 'del(.runs[1].oracle)'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (8: run 2 has no oracle record"* ]]
}

@test "a verify slice that names every feature script on every run passes rule 8 (D3)" {
  printf '#!/bin/sh\n[ "$(cat value.txt)" = "${1:-42}" ]\n' > verify-a.sh
  printf '#!/bin/sh\ntrue\n' > verify-c.sh
  printf '0\n' > value.txt
  ev app-verify before --oracle-version 1 --oracle-file verify-a.sh --oracle-file verify-c.sh -- sh verify-a.sh
  printf '42\n' > value.txt
  ev app-verify after -- sh verify-a.sh
  ev app-verify after -- sh verify-c.sh
  run check app-verify
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "check-evidence never prints control characters from a recorded oracle version (D4)" {
  printf '0\n' > value.txt
  ev s1 before --oracle-version v1 --oracle-file test.sh -- sh test.sh
  printf '# edited\n' >> test.sh
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh
  # A record written by hand or copied from a worker: evidence.sh itself refuses such a version.
  tamper s1 '.runs[].oracle.version = "v1\u001b[2K\rs1: OK"'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" != *$'\033'* ]]
  [[ "$output" != *$'\r'* ]]
}

@test "rule 8 lets the test be fixed before its first right red, under the same version (E1)" {
  printf 'syntax error here (\n' > test.sh
  printf '0\n' > value.txt
  ev s1 before --oracle-version 1 --oracle-file test.sh -- sh test.sh
  printf '#!/bin/sh\n[ "$(cat value.txt)" = "42" ]\n' > test.sh
  ev s1 before -- sh test.sh
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "s1: OK" ]
}

@test "rule 8 does not count a red forced with --outcome on a command that exited 0 (E6)" {
  printf '0\n' > value.txt
  ev s1 before --oracle-version v1 --oracle-file test.sh -- sh test.sh
  printf '#!/bin/sh\nexit 0\n' > test.sh
  ev s1 calibration --oracle-version v2 --outcome target_failure -- sh test.sh
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (8: "*"v2"* ]]
}

@test "check-evidence never prints control characters from a slice directory's name (E5)" {
  record_good_slice s1
  mkdir -p "$REPO/.vetdd/evidence/$(printf 'zz\033[1A\033[2K\rs1')"
  run check
  [ "$status" -ne 0 ]
  [[ "$output" != *$'\033'* ]]
  [[ "$output" != *$'\r'* ]]
}

@test "a verify slice calibrated in A.4 with every script named passes B with the same oracle (E2)" {
  printf '#!/bin/sh\n[ "$(cat value.txt)" = "${1:-42}" ]\n' > verify-a.sh
  printf '#!/bin/sh\ntrue\n' > verify-c.sh
  printf '42\n' > value.txt
  ev app-verify calibration --oracle-version 1 --oracle-file verify-a.sh --oracle-file verify-c.sh -- sh verify-a.sh 7
  ev app-verify calibration -- sh verify-a.sh
  ev app-verify after -- sh verify-a.sh
  ev app-verify after -- sh verify-c.sh
  run check app-verify
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "rule 8 fails when a version that already went green is edited and recalibrated without a bump (F1)" {
  record_good_slice s1
  printf '# edited after its green\n' >> test.sh
  printf '0\n' > value.txt
  ev s1 calibration -- sh test.sh
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (8: "*"version stayed v1"* ]]
}

@test "a slice directory name with a newline cannot print a line of its own (G1)" {
  record_good_slice s1
  mkdir -p "$REPO/.vetdd/evidence/$(printf 'zz\ns2: OK\nyy')"
  run check
  [ "$status" -ne 0 ]
  ! printf '%s\n' "$output" | grep -qx 's2: OK'
  [[ "$output" == *"<invalid slice name>: FAIL (schema: invalid slice id)"* ]]
}

@test "rule 3 fails a green forced with --outcome pass on a command that failed (K1)" {
  printf '0\n' > value.txt
  ev s1 before --oracle-version v1 --oracle-file test.sh -- sh test.sh
  ev s1 after --outcome pass -- sh test.sh
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (3: "*"forced"* ]]
}

@test "rule 8 says why when the only red with the final oracle was forced on exit 0 (K2)" {
  printf '42\n' > value.txt
  ev s1 before --oracle-version v1 --oracle-file test.sh --outcome target_failure -- sh test.sh
  ev s1 after -- sh test.sh
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (8: "*"forced with --outcome"* ]]
}

@test "a run whose exit_code is not a number fails rule 8 instead of passing as a red (M1)" {
  record_good_slice s1
  tamper s1 '.runs[0].exit_code = "0"'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (8: run 1 has no numeric exit_code"* ]]
  [[ "$output" != *"s1: OK"* ]]
}

@test "the forced-pass message says how to recover (M2)" {
  record_good_slice s1
  tamper s1 '.runs[-1].exit_code = 1'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"forced it"*"new slice id"* ]]
}

@test "rule 6 fails an oracle.files entry that is not an object instead of skipping it (N3)" {
  record_good_slice s1
  tamper s1 '.oracle.files = ["test.sh"]'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL"*"6: "* ]]
  [[ "$output" != *"s1: OK"* ]]
}

@test "rule 8 does not count a red forced with --outcome on a command that could not run (O1)" {
  printf '0\n' > value.txt
  ev s1 before --oracle-version v1 --oracle-file test.sh --outcome target_failure -- ./no-such-command
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL"*"8: "* ]]
  [[ "$output" != *"s1: OK"* ]]
}

@test "rule 6 reports an oracle file missing at record time as missing and checks the rest (O2)" {
  record_good_slice s1
  tamper s1 '.oracle.files += [{"path": "gone.sh", "sha256": null}]'
  printf '# edited after green\n' >> test.sh
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"6: oracle file gone.sh is missing"* ]]
  [[ "$output" == *"6: oracle file test.sh changed"* ]]
  [[ "$output" != *"not a repo-relative path"* ]]
}

@test "rule 6 never opens a path that leaves the repository through a newline or a symbolic link (P1)" {
  record_good_slice s1
  printf 'secret\n' > "$REPO/../outside.txt"
  sum="$(sha256_of "$REPO/../outside.txt")"
  tamper s1 ".oracle.files = [{\"path\": \"x\\n../outside.txt\", \"sha256\": \"$sum\"}]"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"6: oracle.files holds an entry that is not a repo-relative path and a hash"* ]]
  ln -s .. lnk
  tamper s1 ".oracle.files = [{\"path\": \"lnk/outside.txt\", \"sha256\": \"$sum\"}]"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"6: oracle file lnk/outside.txt is a symbolic link or outside the repository"* ]]
  ln -s ../outside.txt out.sh
  tamper s1 ".oracle.files = [{\"path\": \"out.sh\", \"sha256\": \"$sum\"}]"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"6: oracle file out.sh is a symbolic link or outside the repository"* ]]
}

@test "rule 8 fails a run whose oracle record has no files array (Q1)" {
  record_good_slice s1
  tamper s1 '.runs[0].oracle = {} | .runs[1].oracle = {}'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"8: run 1 has no oracle record"* ]]
  [[ "$output" != *"s1: OK"* ]]
}

@test "rule 6 reports an oracle file whose directory is gone as missing (Q3)" {
  record_good_slice s1
  tamper s1 '.oracle.files += [{"path": "gone/dir/a.sh", "sha256": "0"}]'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"6: oracle file gone/dir/a.sh is missing"* ]]
}

@test "C1 control characters in a recorded value never reach the terminal (Q5)" {
  record_good_slice s1
  tamper s1 '.runs[0].oracle.version = "v\u009b2K" | .runs[1].oracle.version = "v\u009b2K"'
  printf '# edited after green\n' >> test.sh
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" != *$'\xc2\x9b'* ]]
  tamper s1 '.oracle.files = [{"path": "a\u009b2K.sh", "sha256": "0"}]'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"6: oracle.files holds an entry that is not a repo-relative path and a hash"* ]]
  [[ "$output" != *$'\xc2\x9b'* ]]
}

@test "a version reused by mistake is history once a new version records its red and green (R2)" {
  cp test.sh test.v1
  printf '0\n' > value.txt
  ev s1 before --oracle-version v1 --oracle-file test.sh -- sh test.sh
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh
  printf '# v2\n' >> test.sh
  printf '0\n' > value.txt
  ev s1 calibration --oracle-version v2 -- sh test.sh
  cp test.v1 test.sh
  printf '42\n' > value.txt
  ev s1 after --oracle-version v1 -- sh test.sh
  printf '# v3\n' >> test.sh
  printf '0\n' > value.txt
  ev s1 calibration --oracle-version v3 -- sh test.sh
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "s1: OK" ]
}

@test "the display filter drops C1 controls that a removal would rejoin, and lone C1 bytes (R4)" {
  . "$SCRIPTS/lib/common.sh"
  out="$(printf 'a\302\302\233\233b\233c\343\203\206\n' | vetdd_printable)"
  [ "$out" = "abcテ" ] || { printf '%s' "$out" | od -c; false; }
}

# A PATH holding only the named commands, for running without iconv or with a broken one.
only_path() {
  local bin="$BATS_TEST_TMPDIR/bin" c
  mkdir -p "$bin"
  for c in "$@"; do ln -sf "$(command -v "$c")" "$bin/$c"; done
  printf '%s\n' "$bin"
}

@test "without iconv the display filter keeps valid UTF-8 and still drops C1 controls (S1)" {
  . "$SCRIPTS/lib/common.sh"
  bin="$(only_path tr sed cat)"
  out="$(printf 'a\302\302\233\233b\302\205c\343\203\206\n' | PATH="$bin" vetdd_printable)"
  [ "$out" = "abcテ" ] || { printf '%s' "$out" | od -c; false; }
}

@test "a Japanese oracle path is inside the repository whether or not iconv exists (S1)" {
  . "$SCRIPTS/lib/common.sh"
  printf 'x\n' > 'テスト.sh'
  root="$(pwd -P)"
  vetdd_inside_repo "$root" 'テスト.sh'
  bin="$(only_path dirname grep printf)"
  PATH="$bin" vetdd_inside_repo "$root" 'テスト.sh'
  ! vetdd_inside_repo "$root" "$(printf 'a\302\233b.sh')"
}

@test "a failing display filter never turns a failing slice into OK (S2)" {
  record_good_slice s1
  printf '# edited after green\n' >> test.sh
  mkdir -p "$BATS_TEST_TMPDIR/broken"
  printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/broken/iconv"; chmod +x "$BATS_TEST_TMPDIR/broken/iconv"
  PATH="$BATS_TEST_TMPDIR/broken:$PATH" run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL"* ]]
  [[ "$output" != *"s1: OK"* ]]
}

@test "the display filter passes each line on before its input ends (T1)" {
  . "$SCRIPTS/lib/common.sh"
  { printf 'first\n'; sleep 3; printf 'second\n'; } | vetdd_printable > "$BATS_TEST_TMPDIR/out" &
  sleep 1.5
  grep -q '^first$' "$BATS_TEST_TMPDIR/out"
  wait
  [ "$(cat "$BATS_TEST_TMPDIR/out")" = "$(printf 'first\nsecond')" ]
}

@test "the display filter keeps a last line that has no newline (T1)" {
  . "$SCRIPTS/lib/common.sh"
  [ "$(printf 'a\nb' | vetdd_printable | od -An -c | tr -d ' \n')" = 'a\nb' ]
}
