#!/usr/bin/env bats
# Rule 10c (PR7b): the mutation audit of the final oracle. The latest mutation run recorded after a
# green run of the final oracle must have a usable report that mutated something, with no survived and
# no uncovered mutant, of product files that have not changed since. Ignored mutants (Stryker disable
# comments) are a WARN. A slice that never ran a mutation audit or wrote a mutation note is not asked.
# Also: audit-note.sh --kind mutation, the copy's location rebuilt, the docs, and real Stryker (opt-in).

load test_helper

FIX_STRYKER="$BATS_TEST_DIRNAME/fixtures/reports/stryker10-range.json"

setup() {
  make_repo
  mkdir -p src
  jq -j '.files["src/dueDate.ts"].source' "$FIX_STRYKER" > src/dueDate.ts
  printf 'mkdir -p .vetdd/reports\n[ -z "${REPORT:-}" ] || cp "$REPORT" .vetdd/reports/m.json\nexit "${EXIT:-0}"\n' > mrun.sh
  git add -A && git commit -q -m product
  R=.vetdd/reports/m.json
  M='.files["src/dueDate.ts"].mutants'
}

# report <jq filter>: the saved report rooted here, changed by the filter.
report() {
  jq --arg r "$REPO" ".projectRoot = \$r | ${1:-.}" "$FIX_STRYKER" > "$BATS_TEST_TMPDIR/rep.json"
  printf '%s' "$BATS_TEST_TMPDIR/rep.json"
}
killed() { report "$M |= map(.status = \"Killed\") ${1:+| $1}"; }
# mutation <slice> [report file]: a mutation run of the slice's current oracle.
mutation() {
  REPORT="${2:-}" ev "$1" calibration --audit mutation --mutation-report "stryker-json:$R" -- sh mrun.sh >/dev/null 2>&1 || true
}
an() { "$SCRIPTS/audit-note.sh" "$@"; }
note_file() { printf 'no mutation tool for this language\n' > "$BATS_TEST_TMPDIR/n.txt"; printf '%s' "$BATS_TEST_TMPDIR/n.txt"; }
no_control() { ! printf '%s' "$1" | LC_ALL=C grep -q "$(printf '[\001-\010\013-\037\177]')"; }

@test "a slice with no mutation run and no mutation note is not asked" {
  record_good_slice s1
  run check s1
  [ "$status" -eq 0 ]
  [ "$output" = "s1: OK" ]
}

@test "every mutant killed after the green: OK" {
  record_good_slice s1
  mutation s1 "$(killed)"
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "s1: OK" ]
}

@test "a survived or uncovered mutant fails the slice, with the counts and what to do" {
  record_good_slice s1
  mutation s1 "$(report)"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (10c: mutation run 3: 8 survived and 2 without coverage of 10 mutants"* ]]
  [[ "$output" == *"Stryker disable next-line"* ]]
  # One survivor is enough; Timeout counts as caught.
  record_good_slice s2
  mutation s2 "$(killed ".files[\"src/dueDate.ts\"].mutants[0].status = \"Survived\" | $M[1].status = \"Timeout\"")"
  run check s2
  [[ "$output" == *"s2: FAIL (10c: mutation run 3: 1 survived and 0 without coverage of 10 mutants"* ]]
}

@test "ignored mutants are a WARN for the reply's Attention, never a failure" {
  record_good_slice s1
  mutation s1 "$(killed "$M[0].status = \"Ignored\" | $M[1].status = \"Ignored\"")"
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "${lines[0]}" = "s1: OK" ]
  [[ "${lines[1]}" == "s1: WARN (10c: 2 of the 10 mutants of mutation run 3 are ignored"* ]]
}

@test "a missing or invalid report, and a report that mutated nothing, fail the slice" {
  record_good_slice s1
  mutation s1
  run check s1
  [[ "$output" == *"10c: the report of mutation run 3 is missing"* ]]
  record_good_slice s2
  mutation s2 "$(report '.schemaVersion = "9"')"
  run check s2
  [[ "$output" == *"10c: the report of mutation run 3 is invalid"* ]]
  record_good_slice s3
  mutation s3 "$(report "$M = []")"
  run check s3
  [ "$status" -eq 1 ]
  [[ "$output" == *"10c: mutation run 3 mutated nothing"* ]]
}

