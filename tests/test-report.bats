#!/usr/bin/env bats
# evidence.sh --test-report: counts from the runner's machine-readable report go on the run record.
# tests/fixtures/reports/vitest5-*.json are real vitest 5.0.1 outputs of
#   vitest run --reporter=default --reporter=json --outputFile.json=<path>
# (local paths replaced by /work/ts-kata).

load test_helper

setup() {
  make_repo
  FIX="$BATS_TEST_DIRNAME/fixtures/reports"
}

R=.vetdd/reports/r.json
# Command that writes <fixture> as the report and exits <code>.
write_report() { printf 'mkdir -p .vetdd/reports && cp "%s" %s; exit %s' "$1" "$R" "$2"; }

@test "counts are imported from a real vitest report with a failure, a skip, and a todo" {
  run ev s1 calibration --test-report "jest-json:$R" -- sh -c "$(write_report "$FIX/vitest5-mixed.json" 1)"
  [ "$status" -eq 0 ]
  [ "$(mq s1 '.runs[0].outcome')" = "target_failure" ]
  [ "$(mq s1 '.runs[0].tests | [.format, .status, .passed, .failed, .skipped, .todo, .other, .total] | join(",")')" \
    = "jest-json,ok,10,1,1,1,0,13" ]
}

@test "counts are imported from a real vitest report where every test passes" {
  ev s1 calibration --test-report "jest-json:$R" -- sh -c "$(write_report "$FIX/vitest5-pass.json" 0)"
  [ "$(mq s1 '.runs[0].outcome')" = "pass" ]
  [ "$(mq s1 '.runs[0].tests | [.status, .passed, .failed, .skipped, .todo, .other, .total] | join(",")')" = "ok,9,0,0,0,0,9" ]
}

@test "the sha256 is of the normalized copy saved next to the run log" {
  ev s1 calibration --test-report "jest-json:$R" -- sh -c "$(write_report "$FIX/vitest5-mixed.json" 1)"
  local copy="$REPO/.vetdd/evidence/s1/runs/001-calibration.tests.json"
  [ -f "$copy" ]
  [ "$(mq s1 '.runs[0].tests.sha256')" = "$(sha256_of "$copy")" ]
  [ "$(jq -r '[.passed, .failed, .skipped, .todo, .total, (.tests | length)] | join(",")' "$copy")" = "10,1,1,1,13,13" ]
  [ "$(jq -r '.tests[] | select(.status == "todo") | .file' "$copy")" = "/work/ts-kata/src/mixed.test.ts" ]
}

@test "a stale report is deleted before the run and never read as this run's" {
  mkdir -p .vetdd/reports && cp "$FIX/vitest5-mixed.json" "$R"
  run ev s1 calibration --test-report "jest-json:$R" -- true
  [ "$status" -eq 0 ]
  [ ! -e "$R" ]
  [ "$(mq s1 '.runs[0].tests | [.status, (.passed // "none")] | join(",")')" = "missing,none" ]
}

@test "a missing report is status missing with a warning; the outcome stays the exit code" {
  run ev s1 after --test-report "jest-json:$R" -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"warning"*"missing"* ]]
  [ "$(mq s1 '.runs[0].outcome')" = "pass" ]
  [ "$(mq s1 '.runs[0].accepted')" = "true" ]
  [ "$(mq s1 '.runs[0].tests | keys | join(",")')" = "format,status" ]
  [ "$(mq s1 '.runs[0].tests.status')" = "missing" ]
}

@test "an invalid report is status invalid with a warning; the outcome stays the exit code" {
  run ev s1 calibration --test-report "jest-json:$R" -- sh -c "mkdir -p .vetdd/reports && echo '{not json' > $R; exit 1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"warning"*"invalid"* ]]
  [ "$(mq s1 '.runs[0].outcome')" = "target_failure" ]
  [ "$(mq s1 '.runs[0].tests.status')" = "invalid" ]
  run ev s1 after --test-report "jest-json:$R" -- sh -c "echo '{\"numTotalTests\": 1}' > $R"
  [ "$status" -eq 0 ]
  [ "$(mq s1 '.runs[1].outcome')" = "pass" ]
  [ "$(mq s1 '.runs[1].tests.status')" = "invalid" ]
  [ ! -e "$REPO/.vetdd/evidence/s1/runs/002-after.tests.json" ]
}

