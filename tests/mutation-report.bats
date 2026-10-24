#!/usr/bin/env bats
# The mutation audit record (PR7a): evidence.sh --audit mutation --mutation-report stryker-json:<path>
# reads a Stryker JSON report (mutation-testing-report-schema 1.x) after a calibration run and puts
# its counts, the sha256 of every mutated file's source, and a copy of the report on the run.
# Rule 10c, which judges the record, is PR7b.

load test_helper

FIX_STRYKER="$BATS_TEST_DIRNAME/fixtures/reports/stryker10-range.json"

setup() {
  make_repo
  mkdir -p src
  # The product file is the one the saved report mutated, byte for byte.
  jq -j '.files["src/dueDate.ts"].source' "$FIX_STRYKER" > src/dueDate.ts
  # mrun.sh plays Stryker: it writes $REPORT (if set) where the record reads it, and exits $EXIT.
  printf 'mkdir -p .vetdd/reports\n[ -z "${REPORT:-}" ] || cp "$REPORT" .vetdd/reports/m.json\nexit "${EXIT:-0}"\n' > mrun.sh
  git add -A && git commit -q -m product
  R=.vetdd/reports/m.json
}

# report <jq filter>: the saved report rooted at this repository, changed by the filter, in a temp file.
report() {
  jq --arg r "$REPO" ".projectRoot = \$r | ${1:-.}" "$FIX_STRYKER" > "$BATS_TEST_TMPDIR/rep.json"
  printf '%s' "$BATS_TEST_TMPDIR/rep.json"
}
mut() { ev s1 calibration --audit mutation --mutation-report "stryker-json:$R" "$@" -- sh mrun.sh; }
no_control() { ! printf '%s' "$1" | LC_ALL=C grep -q "$(printf '[\001-\010\013-\037\177]')"; }

@test "a Stryker report is recorded: kind, format, path, status, counts, mutated files, and a hashed copy" {
  REPORT="$(report)" run mut
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s1 '.runs[-1].kind')" = calibration ]
  [ "$(mq s1 '.runs[-1].audit.kind')" = mutation ]
  [ "$(mq s1 '.runs[-1].audit.report.format')" = stryker-json ]
  [ "$(mq s1 '.runs[-1].audit.report.path')" = "$R" ]
  [ "$(mq s1 '.runs[-1].audit.report.status')" = ok ]
  [ "$(mq s1 '.runs[-1].audit.report.counts | [.killed, .survived, .no_coverage, .timeout, .compile_error, .runtime_error, .ignored, .total] | map(tostring) | join(" ")')" = "0 8 2 0 0 0 0 10" ]
  [ "$(mq s1 '.runs[-1].audit.report.files | length')" = 1 ]
  [ "$(mq s1 '.runs[-1].audit.report.files[0].path')" = src/dueDate.ts ]
  [ "$(mq s1 '.runs[-1].audit.report.files[0].sha256')" = "$(sha256_of src/dueDate.ts)" ]
  local copy; copy="$(mq s1 '.runs[-1].audit.report.copy')"
  [ "$copy" = runs/001-mutation.json ]
  [ "$(mq s1 '.runs[-1].audit.report.sha256')" = "$(sha256_of ".vetdd/evidence/s1/$copy")" ]
  # The copy keeps config.mutate (the line ranges) and each mutant, for the judge.
  [ "$(jq -c '.config.mutate' ".vetdd/evidence/s1/$copy")" = '["src/dueDate.ts:85-95"]' ]
}

@test "every Stryker status is counted in its own bucket; Timeout is not folded into killed" {
  REPORT="$(report '.files["src/dueDate.ts"].mutants |= [range(0; length) as $i | .[$i] | .status = (["Killed","Survived","NoCoverage","Timeout","CompileError","RuntimeError","Ignored","Killed","Killed","Survived"][$i])]')" run mut
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s1 '.runs[-1].audit.report.counts | [.killed, .survived, .no_coverage, .timeout, .compile_error, .runtime_error, .ignored, .total] | map(tostring) | join(" ")')" = "3 2 1 1 1 1 1 10" ]
}

@test "the file hash is of the source the report mutated, not of the file on disk now" {
  printf '// changed after the run\n' >> src/dueDate.ts
  REPORT="$(report)" run mut
  [ "$status" -eq 0 ]
  [ "$(mq s1 '.runs[-1].audit.report.files[0].sha256')" != "$(sha256_of src/dueDate.ts)" ]
  [ "$(mq s1 '.runs[-1].audit.report.files[0].sha256')" = "$(jq -j '.files["src/dueDate.ts"].source' "$FIX_STRYKER" | shasum -a 256 | cut -d' ' -f1)" ]
}

@test "a report under a package directory gets repository paths from projectRoot" {
  mkdir -p pkg/src && git mv src/dueDate.ts pkg/src/dueDate.ts && git commit -q -m move
  jq --arg r "$REPO/pkg" '.projectRoot = $r' "$FIX_STRYKER" > "$BATS_TEST_TMPDIR/pkg.json"
  REPORT="$BATS_TEST_TMPDIR/pkg.json" run mut
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s1 '.runs[-1].audit.report.status')" = ok ]
  [ "$(mq s1 '.runs[-1].audit.report.files[0].path')" = pkg/src/dueDate.ts ]
}

