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
# The saved report ran the vitest runner; these tests use the command runner by default (#20, #21).
report() {
  jq --arg r "$REPO" ".projectRoot = \$r | .config.testRunner = \"command\" | .config.commandRunner.command = \"npx --no-install vitest run 'test.sh'\" | ${1:-.}" "$FIX_STRYKER" > "$BATS_TEST_TMPDIR/rep.json"
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
  [[ "$output" == *"10c: no mutation audit for the final oracle after its last green run"* ]]
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
  tamper s1 '.audits[0].after_seq = 0'
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

@test "ts-kata pins Stryker, runs it through the command runner with the slice's tests, and keeps reports out of the tree (#20)" {
  local kata="$VETDD_ROOT/fixtures/ts-kata" cfg
  [ "$(jq -r '.devDependencies["@stryker-mutator/core"]' "$kata/package.json")" = 10.0.0 ]
  # The vitest runner reported killable mutants as Survived with vitest 5 (#20): not a dependency.
  [ "$(jq -r '.devDependencies["@stryker-mutator/vitest-runner"] // "none"' "$kata/package.json")" = none ]
  [ ! -e "$kata/stryker.config.json" ]
  command -v node >/dev/null || skip "node not installed"
  cfg="$(cd "$kata" && VETDD_MUTATION_TESTS=$'src/dueDate.test.ts\nsrc/invoice.test.ts' node --input-type=module -e 'const c = (await import("./stryker.config.mjs")).default; console.log(JSON.stringify(c))')"
  [ "$(printf '%s' "$cfg" | jq -r '.testRunner')" = command ]
  [ "$(printf '%s' "$cfg" | jq -r '.coverageAnalysis')" = off ]
  [ "$(printf '%s' "$cfg" | jq -r '.commandRunner.command')" = "npx --no-install vitest run 'src/dueDate.test.ts' 'src/invoice.test.ts'" ]
  [ "$(printf '%s' "$cfg" | jq -r '.reporters | index("html")')" = null ]
  printf '%s' "$cfg" | jq -r '.jsonReporter.fileName' | grep -q '^\.vetdd/reports/'
  grep -qx '.stryker-tmp/' "$kata/.gitignore"
}

@test "integration (VETDD_REAL_STRYKER=1): the fixed lastDayOfMonth, its mutants killed by the slice's test, judged OK by 10c (#20)" {
  [ "${VETDD_REAL_STRYKER:-}" = 1 ] || skip "set VETDD_REAL_STRYKER=1 to run the real Stryker"
  local kata="$VETDD_ROOT/fixtures/ts-kata"
  [ -x "$kata/node_modules/.bin/stryker" ] || skip "fixtures/ts-kata/node_modules has no Stryker (npm ci there)"
  local K="$BATS_TEST_TMPDIR/kata" first last
  mkdir -p "$K" && cp -R "$kata/package.json" "$kata/tsconfig.json" "$kata/stryker.config.mjs" "$kata/.gitignore" "$kata/src" "$K/"
  ln -s "$kata/node_modules" "$K/node_modules"
  cd "$K" && git init -q && git add -A && git commit -q -m init
  # KATA.md (a): the slice's test, red on the defect, then the calendar fix.
  printf 'import { expect, it } from "vitest";\nimport { closingDate } from "./dueDate.js";\nit("February month-end", () => { expect(closingDate("2026-02-15", "end")).toBe("2026-02-28"); });\n' > src/feb.test.ts
  git add src/feb.test.ts
  ev k1 before --oracle-version v1 --oracle-file src/feb.test.ts -- ./node_modules/.bin/vitest run src/feb.test.ts >/dev/null 2>&1 || true
  perl -0pi -e 's/  const probe = .*?\n  if \(probe\.month === month\) return 31;\n  return fromUtc\(Date\.UTC\(year, month - 1, 30\)\)\.day;/  return fromUtc(Date.UTC(year, month, 0)).day;/s' src/dueDate.ts
  ev k1 after -- ./node_modules/.bin/vitest run src/feb.test.ts >/dev/null 2>&1
  # The whole function, closing brace included: an emptied body is a mutant of the whole block.
  first="$(grep -n '^function lastDayOfMonth' src/dueDate.ts | cut -d: -f1)"
  last="$(awk -v f="$first" 'NR > f && /^}/ { print NR; exit }' src/dueDate.ts)"
  VETDD_MUTATION_TESTS=src/feb.test.ts run ev k1 calibration --audit mutation --mutation-report stryker-json:.vetdd/reports/stryker.json \
    -- ./node_modules/.bin/stryker run stryker.config.mjs --mutate "src/dueDate.ts:$first-$last"
  [ "$(jq -r '.runs[-1].audit.report.status' .vetdd/evidence/k1/meta.json)" = ok ] || { echo "$output"; false; }
  [ "$(jq -r '.runs[-1].audit.report.counts.killed' .vetdd/evidence/k1/meta.json)" -ge 1 ]
  [ "$(jq -r '.runs[-1].audit.report.counts.survived' .vetdd/evidence/k1/meta.json)" = 0 ]
  # The emptied body is caught: the vitest runner reported it Survived (#20).
  jq -e '.files[].mutants[] | select(.mutatorName == "BlockStatement") | .status == "Killed"' .vetdd/evidence/k1/runs/003-mutation.json >/dev/null
  # Stryker left nothing in the tree: only the slice's own change is there.
  [ -z "$(git status --porcelain --untracked-files=all | grep -v -e '^?? .vetdd/' -e ' src/dueDate.ts$' -e ' src/feb.test.ts$')" ]
  run check k1
  [[ "$output" != *"10c"* ]] || { echo "$output"; false; }
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
  jq --arg r "$REPO" --arg k 'src/a\b.ts' '.projectRoot = $r | .config.testRunner = "command" | .config.commandRunner.command = "npx --no-install vitest run x" | .files = {($k): (.files["src/dueDate.ts"] | .source = "x\n" | .mutants |= map(.status = "Killed"))}' "$FIX_STRYKER" > "$BATS_TEST_TMPDIR/bs.json"
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

# --- review round 2 ------------------------------------------------------------------------------

@test "a note carries after_seq, the last run number when it was written (K1)" {
  an s0 --kind mutation --not-applicable --reason-file "$(note_file)"
  [ "$(mq s0 '.audits[0].after_seq')" = 0 ]
  record_good_slice s1
  an s1 --kind mutation --not-applicable --reason-file "$(note_file)"
  [ "$(mq s1 '.audits[0].after_seq')" = 2 ]
  run validate_schema "$REPO/.vetdd/evidence/s1/meta.json"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a note of an older oracle stops counting even when the new version runs in the same second (K1)" {
  record_good_slice s1
  an s1 --kind mutation --not-applicable --reason-file "$(note_file)"
  an s1 --kind undefined-imports --not-applicable --reason-file "$(note_file)"
  # Same second: the old timestamps alone would still count both notes.
  printf '\n# a stronger test\n' >> test.sh
  ev s1 calibration --oracle-version v2 --oracle-file test.sh -- sh -c 'exit 1' >/dev/null 2>&1
  ev s1 after -- sh test.sh >/dev/null 2>&1
  tamper s1 '.audits |= map(.recorded_at = "2099-01-01T00:00:00Z")'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"10b:"* ]]
  [[ "$output" == *"10c: no mutation audit"* ]]
  # And new notes for v2 are taken at once, with no wait for the clock, and they count.
  an s1 --kind mutation --not-applicable --reason-file "$(note_file)"
  an s1 --kind undefined-imports --not-applicable --reason-file "$(note_file)"
  run check s1
  [ "$output" = "s1: OK" ] || { echo "$output"; false; }
}