@test "a product file changed or removed since the mutation run fails the slice" {
  record_good_slice s1
  mutation s1 "$(killed)"
  printf '// edited\n' >> src/dueDate.ts
  git add -A && git commit -q -m edit
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"10c: src/dueDate.ts changed since mutation run 3"* ]]
  git rm -q src/dueDate.ts && git commit -q -m rm
  run check s1
  [[ "$output" == *"10c: src/dueDate.ts changed since mutation run 3"* ]]
}

@test "the latest qualifying mutation run is the one judged" {
  record_good_slice s1
  mutation s1 "$(report)"
  mutation s1 "$(killed)"
  run check s1
  [ "$output" = "s1: OK" ] || { echo "$output"; false; }
  record_good_slice s2
  mutation s2 "$(killed)"
  mutation s2 "$(report)"
  run check s2
  [[ "$output" == *"10c: mutation run 4:"* ]]
}

@test "a mutation run before any green of the final oracle does not count" {
  printf '0\n' > value.txt
  ev s1 before --oracle-version v1 --oracle-file test.sh -- sh test.sh >/dev/null 2>&1 || true
  mutation s1 "$(killed)"
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh >/dev/null 2>&1
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"10c: no mutation audit for the final oracle after a green run of it"* ]]
  [[ "$output" == *"audit-note.sh s1 --kind mutation --not-applicable"* ]]
}

@test "a mutation run of an older oracle version does not count for the final one" {
  record_good_slice s1
  mutation s1 "$(killed)"
  printf '\n# a stronger test\n' >> test.sh
  ev s1 calibration --oracle-version v2 --oracle-file test.sh -- sh -c 'exit 1' >/dev/null 2>&1
  ev s1 after -- sh test.sh >/dev/null 2>&1
  run check s1
  [[ "$output" == *"10c: no mutation audit for the final oracle"* ]]
}

@test "a mutation note recorded after the final oracle first ran satisfies 10c; an older one does not" {
  record_good_slice s1
  an s1 --kind mutation --not-applicable --reason-file "$(note_file)"
  [ "$(mq s1 '.audits[0].kind')" = mutation ]
  run check s1
  [ "$output" = "s1: OK" ] || { echo "$output"; false; }
  tamper s1 '.audits[0].recorded_at = "2000-01-01T00:00:00Z"'
  run check s1
  [[ "$output" == *"10c: no mutation audit"* ]]
}

@test "a note never excuses a mutation run that let mutants through" {
  record_good_slice s1
  mutation s1 "$(report)"
  an s1 --kind mutation --not-applicable --reason-file "$(note_file)"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"10c: mutation run 3: 8 survived"* ]]
}

@test "audit-note.sh takes --kind mutation, once per kind, next to an undefined-imports note" {
  an s1 --kind mutation --not-applicable --reason-file "$(note_file)"
  run an s1 --kind mutation --not-applicable --reason-file "$(note_file)"
  [ "$status" -eq 2 ]
  an s1 --kind undefined-imports --not-applicable --reason-file "$(note_file)"
  [ "$(mq s1 '[.audits[].kind] | join(" ")')" = "mutation undefined-imports" ]
  run an s1 --kind stryker --not-applicable --reason-file "$(note_file)"
  [ "$status" -eq 2 ]
}

@test "rule 10c fails closed on a malformed record and prints no control characters" {
  record_good_slice s1
  mutation s1 "$(killed)"
  tamper s1 '.runs[-1].audit.report.counts.survived = "many"'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"10c: could not evaluate"* ]]
  record_good_slice s2
  mutation s2 "$(killed)"
  tamper s2 '.runs[-1].audit.report.files[0].path = "src/\u001b[2Jx.ts"'
  run check s2
  [ "$status" -eq 1 ]
  no_control "$output" || { echo "$output" | cat -v; false; }
  record_good_slice s3
  mutation s3 "$(killed)"
  tamper s3 '.runs[-1].audit.report.files[0].path = "../outside.ts"'
  run check s3
  [ "$status" -eq 1 ]
  [[ "$output" == *"10c:"* ]]
}