@test "no report after the run is recorded as missing, with a warning; the run is still recorded" {
  run mut
  [ "$status" -eq 0 ]
  [[ "$output" == *"mutation report"*"missing"* ]]
  [ "$(mq s1 '.runs[-1].audit.report | [.format, .path, .status] | join(" ")')" = "stryker-json $R missing" ]
  [ "$(mq s1 '.runs[-1].audit.report | has("counts")')" = false ]
  [ ! -e .vetdd/evidence/s1/runs/001-mutation.json ]
}

@test "a report left by an earlier run is removed before the command runs, so it is never read as this run's" {
  mkdir -p .vetdd/reports && cp "$(report)" "$R"
  run mut
  [ "$(mq s1 '.runs[-1].audit.report.status')" = missing ]
}

@test "a report that is not a usable Stryker report is invalid and nothing of it is kept" {
  local f
  # .files = {} is "empty" since #21 (its own test).
  for f in '"x"' 'del(.files)' '.schemaVersion = "2.0"' 'del(.schemaVersion)' \
           '.files["src/dueDate.ts"].mutants[0].status = "Pending"' \
           '.files["src/dueDate.ts"].mutants[0].status = "Exploded"' \
           '.files["src/dueDate.ts"].source = 5' '.files["src/dueDate.ts"].mutants = {}' \
           '.projectRoot = "/tmp"' '.projectRoot = 5' \
           '.files = {"../outside.ts": .files["src/dueDate.ts"]}' \
           '.files = {"/etc/passwd": .files["src/dueDate.ts"]}' \
           '.files = {"src/a\u001b[2J.ts": .files["src/dueDate.ts"]}'; do
    rm -rf .vetdd
    REPORT="$(report "$f")" run mut
    [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ] || { echo "accepted: $f"; false; }
    [ ! -e .vetdd/evidence/s1/runs/001-mutation.json ]
    no_control "$output" || { echo "$f: control characters in output"; false; }
  done
  # Not JSON, two objects, and an empty file.
  for f in 'not json' '{} {}' ''; do
    rm -rf .vetdd
    printf '%s' "$f" > "$BATS_TEST_TMPDIR/raw.json"
    REPORT="$BATS_TEST_TMPDIR/raw.json" run mut
    [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ] || { echo "accepted raw: $f"; false; }
  done
}

@test "a projectRoot that is a link out of the repository is invalid" {
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere/src"
  cp src/dueDate.ts "$BATS_TEST_TMPDIR/elsewhere/src/"
  ln -s "$BATS_TEST_TMPDIR/elsewhere" out
  jq --arg r "$REPO/out" '.projectRoot = $r' "$FIX_STRYKER" > "$BATS_TEST_TMPDIR/out.json"
  REPORT="$BATS_TEST_TMPDIR/out.json" run mut
  [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ]
}

@test "--mutation-report and --audit mutation go together, on a calibration run, before the command runs" {
  printf '#!/bin/sh\ntouch ran.flag\n' > flag.sh
  run ev s1 calibration --audit mutation -- sh flag.sh
  [ "$status" -eq 2 ]; [[ "$output" == *"--mutation-report"* ]]
  run ev s1 calibration --mutation-report "stryker-json:$R" -- sh flag.sh
  [ "$status" -eq 2 ]; [[ "$output" == *"--audit mutation"* ]]
  run ev s1 calibration --audit undefined-imports --mutation-report "stryker-json:$R" -- sh flag.sh
  [ "$status" -eq 2 ]
  run ev s1 after --audit mutation --mutation-report "stryker-json:$R" -- sh flag.sh
  [ "$status" -eq 2 ]
  run ev s1 calibration --audit mutation --mutation-report "jest-json:$R" -- sh flag.sh
  [ "$status" -eq 2 ]; [[ "$output" == *"stryker-json:"* ]]
  run ev s1 calibration --audit mutation --mutation-report stryker-json: -- sh flag.sh
  [ "$status" -eq 2 ]
  run ev s1 calibration --audit mutation --mutation-report
  [ "$status" -eq 2 ]
  [ ! -e ran.flag ]
  [ ! -e .vetdd/evidence/s1/meta.json ]
}

@test "the mutation report path follows the test-report rules: untracked, under .vetdd/reports/, no link" {
  printf '#!/bin/sh\ntouch ran.flag\n' > flag.sh
  run ev s1 calibration --audit mutation --mutation-report stryker-json:reports/m.json -- sh flag.sh
  [ "$status" -eq 2 ]
  mkdir -p .vetdd/reports && printf '{}' > .vetdd/reports/t.json && git add -f .vetdd/reports/t.json
  run ev s1 calibration --audit mutation --mutation-report stryker-json:.vetdd/reports/t.json -- sh flag.sh
  [ "$status" -eq 2 ]
  ln -s "$BATS_TEST_TMPDIR/x.json" .vetdd/reports/l.json
  run ev s1 calibration --audit mutation --mutation-report stryker-json:.vetdd/reports/l.json -- sh flag.sh
  [ "$status" -eq 2 ]
  [ ! -e ran.flag ]
}