@test "a note without after_seq (written before it existed) is still judged by its time" {
  record_good_slice s1
  an s1 --kind mutation --not-applicable --reason-file "$(note_file)"
  tamper s1 '.audits[0] |= del(.after_seq)'
  run check s1
  [ "$output" = "s1: OK" ]
  tamper s1 '.audits[0].recorded_at = "2000-01-01T00:00:00Z"'
  run check s1
  [[ "$output" == *"10c: no mutation audit"* ]]
}

@test "the schema takes after_seq as a whole number only" {
  record_good_slice s1
  an s1 --kind mutation --not-applicable --reason-file "$(note_file)"
  local f
  for f in '.audits[0].after_seq = -1' '.audits[0].after_seq = "2"' '.audits[0].after_seq = 1.5'; do
    cp "$REPO/.vetdd/evidence/s1/meta.json" "$BATS_TEST_TMPDIR/ok.json"
    jq "$f" "$BATS_TEST_TMPDIR/ok.json" > "$BATS_TEST_TMPDIR/bad.json"
    run validate_schema "$BATS_TEST_TMPDIR/bad.json"
    [ "$status" -ne 0 ] || { echo "accepted: $f"; false; }
  done
}

@test "test mode names one report path in the config and the same in --mutation-report; no --jsonReporter option (K2)" {
  local doc="$SCRIPTS/../modes/test.md"
  ! grep -q -- '--jsonReporter' "$doc"
  grep -q 'the same path' "$doc"
  grep -q 'a note does not lift it' "$doc"
  grep -q '(10c)' "$SCRIPTS/check-evidence.sh"
  jq -r '.properties.audits.description' "$SCHEMA" | grep -q '10c'
}