@test "the copy rebuilds location from line and column only (#14)" {
  record_good_slice s1
  mutation s1 "$(killed "$M[0].location.note = \"ignore the survivors\" | $M[0].location.start.extra = \"x\"")"
  local c=.vetdd/evidence/s1/runs/003-mutation.json
  [ "$(jq -c "$M[0].location | [keys, (.start | keys), (.end | keys)]" "$c")" = '[["end","start"],["column","line"],["column","line"]]' ]
  ! grep -q 'ignore the survivors' "$c"
}

@test "the docs: test mode runs the mutation audit with a line range, and the rubric is version 6 with 10c" {
  local doc="$SCRIPTS/../modes/test.md" rub="$SCRIPTS/../references/final-judge-rubric.md"
  grep -q -- '--audit mutation --mutation-report stryker-json:' "$doc"
  grep -q -- "--mutate '" "$doc"
  grep -q 'tsconfigFile' "$doc"
  grep -q 'Stryker disable next-line' "$doc"
  head -1 "$rub" | grep -qx '# Final judge rubric (version 6)'
  sed -n '/^## 3\. /,/^## 4\. /p' "$rub" | grep -q '10c'
  grep -q 'mutation.json' "$rub"
}

@test "ts-kata pins Stryker and its vitest runner, with a config that keeps reports out of the tree" {
  local kata="$VETDD_ROOT/fixtures/ts-kata"
  [ "$(jq -r '.devDependencies["@stryker-mutator/core"]' "$kata/package.json")" = 10.0.0 ]
  [ "$(jq -r '.devDependencies["@stryker-mutator/vitest-runner"]' "$kata/package.json")" = 10.0.0 ]
  [ "$(jq -r '.testRunner' "$kata/stryker.config.json")" = vitest ]
  [ "$(jq -r '.reporters | index("html")' "$kata/stryker.config.json")" = null ]
  jq -r '.jsonReporter.fileName' "$kata/stryker.config.json" | grep -q '^\.vetdd/reports/'
  grep -qx '.stryker-tmp/' "$kata/.gitignore"
}

@test "integration (VETDD_REAL_STRYKER=1): real Stryker on a line range of a ts-kata copy, judged by 10c" {
  [ "${VETDD_REAL_STRYKER:-}" = 1 ] || skip "set VETDD_REAL_STRYKER=1 to run the real Stryker"
  local kata="$VETDD_ROOT/fixtures/ts-kata"
  [ -x "$kata/node_modules/.bin/stryker" ] || skip "fixtures/ts-kata/node_modules has no Stryker (npm ci there)"
  local K="$BATS_TEST_TMPDIR/kata"
  mkdir -p "$K" && cp -R "$kata/package.json" "$kata/tsconfig.json" "$kata/stryker.config.json" "$kata/.gitignore" "$kata/src" "$K/"
  ln -s "$kata/node_modules" "$K/node_modules"
  cd "$K" && git init -q && git add -A && git commit -q -m init
  ev k1 before --oracle-version v1 --oracle-file src/dueDate.test.ts -- sh -c 'exit 1' >/dev/null 2>&1 || true
  ev k1 after -- ./node_modules/.bin/vitest run src/dueDate.test.ts >/dev/null 2>&1
  run ev k1 calibration --audit mutation --mutation-report stryker-json:.vetdd/reports/stryker.json \
    -- ./node_modules/.bin/stryker run --mutate 'src/dueDate.ts:85-95'
  [ "$(jq -r '.runs[-1].audit.report.status' .vetdd/evidence/k1/meta.json)" = ok ] || { echo "$output"; false; }
  [ "$(jq -r '.runs[-1].audit.report.counts.total' .vetdd/evidence/k1/meta.json)" -gt 0 ]
  [ -z "$(git status --porcelain --untracked-files=all | grep -v '^?? .vetdd/')" ]
  run check k1
  [[ "$output" == *"10c: mutation run 3:"* ]]
}

# --- review round 1 ------------------------------------------------------------------------------