@test "a mutation run is not a red, never trips 10a, and does not ask the slice for an undefined-imports audit" {
  record_good_slice s1
  # Every mutant killed, so rule 10c (PR7b) has nothing to say either.
  local K; K="$(report '.files["src/dueDate.ts"].mutants |= map(.status = "Killed") | .config.testRunner = "command" | .config.commandRunner.command = "npx --no-install vitest run test.sh"')"
  REPORT="$K" EXIT=1 ev s1 calibration --audit mutation --mutation-report "stryker-json:$R" -- sh mrun.sh >/dev/null 2>&1 || true
  REPORT="$K" EXIT=0 ev s1 calibration --audit mutation --mutation-report "stryker-json:$R" -- sh mrun.sh >/dev/null 2>&1
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "s1: OK" ]
  # And it never stands in for the red of a slice.
  printf '42\n' > value.txt
  REPORT="$(report)" EXIT=1 ev s2 calibration --audit mutation --mutation-report "stryker-json:$R" --oracle-version v1 --oracle-file test.sh -- sh mrun.sh >/dev/null 2>&1 || true
  ev s2 after -- sh test.sh >/dev/null 2>&1
  run check s2
  [[ "$output" == *"s2: FAIL (1: no red run"* ]]
}

@test "a mutation note in audits does not ask the slice for an undefined-imports audit" {
  record_good_slice s1
  printf 'python\n' > "$BATS_TEST_TMPDIR/n.txt"
  "$SCRIPTS/audit-note.sh" s1 --kind mutation --not-applicable --reason-file "$BATS_TEST_TMPDIR/n.txt"
  run check s1
  [ "$output" = "s1: OK" ] || { echo "$output"; false; }
}

@test "the mutation record validates against the schema, ok and missing alike, and a mutation note too" {
  REPORT="$(report)" mut >/dev/null 2>&1
  mut >/dev/null 2>&1
  tamper s1 '.audits = [{"kind": "mutation", "status": "not_applicable", "reason": "python", "recorded_at": "2026-10-04T00:00:00Z"}]'
  run validate_schema "$REPO/.vetdd/evidence/s1/meta.json"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "the schema rejects a mutation audit without a report, a report on an undefined-imports audit, and bad counts" {
  REPORT="$(report)" mut >/dev/null 2>&1
  local f
  for f in 'del(.runs[0].audit.report)' '.runs[0].audit.kind = "undefined-imports"' \
           '.runs[0].audit.report.counts.survived = -1' 'del(.runs[0].audit.report.counts.ignored)' \
           '.runs[0].audit.report.counts.extra = 1' '.runs[0].audit.report.files[0].sha256 = "x"' \
           '.runs[0].audit.report.status = "partial"' '.runs[0].audit.report.format = "jest-json"' \
           'del(.runs[0].audit.report.copy)' '.runs[0].audit.report.extra = 1'; do
    cp "$REPO/.vetdd/evidence/s1/meta.json" "$BATS_TEST_TMPDIR/ok.json"
    jq "$f" "$BATS_TEST_TMPDIR/ok.json" > "$BATS_TEST_TMPDIR/bad.json"
    run validate_schema "$BATS_TEST_TMPDIR/bad.json"
    [ "$status" -ne 0 ] || { echo "accepted: $f"; false; }
  done
}

# --- review round 1 ------------------------------------------------------------------------------

@test "file keys must be plain relative paths, also under a package projectRoot (G1)" {
  mkdir -p pkg
  local k
  for k in '/etc/passwd' '' 'src//dueDate.ts' 'src/./dueDate.ts' 'src/' './src/dueDate.ts' 'src/../src/dueDate.ts'; do
    rm -rf .vetdd
    jq --arg r "$REPO/pkg" --arg k "$k" '.projectRoot = $r | .files = {($k): .files["src/dueDate.ts"]}' "$FIX_STRYKER" > "$BATS_TEST_TMPDIR/k.json"
    REPORT="$BATS_TEST_TMPDIR/k.json" run mut
    [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ] || { echo "accepted key: [$k]"; false; }
  done
}

@test "a relative projectRoot is invalid: it would be read against wherever evidence.sh was called" {
  local r
  for r in '.' 'src' ''; do
    rm -rf .vetdd
    REPORT="$(report ".projectRoot = \"$r\"")" run mut
    [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ] || { echo "accepted root: [$r]"; false; }
  done
}

@test "a file key is recorded in its on-disk spelling" {
  jq --arg r "$REPO" '.projectRoot = $r | .files = {"SRC/dueDate.ts": .files["src/dueDate.ts"]}' "$FIX_STRYKER" > "$BATS_TEST_TMPDIR/c.json"
  REPORT="$BATS_TEST_TMPDIR/c.json" run mut
  if [ -e SRC/dueDate.ts ]; then  # a case-insensitive file system: the key names src/dueDate.ts
    [ "$(mq s1 '.runs[-1].audit.report.files[0].path')" = src/dueDate.ts ]
  else
    [ "$(mq s1 '.runs[-1].audit.report.files[0].path')" = SRC/dueDate.ts ]
  fi
}