# --- review round 3 ------------------------------------------------------------------------------

@test "with GNU sha256sum (which escapes a name holding a backslash) the hash is still plain (L3)" {
  # A stand-in for GNU sha256sum: given a file name with a backslash it prefixes the digest with \,
  # as coreutils does; reading standard input it prints the plain digest.
  mkdir -p "$BATS_TEST_TMPDIR/gnu"
  cat > "$BATS_TEST_TMPDIR/gnu/sha256sum" <<'SH'
#!/bin/sh
if [ $# -eq 0 ]; then shasum -a 256 | sed 's/ .*/  -/'; exit; fi
d="$(shasum -a 256 < "$1" | cut -d' ' -f1)"
case "$1" in *\\*) printf '\\%s  %s\n' "$d" "$1" ;; *) printf '%s  %s\n' "$d" "$1" ;; esac
SH
  chmod +x "$BATS_TEST_TMPDIR/gnu/sha256sum"
  printf 'x\n' > 'src/a\b.ts'
  git add -A && git commit -q -m bs
  record_good_slice s1
  jq --arg r "$REPO" --arg k 'src/a\b.ts' '.projectRoot = $r | .config.testRunner = "command" | .config.commandRunner.command = "npx --no-install vitest run x" | .files = {($k): (.files["src/dueDate.ts"] | .source = "x\n" | .mutants |= map(.status = "Killed"))}' "$FIX_STRYKER" > "$BATS_TEST_TMPDIR/bs.json"
  PATH="$BATS_TEST_TMPDIR/gnu:$PATH" mutation s1 "$BATS_TEST_TMPDIR/bs.json"
  PATH="$BATS_TEST_TMPDIR/gnu:$PATH" run check s1
  [ "$output" = "s1: OK" ] || { echo "$output"; false; }
}

@test "Q4 names the mutation report copy and its full source; the judge gets the judged run's copy only (L2)" {
  grep -n 'Q4 what leaves the machine' "$SCRIPTS/../SKILL.md" | grep -q 'mutation report'
  grep -q 'the copy of the mutation run that check-evidence judged' "$SCRIPTS/../references/final-judge-rubric.md"
}

# --- PR review (#17) -----------------------------------------------------------------------------

@test "a mutation run counts only after the final green run: a later integrated run needs a new audit (Codex P1)" {
  record_good_slice s1
  mutation s1 "$(killed)"
  run check s1
  [ "$output" = "s1: OK" ]
  # The tree changes outside the mutated file (a runner setting, a helper), then the final green.
  printf 'setting\n' > sub/config.txt
  git add sub/config.txt && git commit -q -m config
  ev s1 integrated -- sh test.sh >/dev/null 2>&1
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"10c: no mutation audit for the final oracle after its last green run"* ]]
  mutation s1 "$(killed)"
  run check s1
  [ "$output" = "s1: OK" ] || { echo "$output"; false; }
}

@test "test mode limits the mutation run to the slice's own test files (Devin)" {
  # Since #20 the command runner gets the slice's test files through VETDD_MUTATION_TESTS.
  grep -q "VETDD_MUTATION_TESTS='<the slice's test files>'" "$SCRIPTS/../modes/test.md"
}

# --- #20 ------------------------------------------------------------------------------------------

@test "test mode runs Stryker through the command runner with the slice's tests, and says why (#20)" {
  local doc="$SCRIPTS/../modes/test.md" p
  p="$(grep 'Then run the mutation audit' "$doc")"
  [[ "$p" == *'"testRunner": "command"'* ]]
  [[ "$p" == *'VETDD_MUTATION_TESTS'* ]]
  [[ "$p" == *'reported killable mutants as'* ]]
  [[ "$p" != *'--testFiles'* ]]
  [[ "$p" == *'closing brace'* ]]
}

