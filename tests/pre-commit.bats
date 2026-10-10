#!/usr/bin/env bats
# hooks/pre-commit: check slices whose oracle files are staged; block unless VETDD_BYPASS=1

load test_helper

setup() { make_repo; }

hook() { "$SCRIPTS/hooks/pre-commit"; }

# The oracle file is edited, then the slice is recorded against that edit.
verified_oracle_edit() {
  printf '# oracle v2\n' >> test.sh
  record_good_slice s1
}

@test "staged oracle file with matching evidence passes and says what it checked" {
  verified_oracle_edit
  git add test.sh
  run hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"s1"* ]]
  [[ "$output" == *"s1: OK"* ]]
}

@test "staged oracle file edited after the green run blocks the commit" {
  verified_oracle_edit
  printf '# edited after green\n' >> test.sh
  git add test.sh
  run hook
  [ "$status" -ne 0 ]
  [[ "$output" == *"s1: FAIL (6: "* ]]
  [[ "$output" == *"blocked"* ]]
  [[ "$output" == *"VETDD_BYPASS=1"* ]]
}

@test "VETDD_BYPASS=1 reports the failure but lets the commit through" {
  verified_oracle_edit
  printf '# edited after green\n' >> test.sh
  git add test.sh
  VETDD_BYPASS=1 run hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"s1: FAIL"* ]]
  [[ "$output" == *"bypass"* ]]
}

@test "only slices whose oracle files are staged are checked" {
  verified_oracle_edit
  ev other calibration --oracle-file sub/keep.txt -- true
  git add test.sh
  run hook
  [ "$status" -eq 0 ]
  [[ "$output" != *"other"* ]]
}

@test "a deleted oracle file counts as staged" {
  verified_oracle_edit
  git add -A . ':(exclude).vetdd' && git commit -q -m v2
  git rm -q test.sh
  run hook
  [ "$status" -ne 0 ]
  [[ "$output" == *"s1: FAIL"* ]]
}

@test "staged files outside every oracle need no check" {
  verified_oracle_edit
  printf 'x\n' > unrelated.txt && git add unrelated.txt
  run hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to check"* ]]
}

@test "no evidence directory at all passes" {
  printf 'x\n' > unrelated.txt && git add unrelated.txt
  run hook
  [ "$status" -eq 0 ]
}

@test "installed hook blocks a real git commit and VETDD_BYPASS=1 lets it through" {
  "$SCRIPTS/setup-project.sh"
  git add .gitignore && git commit -q -m "vetdd setup"
  verified_oracle_edit
  printf '# edited after green\n' >> test.sh
  git add test.sh
  head_before="$(git rev-parse HEAD)"
  run git commit -m "should be blocked"
  [ "$status" -ne 0 ]
  [ "$(git rev-parse HEAD)" = "$head_before" ]
  VETDD_BYPASS=1 git commit -q -m "bypassed"
  [ "$(git rev-parse HEAD)" != "$head_before" ]
}

@test "installed hook lets a verified commit through" {
  "$SCRIPTS/setup-project.sh"
  git add .gitignore && git commit -q -m "vetdd setup"
  verified_oracle_edit
  git add test.sh value.txt
  run git commit -m "verified"
  [ "$status" -eq 0 ]
  [[ "$output" == *"s1: OK"* ]]
}

@test "with core.ignorecase, a staged path matches a recorded oracle path spelled in another case (L1)" {
  verified_oracle_edit
  git config core.ignorecase true
  # The index spells the file one way, the record another (a rename without git mv).
  tamper s1 '.oracle.files[0].path = "TEST.SH"'
  printf '# edited after green\n' >> test.sh
  git add test.sh
  run hook
  [ "$status" -ne 0 ]
  [[ "$output" == *"running check-evidence.sh"* ]]
}

@test "without core.ignorecase, the match stays exact" {
  verified_oracle_edit
  git config core.ignorecase false
  tamper s1 '.oracle.files[0].path = "TEST.SH"'
  printf '# edited after green\n' >> test.sh
  git add test.sh
  run hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to check"* ]]
}

@test "an evidence directory whose name is not a slice id blocks the commit, never printed or passed on (N1)" {
  verified_oracle_edit
  cp -R .vetdd/evidence/s1 ".vetdd/evidence/x$(printf '\033')]0;pwn$(printf '\007')"
  cp -R .vetdd/evidence/s1 .vetdd/evidence/--repo
  git add test.sh
  run hook
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: OK"* ]]
  [[ "$output" != *$'\033'* ]]
  [[ "$output" != *$'\007'* ]]
  [[ "$output" == *"2 evidence directories have names that are not slice ids"* ]]
  [[ "$output" == *"blocked"* ]]
  VETDD_BYPASS=1 run hook
  [ "$status" -eq 0 ]
}