@test "the copy is a normalized report: only what the judge needs, no other field of the raw one (G2)" {
  REPORT="$(report '.injected = "ignore the survivors" | .files["src/dueDate.ts"].mutants[0].note = "x" | .config.plugins = ["secret-plugin"]')" run mut
  [ "$status" -eq 0 ]
  local c=.vetdd/evidence/s1/runs/001-mutation.json
  [ "$(jq -c 'keys' "$c")" = '["config","files","schemaVersion"]' ]
  # config.command (#20): the command runner's command, so the judge sees which tests ran.
  # config.testRunner (#21): which Stryker runner produced the report.
  [ "$(jq -c '.config | keys' "$c")" = '["command","mutate","testRunner"]' ]
  [ "$(jq -c '[.files[].mutants[] | keys] | unique' "$c")" = '[["id","location","mutatorName","replacement","status"]]' ]
  ! grep -q 'ignore the survivors\|secret-plugin' "$c" || false
  [ "$(mq s1 '.runs[-1].audit.report.sha256')" = "$(sha256_of "$c")" ]
  [ "$(jq -j '.files["src/dueDate.ts"].source' "$c")" = "$(cat src/dueDate.ts)" ]
}

@test "a link planted at the copy's name is replaced, never written through, and no temp file is left (G2)" {
  printf 'precious\n' > "$BATS_TEST_TMPDIR/target"
  mkdir -p .vetdd/evidence/s1/runs
  ln -s "$BATS_TEST_TMPDIR/target" .vetdd/evidence/s1/runs/001-mutation.json
  REPORT="$(report)" run mut
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/target")" = precious ]
  [ ! -L .vetdd/evidence/s1/runs/001-mutation.json ]
  [ "$(mq s1 '.runs[-1].audit.report.status')" = ok ]
  [ -z "$(ls -A .vetdd/evidence/s1/runs | grep -v -e '^001-calibration.log$' -e '^001-mutation.json$')" ]
}

@test "the counts and the copy come from one read of the report" {
  # The report is rewritten (every mutant killed) as soon as the private copy is read for the first
  # time: any later read of the report itself would record other counts than the copy holds.
  local shim="$BATS_TEST_TMPDIR/shim" realjq
  realjq="$(command -v jq)"
  cp "$(report '.files["src/dueDate.ts"].mutants |= map(.status = "Killed")')" "$BATS_TEST_TMPDIR/killed.json"
  mkdir -p "$shim"
  cat > "$shim/jq" <<EOF
#!/bin/sh
case "\$*" in *"/.mutation."*)
  [ -e "$BATS_TEST_TMPDIR/swapped" ] || { cp "$BATS_TEST_TMPDIR/killed.json" "$REPO/$R"; touch "$BATS_TEST_TMPDIR/swapped"; } ;;
esac
exec "$realjq" "\$@"
EOF
  chmod +x "$shim/jq"
  PATH="$shim:$PATH" REPORT="$(report)" run mut
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -e "$BATS_TEST_TMPDIR/swapped" ]
  [ "$(mq s1 '.runs[-1].audit.report.status')" = ok ]
  [ "$(mq s1 '.runs[-1].audit.report.counts.survived')" = 8 ]
  [ "$(jq '[.files[].mutants[] | select(.status == "Survived")] | length' .vetdd/evidence/s1/runs/001-mutation.json)" = 8 ]
  [ "$(mq s1 '.runs[-1].audit.report.sha256')" = "$(sha256_of .vetdd/evidence/s1/runs/001-mutation.json)" ]
}

@test "an audit mark of an unknown kind on a run opts the slice in to rule 10 (fails closed)" {
  record_good_slice s1
  REPORT="$(report '.files["src/dueDate.ts"].mutants |= map(.status = "Killed") | .config.testRunner = "command" | .config.commandRunner.command = "npx --no-install vitest run test.sh"')" ev s1 calibration --audit mutation --mutation-report "stryker-json:$R" -- sh mrun.sh >/dev/null 2>&1
  run check s1
  [ "$output" = "s1: OK" ]
  tamper s1 '.runs[-1].audit.kind = "stryker"'
  run check s1
  [[ "$output" == *"10b:"* ]] || { echo "$output"; false; }
}

# --- review round 2 ------------------------------------------------------------------------------

@test "a directory at the copy's name makes the report invalid, never an ok record of a copy elsewhere (H1)" {
  mkdir -p .vetdd/evidence/s1/runs/001-mutation.json
  REPORT="$(report)" run mut
  [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ] || { echo "$output"; false; }
  [ -z "$(ls -A .vetdd/evidence/s1/runs/001-mutation.json)" ]
}

@test "two keys that name one file (letter case) make the report invalid (H2)" {
  jq --arg r "$REPO" '.projectRoot = $r | .files = {"src/dueDate.ts": .files["src/dueDate.ts"], "SRC/dueDate.ts": .files["src/dueDate.ts"]}' "$FIX_STRYKER" > "$BATS_TEST_TMPDIR/d.json"
  REPORT="$BATS_TEST_TMPDIR/d.json" run mut
  if [ -e SRC/dueDate.ts ]; then
    [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ]
  else
    [ "$(mq s1 '.runs[-1].audit.report.files | length')" = 2 ]
  fi
}