# --- #20 review round 1 ---------------------------------------------------------------------------

# kata_cfg <VETDD_MUTATION_TESTS value or "-unset">: the command the ts-kata config builds, or its error,
# evaluated in a scratch project that holds the ts-kata config, its node_modules, and each named test
# file (with one test, so vitest lists it), so the paths a test makes up exist.
kata_cfg() {
  local kata="$VETDD_ROOT/fixtures/ts-kata" P="$BATS_TEST_TMPDIR/cfgproj" f
  [ -x "$kata/node_modules/.bin/vitest" ] || skip "fixtures/ts-kata/node_modules is missing (npm ci there)"
  rm -rf "$P"; mkdir -p "$P" && cp "$kata/stryker.config.mjs" "$kata/package.json" "$P/" && ln -s "$kata/node_modules" "$P/node_modules"
  if [ "$1" != -unset ]; then
    while IFS= read -r f; do
      case "$f" in ''|-*) continue ;; esac
      mkdir -p "$P/$(dirname -- "$f")" && printf 'import { it } from "vitest";\nit("x", () => {});\n' > "$P/$f"
    done <<< "$1"
  fi
  for f in ${KATA_CFG_EXTRA:-}; do mkdir -p "$P/$(dirname -- "$f")" && printf 'import { it } from "vitest";\nit("x", () => {});\n' > "$P/$f"; done
  if [ "$1" = -unset ]; then
    (cd "$P" && env -u VETDD_MUTATION_TESTS node --input-type=module -e 'const c = (await import("./stryker.config.mjs")).default; console.log(c.commandRunner.command)' 2>&1)
  else
    (cd "$P" && VETDD_MUTATION_TESTS="$1" node --input-type=module -e 'const c = (await import("./stryker.config.mjs")).default; console.log(c.commandRunner.command)' 2>&1)
  fi
}

@test "each test path is single-quoted for the shell, so ( ) \$ [ ] and quotes stay part of the name (Q1)" {
  command -v node >/dev/null || skip "node not installed"
  run kata_cfg $'app/(auth)/login.test.ts\nroutes/$id.test.ts\nsrc/[id].test.ts\nsrc/it\'s.test.ts'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "npx --no-install vitest run 'app/(auth)/login.test.ts' 'routes/\$id.test.ts' 'src/[id].test.ts' 'src/it'\\''s.test.ts'" ] || { echo "$output"; false; }
  # The quoted command, run by sh, hands vitest exactly those names.
  local pre="printf '%s|'" cmd
  cmd="$pre${output#npx --no-install vitest run}"
  [ "$(sh -c "$cmd")" = 'app/(auth)/login.test.ts|routes/$id.test.ts|src/[id].test.ts|src/it'"'"'s.test.ts|' ]
}

@test "with VETDD_MUTATION_TESTS unset or empty the config refuses, instead of running the whole suite silently" {
  command -v node >/dev/null || skip "node not installed"
  run kata_cfg -unset
  [ "$status" -ne 0 ]
  [[ "$output" == *"VETDD_MUTATION_TESTS"* ]]
  run kata_cfg ''
  [ "$status" -ne 0 ]
}

@test "the copy keeps the command the runner ran, so the judge sees which tests faced the mutants" {
  local F="$FIX_STRYKER"
  jq --arg r "$REPO" '.projectRoot = $r | .config.testRunner = "command" | .config.commandRunner = {command: "npx --no-install vitest run '"'"'src/a.test.ts'"'"'"}' "$F" > "$BATS_TEST_TMPDIR/c.json"
  REPORT="$BATS_TEST_TMPDIR/c.json" ev s1 calibration --audit mutation --mutation-report stryker-json:.vetdd/reports/m.json -- sh mrun.sh >/dev/null 2>&1
  [ "$(jq -r '.config.command' .vetdd/evidence/s1/runs/001-mutation.json)" = "npx --no-install vitest run 'src/a.test.ts'" ]
  # A command with a control character makes the report invalid.
  jq '.config.commandRunner.command = "a\u001bb"' "$BATS_TEST_TMPDIR/c.json" > "$BATS_TEST_TMPDIR/d.json"
  REPORT="$BATS_TEST_TMPDIR/d.json" ev s1 calibration --audit mutation --mutation-report stryker-json:.vetdd/reports/m.json -- sh mrun.sh >/dev/null 2>&1
  [ "$(mq s1 '.runs[-1].audit.report.status')" = invalid ]
}