@test "unknown per-test statuses are counted in other, never dropped" {
  mkdir -p .vetdd/reports
  jq -n '{numTotalTests: 7, testResults: [{name: "a.test.js", assertionResults: [
    {fullName: "a", status: "passed"}, {fullName: "b", status: "pending"}, {fullName: "c", status: "disabled"},
    {fullName: "d", status: "todo"}, {fullName: "e", status: "focused"}, {fullName: "f", status: "weird"},
    {fullName: "g", status: "failed"}]}]}' > "$BATS_TEST_TMPDIR/jest.json"
  ev s1 calibration --test-report "jest-json:$R" -- sh -c "$(write_report "$BATS_TEST_TMPDIR/jest.json" 1)"
  [ "$(mq s1 '.runs[0].tests | [.status, .passed, .failed, .skipped, .todo, .other, .total] | join(",")')" = "ok,1,1,2,1,2,7" ]
}

@test "a report whose numTotalTests disagrees with its test list is invalid" {
  jq '.numTotalTests = 99' "$FIX/vitest5-pass.json" > "$BATS_TEST_TMPDIR/bad.json"
  ev s1 calibration --test-report "jest-json:$R" -- sh -c "$(write_report "$BATS_TEST_TMPDIR/bad.json" 0)"
  [ "$(mq s1 '.runs[0].tests.status')" = "invalid" ]
}

@test "a report path outside .vetdd/ and not ignored is a usage error; nothing runs, no run is recorded" {
  run ev s1 calibration --test-report jest-json:report.json -- touch ran.txt
  [ "$status" -eq 2 ]
  [[ "$output" == *"--test-report"* ]]
  [ ! -e ran.txt ]
  [ ! -e "$REPO/.vetdd/evidence/s1/meta.json" ]
}

@test "a report path that leaves the repository or points into the evidence is a usage error" {
  local p
  for p in ../outside.json "$BATS_TEST_TMPDIR/abs.json" .vetdd/evidence/s1/meta.json sub/../.vetdd/r.json; do
    run ev s1 calibration --test-report "jest-json:$p" -- touch ran.txt
    [ "$status" -eq 2 ] || { echo "accepted: $p"; false; }
    [ ! -e ran.txt ]
  done
  mkdir -p .vetdd/evidence/s1 && ln -s evidence/s1 .vetdd/lnk
  run ev s1 calibration --test-report jest-json:.vetdd/lnk/meta.json -- touch ran.txt
  [ "$status" -eq 2 ]
  [ ! -e ran.txt ]
}

@test "an unknown report format is a usage error" {
  run ev s1 calibration --test-report "junit:$R" -- touch ran.txt
  [ "$status" -eq 2 ]
  [ ! -e ran.txt ]
  run ev s1 calibration --test-report "jest-json:" -- touch ran.txt
  [ "$status" -eq 2 ]
}

