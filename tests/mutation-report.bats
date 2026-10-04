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
  for f in '"x"' '.files = {}' 'del(.files)' '.schemaVersion = "2.0"' 'del(.schemaVersion)' \
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
  local K; K="$(report '.files["src/dueDate.ts"].mutants |= map(.status = "Killed")')"
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
  [ "$(jq -c '.config | keys' "$c")" = '["mutate"]' ]
  [ "$(jq -c '[.files[].mutants[] | keys] | unique' "$c")" = '[["id","location","mutatorName","replacement","status"]]' ]
  ! grep -q 'ignore the survivors\|secret-plugin' "$c"
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
  grep -q 'vetdd_mutation_report_import' "$SCRIPTS/lib/mutation-report.sh"
  # Every jq read after the first copy goes to the private temp copy, never back to the report path.
  [ "$(grep -c '"\$root/\$rel"' "$SCRIPTS/lib/mutation-report.sh")" -le 4 ]
}

@test "an audit mark of an unknown kind on a run opts the slice in to rule 10 (fails closed)" {
  record_good_slice s1
  REPORT="$(report '.files["src/dueDate.ts"].mutants |= map(.status = "Killed")')" ev s1 calibration --audit mutation --mutation-report "stryker-json:$R" -- sh mrun.sh >/dev/null 2>&1
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