@test "the docs: one path per line, quoted by the config, a refusal when unset, and vitest's file filter is a substring match (Q2, Q3)" {
  local p; p="$(grep 'Then run the mutation audit' "$SCRIPTS/../modes/test.md")"
  [[ "$p" != *'+ process.env.VETDD_MUTATION_TESTS'* ]]
  [[ "$p" == *'one per line'* ]]
  [[ "$p" == *'substring'* ]]
  [[ "$p" == *'unset'* ]]
  grep -q 'VETDD_MUTATION_TESTS' "$SCRIPTS/check-evidence.sh"
}

# --- #20 review round 2 ---------------------------------------------------------------------------

@test "the copy keeps the command only when the command runner ran: a vitest-runner report's default npm test is not kept (R1)" {
  record_good_slice s1
  # The saved real report: testRunner vitest, and Stryker's default commandRunner.command "npm test".
  [ "$(jq -r '.config.testRunner + " " + .config.commandRunner.command' "$FIX_STRYKER")" = "vitest npm test" ]
  mutation s1 "$(killed '.config.testRunner = "vitest" | .config.commandRunner.command = "npm test"')"
  [ "$(jq -r '.config.command' .vetdd/evidence/s1/runs/003-mutation.json)" = null ]
  # A control character in an unused commandRunner.command does not make the report invalid.
  mutation s1 "$(killed '.config.testRunner = "vitest" | .config.commandRunner.command = "a\u0009b"')"
  [ "$(mq s1 '.runs[-1].audit.report.status')" = ok ]
  mutation s1 "$(killed '.config.testRunner = "command" | .config.commandRunner.command = "npx --no-install vitest run '"'"'src/x.test.ts'"'"'"')"
  [ "$(jq -r '.config.command' .vetdd/evidence/s1/runs/005-mutation.json)" = "npx --no-install vitest run 'src/x.test.ts'" ]
}

@test "an empty report's 10c line says to widen the range; an invalid one says to run again (R2, #21)" {
  record_good_slice s1
  mutation s1 "$(report '.files = {}')"
  run check s1
  [[ "$output" == *"10c: mutation run 3 mutated nothing: the --mutate ranges held no mutant; widen them to the function's closing brace"* ]] || { echo "$output"; false; }
  record_good_slice s2
  mutation s2 "$(report '.schemaVersion = "9"')"
  run check s2
  [[ "$output" == *"10c: the report of mutation run 3 is invalid; run the mutation audit again"* ]]
  [[ "$output" != *"closing brace"* ]]
}

@test "a test path starting with - is refused, a path keeps its spaces, and the quoting is said to be POSIX sh (R3)" {
  command -v node >/dev/null || skip "node not installed"
  run kata_cfg $'-t\nsrc/a.test.ts'
  [ "$status" -ne 0 ]
  [[ "$output" == *"starts with -"* ]]
  run kata_cfg ' src/a b.test.ts'
  [ "$output" = "npx --no-install vitest run ' src/a b.test.ts'" ] || { echo "$output"; false; }
  grep -q 'POSIX' "$VETDD_ROOT/fixtures/ts-kata/stryker.config.mjs"
  grep 'Then run the mutation audit' "$SCRIPTS/../modes/test.md" | grep -q 'POSIX'
}

@test "the copy's command is described in evidence.sh, the schema, and the rubric, which asks the judge to check it" {
  grep -q 'config.command' "$SCRIPTS/evidence.sh"
  jq -r '."$defs".mutationReport.anyOf[0].properties.sha256.description' "$SCHEMA" | grep -q 'command'
  sed -n '/^```/,/^```/p' "$SCRIPTS/../references/final-judge-rubric.md" | grep -q 'config.command'
  sed -n '/^## 3\. /,/^## 4\. /p' "$SCRIPTS/../references/final-judge-rubric.md" | grep -q 'config.command'
}

# --- #21 ------------------------------------------------------------------------------------------

@test "a mutation run that did not use the command runner is a WARN (#20, #21)" {
  record_good_slice s1
  mutation s1 "$(killed '.config.testRunner = "vitest"')"
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"s1: WARN (10c: mutation run 3 ran Stryker's vitest runner"* ]] || { echo "$output"; false; }
  record_good_slice s2
  mutation s2 "$(killed '.config.testRunner = "command" | .config.commandRunner.command = "npx --no-install vitest run '"'"'src/a.test.ts'"'"'"')"
  run check s2
  [ "$output" = "s2: OK" ] || { echo "$output"; false; }
}