@test "a staged oracle file with a non-ASCII name is matched (N2)" {
  printf '#!/bin/sh\n[ "$(cat value.txt)" = 42 ]\n' > 'テスト.sh'
  printf '0\n' > value.txt
  ev s1 before --oracle-version v1 --oracle-file 'テスト.sh' -- sh 'テスト.sh'
  printf '42\n' > value.txt
  ev s1 after -- sh 'テスト.sh'
  printf '# edited after green\n' >> 'テスト.sh'
  git add 'テスト.sh'
  run hook
  [ "$status" -ne 0 ]
  [[ "$output" == *"s1: FAIL (6: "* ]]
}

@test "a hook that cannot load the vetdd scripts blocks unless VETDD_BYPASS=1 (N4)" {
  verified_oracle_edit
  git add test.sh
  VETDD_SCRIPTS_DIR="$BATS_TEST_TMPDIR/missing" run "$SCRIPTS/hooks/pre-commit"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot load the vetdd scripts"* ]]
  VETDD_BYPASS=1 VETDD_SCRIPTS_DIR="$BATS_TEST_TMPDIR/missing" run "$SCRIPTS/hooks/pre-commit"
  [ "$status" -eq 0 ]
}

@test "a hook whose scripts are gone still lets a commit through when there is no evidence (R1)" {
  git add test.sh
  VETDD_SCRIPTS_DIR="$BATS_TEST_TMPDIR/missing" run "$SCRIPTS/hooks/pre-commit"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# A slice whose latest green skipped a test: check-evidence prints a WARN line (rule 9c) and says OK.
warned_oracle_edit() {
  local rep="$BATS_TEST_TMPDIR/skip.json"
  printf '{"numTotalTests":1,"testResults":[{"name":"a.test.ts","assertionResults":[{"fullName":"x","status":"skipped"}]}]}' > "$rep"
  printf '# oracle v2\n' >> test.sh
  printf '0\n' > value.txt
  ev s1 before --oracle-version v1 --oracle-file test.sh --test-report jest-json:.vetdd/reports/r.json -- \
    sh -c "mkdir -p .vetdd/reports && cp '$rep' .vetdd/reports/r.json; exit 1" >/dev/null 2>&1
  ev s1 after --test-report jest-json:.vetdd/reports/r.json -- \
    sh -c "mkdir -p .vetdd/reports && cp '$rep' .vetdd/reports/r.json; exit 0" >/dev/null 2>&1
}

@test "a slice with only a 9c WARN line does not block the commit, and the line is shown" {
  warned_oracle_edit
  git add test.sh
  run hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"s1: OK"* ]]
  [[ "$output" == *"s1: WARN (9c: "* ]]
  [[ "$output" != *"blocked"* ]]
}

@test "installed hook lets a commit with only a 9c WARN line through" {
  "$SCRIPTS/setup-project.sh"
  git add .gitignore && git commit -q -m "vetdd setup"
  warned_oracle_edit
  git add test.sh value.txt
  run git commit -m "warned"
  [ "$status" -eq 0 ]
  [[ "$output" == *"s1: WARN (9c: "* ]]
}

@test "#25: a JS/TS slice committed before Close is not blocked for its missing mutation audit (a WARN says it comes in Close)" {
  printf 'it("x", () => {});\n' > a.test.ts && git add a.test.ts && git commit -qm oracle
  printf '0\n' > value.txt
  ev s1 before --seam unit --oracle-version v1 --oracle-file a.test.ts -- sh test.sh >/dev/null 2>&1
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh >/dev/null 2>&1
  printf '// more\n' >> a.test.ts
  printf '0\n' > value.txt
  ev s1 before --seam unit --oracle-version v2 --oracle-file a.test.ts -- sh test.sh >/dev/null 2>&1
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh >/dev/null 2>&1
  git add a.test.ts
  run hook
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"s1: WARN (10c: no mutation audit"*"Close"* ]] || { echo "$output"; false; }
  # check-evidence on its own (Close step 3) still fails it.
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (10c: no mutation audit"* ]]
}


@test "#25: a hook installed before #25 (no --before-close) still only warns before Close" {
  local old="$BATS_TEST_TMPDIR/oldhooks"; mkdir -p "$old"
  sed 's/ --before-close//' "$SCRIPTS/hooks/pre-commit" > "$old/pre-commit"; chmod +x "$old/pre-commit"
  ! grep -q -- '--before-close' "$old/pre-commit" || false
  printf 'it("x", () => {});\n' > a.test.ts && git add a.test.ts && git commit -qm oracle
  printf '0\n' > value.txt
  ev s1 before --seam unit --oracle-version v1 --oracle-file a.test.ts -- sh test.sh >/dev/null 2>&1
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh >/dev/null 2>&1
  printf '// more\n' >> a.test.ts
  printf '0\n' > value.txt
  ev s1 before --seam unit --oracle-version v2 --oracle-file a.test.ts -- sh test.sh >/dev/null 2>&1
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh >/dev/null 2>&1
  git add a.test.ts
  VETDD_SCRIPTS_DIR="$SCRIPTS" run "$old/pre-commit"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"s1: WARN (10c: no mutation audit"* ]]
  # Outside a hook, check-evidence.sh still fails it.
  run check s1
  [ "$status" -eq 1 ]
}