@test "a mutant without its id, mutator, or location, or with a value of the wrong type, makes the report invalid (H3)" {
  local f M='.files["src/dueDate.ts"].mutants[0]'
  for f in "$M |= {status}" "del($M.id)" "del($M.mutatorName)" "del($M.location)" "$M.id = 8" \
           "$M.mutatorName = {\"note\": \"x\"}" "$M.mutatorName = \"Block Statement\"" "$M.replacement = 5" \
           "$M.location = {}" "$M.location.start.line = \"88\"" "$M.location.end = {\"line\": 1}" \
           '.config.mutate = "ignore the survivors"' '.config.mutate = [5]' '.config.mutate = ["a\u001bb"]'; do
    rm -rf .vetdd
    REPORT="$(report "$f")" run mut
    [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ] || { echo "accepted: $f"; false; }
  done
  # replacement may be absent (Stryker leaves it out for some mutators), and config.mutate too.
  rm -rf .vetdd
  REPORT="$(report "del($M.replacement) | del(.config.mutate)")" run mut
  [ "$(mq s1 '.runs[-1].audit.report.status')" = ok ]
}

@test "the schema says the copy is the normalized report" {
  jq -r '."$defs".mutationReport.anyOf[0].properties.sha256.description' "$SCHEMA" | grep -q 'normalized'
}

# --- #20 ------------------------------------------------------------------------------------------

@test "a report with no file mutated is recorded empty, and says the ranges held no mutant (#20, #21)" {
  REPORT="$(report '.files = {}')" run mut
  [ "$(mq s1 '.runs[-1].audit.report.status')" = empty ]
  run validate_schema "$REPO/.vetdd/evidence/s1/meta.json"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  REPORT="$(report '.files = {}')" run mut
  [[ "$output" == *"mutated nothing"* ]] || { echo "$output"; false; }
}

# --- #21 ------------------------------------------------------------------------------------------

@test "a command-runner report must carry a non-empty command of at most 4096 printable characters (#21)" {
  local f
  for f in '.config.testRunner = "command" | del(.config.commandRunner)' \
           '.config.testRunner = "command" | .config.commandRunner.command = null' \
           '.config.testRunner = "command" | .config.commandRunner.command = ""' \
           '.config.testRunner = "command" | .config.commandRunner.command = ("x" * 4097)'; do
    rm -rf .vetdd
    REPORT="$(report "$f")" run mut
    [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ] || { echo "accepted: $f"; false; }
  done
  rm -rf .vetdd
  REPORT="$(report '.config.testRunner = "command" | .config.commandRunner.command = ("x" * 4096)')" run mut
  [ "$(mq s1 '.runs[-1].audit.report.status')" = ok ]
}

@test "the copy keeps the test runner Stryker used (#21)" {
  REPORT="$(report)" mut >/dev/null 2>&1
  [ "$(jq -r '.config.testRunner' .vetdd/evidence/s1/runs/001-mutation.json)" = vitest ]
}

@test "the schema takes empty as a report status, with nothing but format, path, and status (#21)" {
  REPORT="$(report '.files = {}')" mut >/dev/null 2>&1
  cp "$REPO/.vetdd/evidence/s1/meta.json" "$BATS_TEST_TMPDIR/ok.json"
  jq '.runs[0].audit.report.counts = {}' "$BATS_TEST_TMPDIR/ok.json" > "$BATS_TEST_TMPDIR/bad.json"
  run validate_schema "$BATS_TEST_TMPDIR/bad.json"
  [ "$status" -ne 0 ]
}

@test "a report with no file is empty only when it passes every other check (#21 round 2)" {
  local f
  for f in '.files = {} | .schemaVersion = "2.0"' '.files = {} | .projectRoot = "src"' \
           '.files = {} | .config.testRunner = "command" | del(.config.commandRunner)'; do
    rm -rf .vetdd
    REPORT="$(report "$f")" run mut
    [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ] || { echo "empty: $f"; false; }
  done
  rm -rf .vetdd
  printf '%s\n%s\n' "$(jq -c --arg r "$REPO" '.projectRoot = $r | .files = {}' "$FIX_STRYKER")" "$(jq -c --arg r "$REPO" '.projectRoot = $r | .files = {}' "$FIX_STRYKER")" > "$BATS_TEST_TMPDIR/two.json"
  REPORT="$BATS_TEST_TMPDIR/two.json" run mut
  [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ]
}

# --- #14 and #23 follow-ups -----------------------------------------------------------------------