@test "the ts-kata config refuses a test path that is a substring of another test file's path (#21)" {
  command -v node >/dev/null || skip "node not installed"
  local kata="$VETDD_ROOT/fixtures/ts-kata"
  run sh -c "cd '$kata' && VETDD_MUTATION_TESTS=dueDate.test.ts node --input-type=module -e 'await import(\"./stryker.config.mjs\")' 2>&1"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # src/invoice.test.ts and src/dueDate.test.ts both contain "test.ts": the filter would run both.
  run sh -c "cd '$kata' && VETDD_MUTATION_TESTS=test.ts node --input-type=module -e 'await import(\"./stryker.config.mjs\")' 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"selects 2 test files"* ]] || { echo "$output"; false; }
  run sh -c "cd '$kata' && VETDD_MUTATION_TESTS=nothing.test.ts node --input-type=module -e 'await import(\"./stryker.config.mjs\")' 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"selects 0 test files"* ]]
}

@test "the ts-kata config refuses to run on Windows, where cmd.exe keeps the single quotes (#21)" {
  grep -q 'process.platform === "win32"' "$VETDD_ROOT/fixtures/ts-kata/stryker.config.mjs"
}

@test "Q4 names the test command in the mutation report copy, and the rubric says what it is for a verify slice (#21)" {
  grep 'Q4 what leaves the machine' "$SCRIPTS/../SKILL.md" | grep -q 'test command'
  sed -n '/^## 3\. /,/^## 4\. /p' "$SCRIPTS/../references/final-judge-rubric.md" | grep -q 'verify slice'
}

# --- #21 review round 1 ---------------------------------------------------------------------------

@test "the config asks vitest which files a path selects: a match in another letter case is refused (S1)" {
  command -v node >/dev/null || skip "node not installed"
  # vitest matches case-insensitively: user.test.ts also selects src/adminUser.test.ts.
  KATA_CFG_EXTRA='src/adminUser.test.ts' run kata_cfg 'src/user.test.ts'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  KATA_CFG_EXTRA='src/adminUser.test.ts' run kata_cfg 'user.test.ts'
  [ "$status" -ne 0 ]
  [[ "$output" == *"selects 2 test files"* ]] || { echo "$output"; false; }
}

@test "the config follows the project's own vitest include, and does not need fs.globSync (S2)" {
  command -v node >/dev/null || skip "node not installed"
  ! grep -q 'globSync' "$VETDD_ROOT/fixtures/ts-kata/stryker.config.mjs"
  grep -q 'vitest list' "$VETDD_ROOT/fixtures/ts-kata/stryker.config.mjs"
}

@test "a copy written before testRunner was kept, with no command, is a WARN (runner unknown) (S3)" {
  record_good_slice s1
  mutation s1 "$(killed)"
  local c=.vetdd/evidence/s1/runs/003-mutation.json
  jq 'del(.config.testRunner) | .config.command = null' "$c" > "$c.tmp" && mv "$c.tmp" "$c"
  tamper s1 ".runs[-1].audit.report.sha256 = \"$(sha256_of "$c")\""
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"WARN (10c: mutation run 3 does not say which Stryker runner"* ]] || { echo "$output"; false; }
}

@test "the copy's testRunner is described with its command, in the code comment, the schema, evidence.sh, and the rubric (S4)" {
  grep -q 'config.testRunner' "$SCRIPTS/lib/mutation-report.sh"
  jq -r '."$defs".mutationReport.anyOf[0].properties.sha256.description' "$SCHEMA" | grep -q 'testRunner'
  grep -q 'config.testRunner' "$SCRIPTS/evidence.sh"
  sed -n '/^```/,/^```/p' "$SCRIPTS/../references/final-judge-rubric.md" | grep -q 'config.testRunner'
}

@test "test mode says Windows and empty once each (S5)" {
  local p; p="$(grep 'Then run the mutation audit' "$SCRIPTS/../modes/test.md")"
  [ "$(printf '%s' "$p" | grep -o 'cmd.exe' | wc -l | tr -d ' ')" = 1 ]
  [ "$(printf '%s' "$p" | grep -o 'recorded `empty`' | wc -l | tr -d ' ')" = 1 ]
}