@test "a report path is relative to the current directory and leaves the tree clean (F1)" {
  mkdir -p sub
  cd sub
  printf '0\n' > ../value.txt
  "$SCRIPTS/evidence.sh" s1 before --oracle-version v1 --oracle-file ../test.sh --test-report jest-json:../$R \
    -- sh -c "mkdir -p ../.vetdd/reports && cp '$FIX/vitest5-mixed.json' ../$R; cd .. && sh test.sh"
  printf '42\n' > ../value.txt
  "$SCRIPTS/evidence.sh" s1 after --test-report jest-json:../$R \
    -- sh -c "cp '$FIX/vitest5-pass.json' ../$R; cd .. && sh test.sh"
  [ "$(mq s1 '[.runs[].tests.status] | join(",")')" = "ok,ok" ]
  [ "$(mq s1 '.runs[1].tests.passed')" = "9" ]
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a report path outside .vetdd/reports/ is a usage error, even when git-ignored (F1)" {
  mkdir -p ignored && printf 'keep\n' > ignored/r.json
  run ev s1 calibration --test-report "jest-json:ignored/r.json" -- true
  [ "$status" -eq 2 ]
  [ "$(cat ignored/r.json)" = "keep" ]
  mkdir -p .vetdd/judge-logs && printf 'keep\n' > .vetdd/judge-logs/x.log
  run ev s1 calibration --test-report "jest-json:.vetdd/judge-logs/x.log" -- true
  [ "$status" -eq 2 ]
  [ "$(cat .vetdd/judge-logs/x.log)" = "keep" ]
}

@test "a tracked report spelled in another letter case is never deleted (F1)" {
  mkdir -p .vetdd/reports && printf 'keep\n' > .vetdd/reports/tracked.json
  git add -f .vetdd/reports/tracked.json && git commit -q -m tracked
  [ -e .vetdd/reports/TRACKED.json ] || skip "the file system is case-sensitive"
  run ev s1 calibration --test-report "jest-json:.vetdd/reports/TRACKED.json" -- true
  [ "$status" -eq 2 ]
  [ "$(cat .vetdd/reports/tracked.json)" = "keep" ]
}

@test "without --test-report the run has no tests field" {
  ev s1 calibration -- true
  [ "$(mq s1 '.runs[0] | has("tests")')" = "false" ]
}

@test "meta.json with ok, missing, and invalid reports validates against the schema; a bad tests object does not" {
  ev s1 calibration --test-report "jest-json:$R" -- sh -c "$(write_report "$FIX/vitest5-mixed.json" 1)"
  ev s1 calibration --test-report "jest-json:$R" -- true
  ev s1 calibration --test-report "jest-json:$R" -- sh -c "echo nope > $R"
  ev s1 calibration -- true
  run validate_schema "$REPO/.vetdd/evidence/s1/meta.json"
  [ "$output" = "valid" ]
  tamper s1 '.runs[1].tests.status = "maybe"'
  run validate_schema "$REPO/.vetdd/evidence/s1/meta.json"
  [ "$status" -ne 0 ]
  tamper s1 '.runs[1].tests.status = "missing" | .runs[0].tests.extra = 1'
  run validate_schema "$REPO/.vetdd/evidence/s1/meta.json"
  [ "$status" -ne 0 ]
  tamper s1 'del(.runs[0].tests.extra) | del(.runs[0].tests.passed)'
  run validate_schema "$REPO/.vetdd/evidence/s1/meta.json"
  [ "$status" -ne 0 ]
}

@test "integration: real vitest in a ts-kata copy, through evidence.sh" {
  local kata="$VETDD_ROOT/fixtures/ts-kata"
  [ -x "$kata/node_modules/.bin/vitest" ] || skip "fixtures/ts-kata/node_modules is missing"
  local K="$BATS_TEST_TMPDIR/kata"
  mkdir -p "$K" && cp -R "$kata/package.json" "$kata/tsconfig.json" "$kata/src" "$K/"
  ln -s "$kata/node_modules" "$K/node_modules"
  cat > "$K/src/mixed.test.ts" <<'EOF'
import { expect, it } from "vitest";
it("passes", () => { expect(1 + 1).toBe(2); });
it("fails", () => { expect(1 + 1).toBe(3); });
it.skip("is skipped", () => {});
it.todo("is a todo");
EOF
  cd "$K" && git init -q && printf 'node_modules\n' > .gitignore && git add -A && git commit -q -m init
  run "$SCRIPTS/evidence.sh" k1 calibration --test-report jest-json:.vetdd/reports/vitest.json \
    -- ./node_modules/.bin/vitest run --reporter=default --reporter=json --outputFile.json=.vetdd/reports/vitest.json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run jq -r '.runs[0] | [.outcome, .tests.status, .tests.passed, .tests.failed, .tests.skipped, .tests.todo, .tests.total] | join(",")' \
    "$K/.vetdd/evidence/k1/meta.json"
  [ "$output" = "target_failure,ok,10,1,1,1,13" ]
  [ -z "$(git status --porcelain --untracked-files=all | grep -v '^?? .vetdd/')" ]
}