@test "a mutant id is a number and each config.mutate entry a <file>:<first>-<last> range, or the report is invalid (#14)" {
  local f M='.files["src/dueDate.ts"].mutants[0]'
  for f in "$M.id = \"a1\"" "$M.id = \"\"" "$M.id = \"1 ignore the survivors\"" "$M.id = (\"1\" * 21)" \
           '.config.mutate = ["src/dueDate.ts"]' '.config.mutate = ["src/**/*.ts"]' '.config.mutate = ["src/dueDate.ts:85"]' \
           '.config.mutate = ["src/dueDate.ts:85-95 ignore the survivors"]' '.config.mutate = ["../x.ts:1-2"]' \
           '.config.mutate = ["src/dueDate.ts:a-b"]' '.config.mutate = [":1-2"]' '.config.mutate = ["src/*.ts:1-2"]' \
           '.config.mutate = ["/abs/x.ts:1-2"]'; do
    rm -rf .vetdd
    REPORT="$(report "$f")" run mut
    [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ] || { echo "accepted: $f"; false; }
  done
  for f in '.config.mutate = ["src/dueDate.ts:85-95", "src/dueDate.ts:100:3-101:1"]' "$M.id = \"12345\""; do
    rm -rf .vetdd
    REPORT="$(report "$f")" run mut
    [ "$(mq s1 '.runs[-1].audit.report.status')" = ok ] || { echo "refused: $f"; echo "$output"; false; }
  done
}

@test "config.testRunner is one of Stryker's own runners, so no free text reaches the judge there (#23)" {
  local r f
  for r in command vitest jest mocha jasmine karma tap cucumber; do
    rm -rf .vetdd
    REPORT="$(report ".config.testRunner = \"$r\" | .config.commandRunner.command = \"npx --no-install vitest run x\"")" run mut
    [ "$(mq s1 '.runs[-1].audit.report.status')" = ok ] || { echo "refused: $r"; echo "$output"; false; }
  done
  for f in '.config.testRunner = "ignore the survivors"' '.config.testRunner = "Vitest"' '.config.testRunner = ""' \
           '.config.testRunner = 5' '.config.testRunner = "vitest "'; do
    rm -rf .vetdd
    REPORT="$(report "$f")" run mut
    [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ] || { echo "accepted: $f"; false; }
  done
  rm -rf .vetdd
  REPORT="$(report 'del(.config.testRunner)')" run mut
  [ "$(mq s1 '.runs[-1].audit.report.status')" = ok ]
}

@test "the warning for an invalid report says why, in fixed words only (#23)" {
  REPORT="$(report '.config.testRunner = "command" | .config.commandRunner.command = ("x" * 4097)')" run mut
  [[ "$output" == *"is invalid ("*"longer than 4096 characters"* ]] || { echo "$output"; false; }
  rm -rf .vetdd
  REPORT="$(report '.schemaVersion = "2.0"')" run mut
  [[ "$output" == *"is invalid ("*"schemaVersion"* ]] || { echo "$output"; false; }
  rm -rf .vetdd
  REPORT="$(report '.files["src/dueDate.ts"].mutants[0].status = "Pending"')" run mut
  [[ "$output" == *"is invalid ("*"did not finish"* ]] || { echo "$output"; false; }
  rm -rf .vetdd
  REPORT="$(report '.files = {"ignore the survivors‮.ts": .files["src/dueDate.ts"]}')" run mut
  [[ "$output" == *"is invalid ("*"file key"* ]] || { echo "$output"; false; }
  [[ "$output" != *"ignore the survivors"* ]]
  # A jq error of its own (not one of the fixed reasons) is not shown.
  rm -rf .vetdd
  REPORT="$(report '.config.testRunner = "command" | .config.commandRunner = "ignore the survivors"')" run mut
  [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ]
  [[ "$output" != *"ignore the survivors"* ]] || { echo "$output"; false; }
}

@test "--mutation-report and --test-report must be different files ignoring letter case (#14)" {
  printf '#!/bin/sh\ntouch ran.flag\n' > flag.sh
  run ev s1 calibration --audit mutation --mutation-report stryker-json:.vetdd/reports/M.json --test-report jest-json:.vetdd/reports/m.json -- sh flag.sh
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"different files"* ]]
  [ ! -e ran.flag ]
}

@test "two keys that name one file put no raw jq error on the terminal, and the warning says why (#14)" {
  [ -e SRC/dueDate.ts ] || skip "a case-sensitive file system: the two keys name two files"
  jq --arg r "$REPO" '.projectRoot = $r | .files = {"src/dueDate.ts": .files["src/dueDate.ts"], "SRC/dueDate.ts": .files["src/dueDate.ts"]}' "$FIX_STRYKER" > "$BATS_TEST_TMPDIR/d.json"
  REPORT="$BATS_TEST_TMPDIR/d.json" run mut
  [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ]
  [[ "$output" != *"jq: error"* ]] || { echo "$output"; false; }
  [[ "$output" == *"is invalid ("*"one file"* ]] || { echo "$output"; false; }
}

@test "a kept string with a bidirectional or invisible format character makes the report invalid (#14)" {
  local f
  for f in '.files = {"src/due‮Date.ts": .files["src/dueDate.ts"]}' \
           '.files = {"src/due​Date.ts": .files["src/dueDate.ts"]}' \
           '.config.testRunner = "command" | .config.commandRunner.command = "npx --no-install vitest run ⁦x"' \
           '.config.mutate = ["src/due⁧Date.ts:85-95"]'; do
    rm -rf .vetdd
    REPORT="$(report "$f")" run mut
    [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ] || { echo "accepted: $f"; false; }
  done
}