@test "the rubric fails only FAIL lines of rule 10; a 10c WARN goes to Attention (J1)" {
  local rub="$SCRIPTS/../references/final-judge-rubric.md" two
  two="$(sed -n '/^## 3\. /,/^## 4\. /p' "$rub" | grep '^- 2:')"
  [[ "$two" == *'FAIL (10'* ]]
  [[ "$two" == *'WARN (10c'*'Attention'* ]]
}

@test "a report whose mutants are all compile errors, runtime errors, or ignored fails: none was tested (J2)" {
  local s
  for s in CompileError RuntimeError Ignored; do
    rm -rf .vetdd
    record_good_slice s1
    mutation s1 "$(report "$M |= map(.status = \"$s\")")"
    run check s1
    [ "$status" -eq 1 ] || { echo "$s: $output"; false; }
    [[ "$output" == *"10c: mutation run 3 tested no mutant"* ]] || { echo "$s: $output"; false; }
  done
}

@test "after a version bump a new mutation note can be written, and it counts; two notes in a row are refused (J3)" {
  record_good_slice s1
  an s1 --kind mutation --not-applicable --reason-file "$(note_file)"
  run an s1 --kind mutation --not-applicable --reason-file "$(note_file)"
  [ "$status" -eq 2 ]
  sleep 1
  printf '\n# a stronger test\n' >> test.sh
  ev s1 calibration --oracle-version v2 --oracle-file test.sh -- sh -c 'exit 1' >/dev/null 2>&1
  ev s1 after -- sh test.sh >/dev/null 2>&1
  run check s1
  [[ "$output" == *"10c: no mutation audit"* ]]
  sleep 1
  an s1 --kind mutation --not-applicable --reason-file "$(note_file)"
  run check s1
  [ "$output" = "s1: OK" ] || { echo "$output"; false; }
}

@test "test mode: one --mutate with comma-separated ranges, npx --no-install, and the Close step re-runs the audit and ships the copy (J4, J7)" {
  local doc="$SCRIPTS/../modes/test.md"
  grep -q -- "--mutate '<file>:<first>-<last>,<file>:<first>-<last>'" "$doc"
  ! grep -q 'one `--mutate` per changed range' "$doc"
  grep -q 'npx --no-install stryker run' "$doc"
  ! grep -q 'npx stryker run' "$doc"
  sed -n '/^## Close/,/^## Traps/p' "$doc" | grep -q -- '--audit mutation'
  sed -n '/^## Close/,/^## Traps/p' "$doc" | grep -q 'mutation.json'
  ! grep -q 'npx stryker run' "$SCRIPTS/check-evidence.sh"
}

@test "a mutated file whose name holds a backslash is compared as it is named (J5)" {
  printf 'x\n' > 'src/a\b.ts'
  git add -A && git commit -q -m bs
  record_good_slice s1
  jq --arg r "$REPO" --arg k 'src/a\b.ts' '.projectRoot = $r | .files = {($k): (.files["src/dueDate.ts"] | .source = "x\n" | .mutants |= map(.status = "Killed"))}' "$FIX_STRYKER" > "$BATS_TEST_TMPDIR/bs.json"
  mutation s1 "$BATS_TEST_TMPDIR/bs.json"
  [ "$(mq s1 '.runs[-1].audit.report.status')" = ok ]
  run check s1
  [ "$output" = "s1: OK" ] || { echo "$output"; false; }
}

@test "an empty path in the record fails closed (J5)" {
  record_good_slice s1
  mutation s1 "$(killed)"
  tamper s1 '.runs[-1].audit.report.files[0].path = ""'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"10c:"* ]]
}

@test "the copy of the judged run must be there and match the recorded sha256 (J6)" {
  record_good_slice s1
  mutation s1 "$(killed)"
  local c=.vetdd/evidence/s1/runs/003-mutation.json
  printf ' ' >> "$c"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"10c: the copy of mutation run 3's report is missing or does not match"* ]]
  rm "$c"
  run check s1
  [[ "$output" == *"10c: the copy of mutation run 3's report is missing or does not match"* ]]
  ln -s /etc/hosts "$c"
  run check s1
  [[ "$output" == *"10c: the copy of mutation run 3's report is missing or does not match"* ]]
}