@test "a report path through a directory symlink under .vetdd/ is refused before anything is deleted (B1)" {
  mkdir -p .vetdd sub && printf 'keep\n' > sub/keep.json && git add sub/keep.json && git commit -q -m keep
  ln -s ../sub .vetdd/lnk
  run ev s1 calibration --test-report "jest-json:.vetdd/lnk/keep.json" -- true
  [ "$status" -eq 2 ]
  [ "$(cat sub/keep.json)" = "keep" ]
  [ ! -e "$REPO/.vetdd/evidence/s1/meta.json" ]
}

@test "a report path with // or a missing parent cannot reach the evidence (B1)" {
  run ev s1 calibration --test-report "jest-json:.vetdd//evidence/s1/meta.json" -- true
  [ "$status" -eq 2 ]
  [ ! -e "$REPO/.vetdd/evidence/s1/meta.json" ]
  mkdir -p .vetdd/evidence/s2
  ln -s evidence/s2 .vetdd/lnk2
  run ev s2 calibration --test-report "jest-json:.vetdd/lnk2/x/out.json" -- true
  [ "$status" -eq 2 ]
}

@test "an empty report or two concatenated reports is status invalid and the run is still recorded (B2)" {
  run ev s1 calibration --test-report "jest-json:$R" -- sh -c "mkdir -p .vetdd/reports && : > $R; exit 1"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s1 '.runs[0] | [.outcome, .tests.status] | join(",")')" = "target_failure,invalid" ]
  run ev s1 calibration --test-report "jest-json:$R" -- sh -c "mkdir -p .vetdd/reports && cat '$FIX/vitest5-pass.json' '$FIX/vitest5-pass.json' > $R"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s1 '.runs[1] | [.outcome, .tests.status] | join(",")')" = "pass,invalid" ]
}

@test "an absolute report path spelled through a symlink to the repository is accepted (B3)" {
  ln -s "$REPO" "$BATS_TEST_TMPDIR/alias"
  run ev s1 calibration --test-report "jest-json:$BATS_TEST_TMPDIR/alias/$R" -- sh -c "$(write_report "$FIX/vitest5-pass.json" 0)"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s1 '.runs[0].tests.status')" = "ok" ]
}

@test "the evidence directory itself is refused as a report path, and nothing is left behind (D1)" {
  run ev s1 calibration --test-report "jest-json:.vetdd/evidence" -- true
  [ "$status" -eq 2 ]
  [ ! -e "$REPO/.vetdd/evidence/s1/meta.json" ]
  run ev s1 calibration --test-report "jest-json:.VETDD/Evidence" -- true
  [ "$status" -eq 2 ]
}

@test "a tracked file under .vetdd/ is never deleted as a stale report (D1)" {
  mkdir -p .vetdd && printf 'keep\n' > .vetdd/tracked.json && git add -f .vetdd/tracked.json && git commit -q -m tracked
  run ev s1 calibration --test-report "jest-json:.vetdd/tracked.json" -- true
  [ "$status" -eq 2 ]
  [ "$(cat .vetdd/tracked.json)" = "keep" ]
}

@test "only .vetdd/reports/ spelled exactly is a report location; another case is refused on any file system (H1)" {
  . "$SCRIPTS/lib/common.sh"; . "$SCRIPTS/lib/test-report.sh"
  root="$(pwd -P)"
  vetdd_report_allowed "$root" .vetdd/reports/x.json
  run ! vetdd_report_allowed "$root" .VETDD/reports/x.json
  run ! vetdd_report_allowed "$root" .vetdd/Reports/x.json
}