@test "an import cut short by a signal leaves no temp file behind (#14)" {
  local shim="$BATS_TEST_TMPDIR/shim" realjq
  realjq="$(command -v jq)"
  mkdir -p "$shim" "$BATS_TEST_TMPDIR/tmp"
  # The jq that writes the copy signals the shell running the import, as an interrupt would.
  printf '#!/bin/sh\ncase "$*" in *"map_values({source"*) kill -TERM "$PPID"; exit 1 ;; esac\nexec "%s" "$@"\n' "$realjq" > "$shim/jq"
  chmod +x "$shim/jq"
  PATH="$shim:$PATH" TMPDIR="$BATS_TEST_TMPDIR/tmp" REPORT="$(report)" run mut
  [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ] || { echo "$output"; false; }
  [ -z "$(ls -A .vetdd/evidence/s1/runs | grep -v -e '^001-calibration.log$')" ] || { ls -A .vetdd/evidence/s1/runs; false; }
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/tmp" | grep '^vetdd-source')" ]
}

@test "a report with another hard link, a report over 64 MiB, and a runs directory the command made a link are invalid (#14)" {
  # A hard link: the command put another name of a file outside the report directory at the report path.
  cp "$(report)" "$BATS_TEST_TMPDIR/outside.json"
  printf 'mkdir -p .vetdd/reports\nln "%s" .vetdd/reports/m.json\n' "$BATS_TEST_TMPDIR/outside.json" > hl.sh
  run ev s1 calibration --audit mutation --mutation-report "stryker-json:$R" -- sh hl.sh
  [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ] || { echo "$output"; false; }
  [[ "$output" == *"hard link"* ]] || { echo "$output"; false; }
  # Over the size limit: a usable report followed by 64 MiB of blanks (still one JSON object).
  rm -rf .vetdd
  cp "$(report)" "$BATS_TEST_TMPDIR/big.json"
  head -c 67108864 /dev/zero | LC_ALL=C tr '\000' ' ' >> "$BATS_TEST_TMPDIR/big.json"
  REPORT="$BATS_TEST_TMPDIR/big.json" run mut
  [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ] || { echo "$output"; false; }
  [[ "$output" == *"64 MiB"* ]] || { echo "$output"; false; }
  # runs/ swapped for a link out of the repository while the command ran: nothing is written there.
  rm -rf .vetdd
  mkdir -p "$BATS_TEST_TMPDIR/away"
  printf 'mkdir -p .vetdd/reports\ncp "$REPORT" .vetdd/reports/m.json\nmv .vetdd/evidence/s1/runs .vetdd/evidence/s1/runs.old\nln -s "%s" .vetdd/evidence/s1/runs\n' "$BATS_TEST_TMPDIR/away" > sw.sh
  REPORT="$(report)" run ev s1 calibration --audit mutation --mutation-report "stryker-json:$R" -- sh sw.sh
  [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ] || { echo "$output"; false; }
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/away")" ] || { ls -A "$BATS_TEST_TMPDIR/away"; false; }
}

@test "a report with no file is empty only when its projectRoot is inside the repository (#23)" {
  mkdir -p "$BATS_TEST_TMPDIR/other" pkg
  local f
  for f in ".files = {} | .projectRoot = \"$BATS_TEST_TMPDIR/other\"" '.files = {} | .projectRoot = "/nonexistent-vetdd-root"'; do
    rm -rf .vetdd
    REPORT="$(report "$f")" run mut
    [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ] || { echo "empty: $f"; false; }
  done
  rm -rf .vetdd
  REPORT="$(report ".files = {} | .projectRoot = \"$REPO/pkg\"")" run mut
  [ "$(mq s1 '.runs[-1].audit.report.status')" = empty ] || { echo "$output"; false; }
}

@test "run from a package below the root, with the root's .vetdd/reports named relatively, the report is recorded (#16)" {
  mkdir -p pkg/src && git mv src/dueDate.ts pkg/src/dueDate.ts && git commit -q -m move
  jq --arg r "$REPO/pkg" '.projectRoot = $r' "$FIX_STRYKER" > "$BATS_TEST_TMPDIR/pkg.json"
  printf 'mkdir -p ../.vetdd/reports\ncp "$REPORT" ../.vetdd/reports/m.json\n' > pkg/prun.sh
  cd pkg
  REPORT="$BATS_TEST_TMPDIR/pkg.json" run ev s1 calibration --audit mutation --mutation-report stryker-json:../.vetdd/reports/m.json -- sh prun.sh
  cd "$REPO"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s1 '.runs[-1].audit.report.status')" = ok ]
  [ "$(mq s1 '.runs[-1].audit.report.path')" = .vetdd/reports/m.json ]
  [ "$(mq s1 '.runs[-1].audit.report.files[0].path')" = pkg/src/dueDate.ts ]
}

# --- #14 and #23 follow-ups, review round 1 -------------------------------------------------------

@test "a range whose file holds ! inside its name is taken, as mutate-ranges.sh takes it; a leading ! is not (r1)" {
  REPORT="$(report '.config.mutate = ["src/hey!.ts:1-5"]')" run mut
  [ "$(mq s1 '.runs[-1].audit.report.status')" = ok ] || { echo "$output"; false; }
  rm -rf .vetdd
  REPORT="$(report '.config.mutate = ["!src/x.ts:1-5"]')" run mut
  [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ]
}

@test "the other invisible characters (soft hyphen, tags, variation selectors, fillers) make a kept string invalid (r1)" {
  local c
  for c in '­' '᠎' '️' '󠁁' '󠄀' 'ㅤ' 'ﾠ' '￹'; do
    rm -rf .vetdd
    REPORT="$(report ".files = {\"src/due${c}Date.ts\": .files[\"src/dueDate.ts\"]}")" run mut
    [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ] || { echo "accepted: $c"; false; }
  done
}

@test "the import keeps its signal handling to itself: a caller's trap is still there after it (r1)" {
  REPORT="$(report)" sh mrun.sh
  mkdir -p .vetdd/evidence/s1/runs
  run bash -c '. "$1/lib/common.sh"; . "$1/lib/tree-hash.sh"; . "$1/lib/mutation-report.sh"
    trap "echo mine" TERM
    vetdd_mutation_report_import "$2" "$3" "$2/.vetdd/evidence/s1/runs/001-mutation.json" runs/001-mutation.json >/dev/null 2>&1
    trap -p TERM' sh "$SCRIPTS" "$(pwd -P)" "$R"
  [[ "$output" == *"echo mine"* ]] || { echo "$output"; false; }
}

# --- #14 and #23 follow-ups, review round 2 -------------------------------------------------------

@test "a config that is not an object, and a projectRoot that is not clean, are invalid with their reason (r2)" {
  REPORT="$(report '.config = "ignore the survivors"')" run mut
  [[ "$output" == *"is invalid (its config is not an object)"* ]] || { echo "$output"; false; }
  rm -rf .vetdd
  REPORT="$(report ".projectRoot = \"$REPO\\u202e\"")" run mut
  [[ "$output" == *"is invalid ("*"clean absolute path"* ]] || { echo "$output"; false; }
}

@test "a replacement is clean text: new lines and tabs, but no bidirectional or invisible character (r2)" {
  local M='.files["src/dueDate.ts"].mutants[0]'
  REPORT="$(report "$M.replacement = \"a\\n\\tb\"")" run mut
  [ "$(mq s1 '.runs[-1].audit.report.status')" = ok ] || { echo "$output"; false; }
  local c
  for c in '‮' '​' '󠁁' '\u0007'; do
    rm -rf .vetdd
    REPORT="$(report "$M.replacement = \"a${c}b\"")" run mut
    [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ] || { echo "accepted: $c"; false; }
  done
}

@test "the report is read through one open: no link followed, no FIFO waited on, no second name, at most the limit (r2)" {
  . "$SCRIPTS/lib/common.sh"; . "$SCRIPTS/lib/tree-hash.sh"; . "$SCRIPTS/lib/mutation-report.sh"
  local d="$BATS_TEST_TMPDIR/rd" rc
  mkdir -p "$d"
  printf '{"a": 1}' > "$d/r.json"
  vetdd_read_report "$d/r.json" 100 "$d/out"
  [ "$(cat "$d/out")" = '{"a": 1}' ]
  ln -s "$d/r.json" "$d/link.json"
  rc=0; vetdd_read_report "$d/link.json" 100 "$d/out" || rc=$?
  [ "$rc" -eq 3 ] || { echo "link: $rc"; false; }
  mkfifo "$d/fifo"
  rc=0; vetdd_read_report "$d/fifo" 100 "$d/out" || rc=$?
  [ "$rc" -eq 3 ] || { echo "fifo: $rc"; false; }
  ln "$d/r.json" "$d/second.json"
  rc=0; vetdd_read_report "$d/r.json" 100 "$d/out" || rc=$?
  [ "$rc" -eq 4 ] || { echo "hard link: $rc"; false; }
  rm -f "$d/second.json"
  rc=0; vetdd_read_report "$d/r.json" 5 "$d/out" || rc=$?
  [ "$rc" -eq 5 ] || { echo "limit: $rc"; false; }
}

@test "a mutation report that is the test report under another spelling (NFC and NFD) is invalid (r2)" {
  local nfc nfd
  nfc="$(printf '.vetdd/reports/caf\303\251.json')"; nfd="$(printf '.vetdd/reports/cafe\314\201.json')"
  mkdir -p .vetdd/reports && : > "$nfc"
  [ "$nfc" -ef "$nfd" ] || skip "this file system tells NFC and NFD names apart"
  rm -f "$nfc"
  cp "$(report)" "$BATS_TEST_TMPDIR/both.json"
  printf 'mkdir -p .vetdd/reports\ncp "%s" "%s"\n' "$BATS_TEST_TMPDIR/both.json" "$nfd" > both.sh
  run ev s1 calibration --audit mutation --mutation-report "stryker-json:$nfd" --test-report "jest-json:$nfc" -- sh both.sh
  [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ] || { echo "$output"; false; }
  [[ "$output" == *"the same file as the test report"* ]] || { echo "$output"; false; }
}