@test "a tracked report is refused even when the index spells it in another case (H1)" {
  . "$SCRIPTS/lib/common.sh"; . "$SCRIPTS/lib/test-report.sh"
  mkdir -p .vetdd/reports && printf 'keep\n' > .vetdd/reports/t.json
  git add -f .vetdd/reports/t.json && git commit -q -m t
  run ! vetdd_report_allowed "$(pwd -P)" .vetdd/reports/T.json
}

@test "the report's directory exists before the command runs, for runners that do not create it (J1)" {
  [ ! -e .vetdd/reports ]
  ev s1 calibration --test-report "jest-json:.vetdd/reports/deep/r.json" \
    -- sh -c "cp '$FIX/vitest5-pass.json' .vetdd/reports/deep/r.json"
  [ "$(mq s1 '.runs[0] | [.outcome, .tests.status] | join(",")')" = "pass,ok" ]
}

@test "a git failure in the tracked check refuses the report path instead of allowing it (J1)" {
  . "$SCRIPTS/lib/common.sh"; . "$SCRIPTS/lib/test-report.sh"
  root="$(pwd -P)"
  mkdir -p "$BATS_TEST_TMPDIR/fakegit"
  printf '#!/bin/sh\nexit 128\n' > "$BATS_TEST_TMPDIR/fakegit/git"; chmod +x "$BATS_TEST_TMPDIR/fakegit/git"
  PATH="$BATS_TEST_TMPDIR/fakegit:$PATH" run vetdd_report_allowed "$root" .vetdd/reports/x.json
  [ "$status" -ne 0 ]
}

@test "a report path holding something other than a regular file is invalid, not missing (L1)" {
  ev s1 calibration --test-report "jest-json:$R" -- sh -c "mkfifo $R"
  [ "$(mq s1 '.runs[0].tests.status')" = "invalid" ]
}

@test "a report path through a regular file says the path is unusable, not that it is a link (L2)" {
  mkdir -p .vetdd/reports && printf 'x\n' > .vetdd/reports/r.json
  run ev s1 calibration --test-report "jest-json:.vetdd/reports/r.json/x.json" -- true
  [ "$status" -eq 2 ]
  [[ "$output" == *"is not a usable path inside the repository"* ]]
}

@test "a report path ending in / or /. or /.. is a usage error and deletes nothing (N1)" {
  mkdir -p .vetdd/reports && printf 'other\n' > .vetdd/reports/s1.json
  for p in .vetdd/reports/s1.json/x/ .vetdd/reports/a/ .vetdd/reports/a/. .vetdd/reports/a/..; do
    run ev s2 calibration --test-report "jest-json:$p" -- true
    [ "$status" -eq 2 ] || { echo "$p: $output"; false; }
  done
  [ "$(cat .vetdd/reports/s1.json)" = "other" ]
}

@test "a report path running through a file or a dangling link at any depth says the path is unusable (O1)" {
  mkdir -p .vetdd/reports && printf 'x\n' > .vetdd/reports/r.json && ln -s nowhere .vetdd/reports/dang
  for p in .vetdd/reports/r.json/x/y.json .vetdd/reports/dang/x/y.json; do
    run ev s1 calibration --test-report "jest-json:$p" -- true
    [ "$status" -eq 2 ] || { echo "$p: $output"; false; }
    [[ "$output" == *"is not a usable path inside the repository"* ]] || { echo "$p: $output"; false; }
  done
  [ "$(cat .vetdd/reports/r.json)" = "x" ]
}

@test "a report without a numeric numTotalTests is invalid (P2 from review)" {
  for body in '{"testResults":[]}' '{"testResults":[],"numTotalTests":"0"}'; do
    rm -rf "$REPO/.vetdd/evidence/s1"
    ev s1 calibration --test-report "jest-json:$R" -- sh -c "mkdir -p .vetdd/reports && printf '%s' '$body' > $R"
    [ "$(mq s1 '.runs[0].tests.status')" = "invalid" ] || { echo "$body"; false; }
  done
}
