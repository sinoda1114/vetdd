#!/usr/bin/env bats
# The planted record (#62 item 5, #74, #82): a calibration run that calibrate.sh planted records
# carries planted: {patch, sha256, files}, the diff from the originals plant saved to the planted
# files, kept at runs/<seq>-planted.patch. evidence.sh takes it only from a running calibrate.sh
# planted; check-evidence checks the copy (rule 12); judge-layout sends it with the red-run log;
# mutate-ranges reads it instead of guessing whether a red was an unfix or a plant.
# A negated command mid-test is written `! cmd || false`: bats does not fail a test on a bare `! cmd`.

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  make_repo
  printf '42\n' > value.txt
  git add -A && git commit -q -m fixed
}

cal() { "$SCRIPTS/calibrate.sh" "$@"; }
state_dir() { printf '%s/vetdd-calib/%s' "$(git rev-parse --absolute-git-dir)" "$1"; }
JL() { "$SCRIPTS/judge-layout.sh" "$@"; }

# A behavior-preserving slice: a planted red (value 41), then its green.
planted_slice() {
  cal plant "$1" --file value.txt --oracle-file test.sh >/dev/null 2>&1
  printf '41\n' > value.txt
  cal planted "$1" --seam unit --oracle-version v1 --oracle-file test.sh -- sh test.sh >/dev/null 2>&1
  ev "$1" after -- sh test.sh >/dev/null 2>&1
}

# --- calibrate.sh and evidence.sh -----------------------------------------------------------------

@test "planted records planted: {patch, sha256, files} on its run, the patch at runs/<seq>-planted.patch" {
  ev s1 calibration --oracle-file test.sh -- true >/dev/null 2>&1
  cal plant s1 --file value.txt --oracle-file test.sh
  printf '41\n' > value.txt
  run cal planted s1 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s1 '.runs[-1].seq')" = 2 ]
  [ "$(mq s1 '.runs[-1].planted.patch')" = runs/002-planted.patch ]
  [ "$(mq s1 '.runs[-1].planted.files | tojson')" = '["value.txt"]' ]
  local p=.vetdd/evidence/s1/runs/002-planted.patch
  [ -f "$p" ] && [ ! -L "$p" ]
  [ "$(mq s1 '.runs[-1].planted.sha256')" = "$(sha256_of "$p")" ]
  grep -qx -- '--- a/value.txt' "$p"
  grep -qx -- '+++ b/value.txt' "$p"
  grep -qx -- '-42' "$p"
  grep -qx -- '+41' "$p"
  # The patch takes the original (put back) to the planted file.
  [ "$(cat value.txt)" = 42 ]
  git apply "$p" && [ "$(cat value.txt)" = 41 ]
  git checkout -q -- value.txt
}

@test "the patch and its files name only the saved files that were changed, as repository paths from a subdirectory" {
  mkdir -p proj && cp test.sh proj/test.sh && printf '42\n' > proj/value.txt && printf 'o\n' > proj/other.txt
  git add -A && git commit -q -m proj
  cd proj
  cal plant p1 --file value.txt --file other.txt --oracle-file test.sh >/dev/null
  printf '41\n' > value.txt
  run cal planted p1 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq p1 '.runs[-1].planted.files | tojson')" = '["proj/value.txt"]' ]
  grep -qx -- '--- a/proj/value.txt' "$REPO/.vetdd/evidence/p1/runs/001-planted.patch"
  ! grep -q 'other.txt' "$REPO/.vetdd/evidence/p1/runs/001-planted.patch" || false
}

@test "an executable bit planted alone is in the patch, and a planted run that did not go red keeps its record too" {
  cal plant s1 --file value.txt --oracle-file test.sh >/dev/null
  chmod +x value.txt
  run cal planted s1 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 1 ]
  [ "$(mq s1 '.runs[-1].outcome')" = pass ]
  [ "$(mq s1 '.runs[-1].planted.files | tojson')" = '["value.txt"]' ]
  grep -qx 'new mode 100755' .vetdd/evidence/s1/runs/001-planted.patch
  [ ! -x value.txt ]
}

@test "a planted new file (not in HEAD) and a repository without commits are covered" {
  printf 'n\n' > new.txt
  cal plant s1 --file new.txt --oracle-file test.sh >/dev/null
  printf 'm\n' > new.txt
  run cal planted s1 --oracle-file test.sh -- sh -c 'exit 1'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s1 '.runs[-1].planted.files | tojson')" = '["new.txt"]' ]
  [ "$(cat new.txt)" = n ]
  NOHEAD="$BATS_TEST_TMPDIR/nohead" && mkdir -p "$NOHEAD" && cd "$NOHEAD" && git init -q
  printf '#!/bin/sh\n[ "$(cat value.txt)" = "42" ]\n' > test.sh
  printf '42\n' > value.txt && git add -A
  cal plant s9 --file value.txt --oracle-file test.sh >/dev/null
  printf '41\n' > value.txt
  run cal planted s9 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -r '.runs[-1].planted.files | tojson' .vetdd/evidence/s9/meta.json)" = '["value.txt"]' ]
}

@test "unfix, stub, and a plain calibration carry no planted field" {
  printf '43\n' > value.txt
  cal unfix s1 --file value.txt --oracle-file test.sh -- sh -c '[ "$(cat value.txt)" = 43 ]' >/dev/null 2>&1 || true
  ev s2 calibration --oracle-file test.sh -- false >/dev/null 2>&1
  [ "$(mq s1 '.runs[-1] | has("planted")')" = false ]
  [ "$(mq s2 '.runs[-1] | has("planted")')" = false ]
  printf 'export const x = 1;\n' > lib.ts && git add lib.ts && git commit -q -m lib
  cal stub s3 --file lib.ts --oracle-file test.sh -- false >/dev/null 2>&1 || true
  [ "$(mq s3 '.runs[-1] | has("planted")')" = false ]
  ! ls .vetdd/evidence/*/runs/*-planted.patch 2>/dev/null || false
}

@test "evidence.sh takes --planted only from a running calibrate.sh planted of the same slice, refused before the command runs" {
  printf 'x\n' > p.patch
  run ev s1 calibration --planted p.patch -- touch ran
  [ "$status" -eq 2 ] && [[ "$output" == *"calibrate.sh"* ]]
  run ev s1 calibration --planted -- touch ran
  [ "$status" -eq 2 ]
  # The state path, but no planted run going (no plant, no run claimed).
  local st; st="$(state_dir s1)"
  mkdir -p "$st" && cp p.patch "$st/planted.patch"
  run ev s1 calibration --planted "$st/planted.patch" -- touch ran
  [ "$status" -eq 2 ]
  echo plant > "$st/mode"
  run ev s1 calibration --planted "$st/planted.patch" -- touch ran
  [ "$status" -eq 2 ]
  rm -rf "$st"
  # A real planted run of s1 is going: another slice, another kind, or with --audit is still refused.
  cal plant s1 --file value.txt --oracle-file test.sh >/dev/null
  printf '41\n' > value.txt
  mkdir "$st/run.lock" && printf 'diff\n' > "$st/planted.patch"
  run ev s2 calibration --planted "$st/planted.patch" -- touch ran;                                [ "$status" -eq 2 ]
  run ev s1 before --planted "$st/planted.patch" -- touch ran;                                     [ "$status" -eq 2 ]
  run ev s1 after --planted "$st/planted.patch" -- touch ran;                                      [ "$status" -eq 2 ]
  run ev s1 calibration --audit undefined-imports --planted "$st/planted.patch" -- touch ran;      [ "$status" -eq 2 ]
  # A patch git cannot read, or one that names no file, is refused too.
  run ev s1 calibration --planted "$st/planted.patch" -- touch ran;                                [ "$status" -eq 2 ]
  [ ! -e ran ]
  [ ! -e .vetdd/evidence/s1/meta.json ] && [ ! -e .vetdd/evidence/s2/meta.json ]
  rmdir "$st/run.lock"
  cal restore s1 >/dev/null
  [ "$(cat value.txt)" = 42 ]
}

@test "calibrate.sh does not take --planted from the caller" {
  run cal unfix s1 --file value.txt --oracle-file test.sh --planted x -- true
  [ "$status" -eq 2 ]
  cal plant s1 --file value.txt --oracle-file test.sh >/dev/null
  printf '41\n' > value.txt
  run cal planted s1 --oracle-file test.sh --planted x -- sh test.sh
  [ "$status" -eq 2 ]
  cal restore s1 >/dev/null
}

@test "the schema takes the planted field, closed, and a run without it stays valid" {
  planted_slice s1
  run validate_schema "$REPO/.vetdd/evidence/s1/meta.json"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local m="$REPO/.vetdd/evidence/s1/meta.json" bad="$BATS_TEST_TMPDIR/bad.json" f
  for f in '.runs[0].planted.extra = 1' '.runs[0].planted.patch = "runs/1-planted.patch"' \
           '.runs[0].planted.patch = "runs/001-calibration.log"' '.runs[0].planted.sha256 = "abc"' \
           '.runs[0].planted.files = []' '.runs[0].planted.files = [""]' 'del(.runs[0].planted.sha256)' \
           '.runs[0].planted = "x"'; do
    jq "$f" "$m" > "$bad"
    run validate_schema "$bad"
    [ "$status" -ne 0 ] || { echo "accepted: $f"; false; }
  done
  jq 'del(.runs[0].planted)' "$m" > "$bad"
  run validate_schema "$bad"
  [ "$status" -eq 0 ]
}

# --- check-evidence.sh rule 12 -------------------------------------------------------------------

@test "rule 12: a planted slice with its patch in place is OK" {
  planted_slice s1
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "s1: OK" ]
}

@test "rule 12: the patch must be there, a regular file, and match the recorded sha256" {
  planted_slice s1
  local p=.vetdd/evidence/s1/runs/001-planted.patch
  cp "$p" "$BATS_TEST_TMPDIR/keep"
  printf ' ' >> "$p"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (12: the planted patch of calibration run 1 is missing or does not match"* ]] || { echo "$output"; false; }
  rm "$p"
  run check s1
  [ "$status" -eq 1 ] && [[ "$output" == *"FAIL (12:"* ]]
  ln -s "$BATS_TEST_TMPDIR/keep" "$p"
  run check s1
  [ "$status" -eq 1 ] && [[ "$output" == *"FAIL (12:"* ]]
  rm "$p" && cp "$BATS_TEST_TMPDIR/keep" "$p"
  run check s1
  [ "$status" -eq 0 ]
}

@test "rule 12: a record whose planted field is malformed, or names another file, fails" {
  planted_slice s1
  local f
  for f in '.runs[0].planted.patch = "runs/009-planted.patch"' '.runs[0].planted.patch = "../../x"' \
           '.runs[0].planted.sha256 = "0000000000000000000000000000000000000000000000000000000000000000"' \
           '.runs[0].planted = "x"' '.runs[0].planted.files = []' '.runs[0].planted.sha256 = 5'; do
    cp .vetdd/evidence/s1/meta.json "$BATS_TEST_TMPDIR/meta"
    tamper s1 "$f"
    run check s1
    [ "$status" -eq 1 ] && [[ "$output" == *"FAIL (12:"* ]] || { echo "$f: $output"; false; }
    cp "$BATS_TEST_TMPDIR/meta" .vetdd/evidence/s1/meta.json
  done
  # Old evidence, from before the field: nothing is asked.
  tamper s1 'del(.runs[0].planted)'
  rm .vetdd/evidence/s1/runs/001-planted.patch
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "rule 12 is documented in check-evidence.sh's header, and the schema describes the field" {
  grep -q '^# Planted: *(12)' "$SCRIPTS/check-evidence.sh"
  jq -r '."$defs".run.properties.planted.description' "$SCHEMA" | grep -q 'calibrate.sh planted'
}

# --- judge-layout.sh ------------------------------------------------------------------------------

@test "judge-layout sends a planted red's patch with its log" {
  planted_slice s1
  printf '## Oracle\nvalue.txt holds 42\n' > "$BATS_TEST_TMPDIR/reply.md"
  local OUT="$BATS_TEST_TMPDIR/judge/candidates"
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$OUT/c1/evidence/s1/runs/001-calibration.log" ]
  cmp -s "$OUT/c1/evidence/s1/runs/001-planted.patch" .vetdd/evidence/s1/runs/001-planted.patch
  # Green logs stay.
  [ ! -e "$OUT/c1/evidence/s1/runs/002-after.log" ]
}

@test "judge-layout leaves a planted run that did not go red on the machine, and stops when a red's patch is missing" {
  cal plant s1 --file value.txt --oracle-file test.sh >/dev/null
  chmod +x value.txt
  cal planted s1 --oracle-file test.sh -- sh test.sh >/dev/null 2>&1 || true
  planted_slice s1
  printf '## Oracle\nvalue.txt holds 42\n' > "$BATS_TEST_TMPDIR/reply.md"
  local OUT="$BATS_TEST_TMPDIR/judge/candidates"
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$OUT/c1/evidence/s1/runs/001-planted.patch" ]
  [ -f "$OUT/c1/evidence/s1/runs/002-planted.patch" ]
  rm .vetdd/evidence/s1/runs/002-planted.patch
  run JL --out "$BATS_TEST_TMPDIR/judge2" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"002-planted.patch"* ]]
}

@test "judge-layout's header lists the planted patch with the red-run logs" {
  grep -q 'planted.patch' "$SCRIPTS/judge-layout.sh"
  sed -n '1,70p' "$SCRIPTS/judge-layout.sh" | grep -q '<seq>-planted.patch'
}

# --- SKILL.md -------------------------------------------------------------------------------------

@test "SKILL.md's Q4 names the planted patch among what goes to the judge" {
  grep '^| Q4 ' "$SCRIPTS/../SKILL.md" | grep -q 'planted patch'
}

# --- mutate-ranges.sh -----------------------------------------------------------------------------

mr() { "$SCRIPTS/mutate-ranges.sh" "$@"; }
green() { ev "$1" after -- true >/dev/null 2>&1; }
calq() { cal "$@" >/dev/null 2>&1; }

@test "mutate-ranges: a refactor whose planted defect restores HEAD content is not an unfix (claude-kit#11, Devin)" {
  mkdir -p src
  printf '%s\n' 'function f(x) {' '  return x > 1;' '}' 'function g(y) {' '  return y * 2 + 0;' '}' > src/a.js
  git add -A && git commit -q -m product
  ev s0 before --seam unit --oracle-version v1 --oracle-file test.sh -- false >/dev/null 2>&1
  printf '%s\n' 'function f(x) {' '  return x >= 1;' '}' 'function g(y) {' '  return y * 2 + 0;' '}' > src/a.js
  green s0
  calq plant s1 --file src/a.js --oracle-file test.sh
  printf '%s\n' 'function f(x) {' '  return x > 1;' '}' 'function g(y) {' '  return y * 2 + 0;' '}' > src/a.js
  calq planted s1 --oracle-file test.sh -- false
  green s1
  printf '%s\n' 'function f(x) {' '  return x >= 1;' '}' 'function g(y) {' '  return y + y + 0;' '}' > src/a.js
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:5-5" ]
  [[ "$stderr" == *"planted"* ]] || { echo "$stderr"; false; }
  # Old evidence, without the field, is still read by comparing with HEAD (the guess).
  tamper s1 'del(.runs[].planted)'
  run --separate-stderr mr s1
  [ "$output" = "src/a.js:2-2" ] || { echo "$output $stderr"; false; }
}

@test "mutate-ranges: a later version's planted red starts at the tree before the plant, so the line the after puts back is not the slice's (#74 item 2)" {
  mkdir -p src
  printf '%s\n' a1 a2 a3 a4 a5 > src/a.js
  git add -A && git commit -q -m product
  ev s1 before --seam unit --oracle-version v1 --oracle-file test.sh -- false >/dev/null 2>&1
  printf '%s\n' a1 X2 a3 a4 a5 > src/a.js
  green s1
  ev s2 before --seam unit --oracle-version v1 --oracle-file test.sh -- false >/dev/null 2>&1
  printf '%s\n' a1 X2 a3 X4 a5 > src/a.js
  green s2
  # s1's v2 red is planted in s2's line; the after puts s2's line back.
  printf 'echo stronger\n' >> test.sh
  calq plant s1 --file src/a.js --oracle-file test.sh
  printf '%s\n' a1 X2 a3 BAD a5 > src/a.js
  calq planted s1 --oracle-version v2 --oracle-file test.sh -- false
  [ "$(sed -n 4p src/a.js)" = X4 ]
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:2-2" ]
  run --separate-stderr mr s2
  [ "$output" = "src/a.js:4-4" ]
}

@test "mutate-ranges: a planted red whose patch is missing or changed cannot be attributed (exit 2)" {
  mkdir -p src
  printf '%s\n' a1 a2 a3 a4 a5 > src/a.js
  git add -A && git commit -q -m product
  ev s1 before --seam unit --oracle-version v1 --oracle-file test.sh -- false >/dev/null 2>&1
  printf '%s\n' a1 X2 a3 a4 a5 > src/a.js
  green s1
  printf 'echo stronger\n' >> test.sh
  calq plant s1 --file src/a.js --oracle-file test.sh
  printf '%s\n' a1 X2 a3 BAD a5 > src/a.js
  calq planted s1 --oracle-version v2 --oracle-file test.sh -- false
  green s1
  local p; p=".vetdd/evidence/s1/$(mq s1 '[.runs[] | select(.planted)][0].planted.patch')"
  printf ' ' >> "$p"
  run --separate-stderr mr s1
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"planted patch"* ]] || { echo "$stderr"; false; }
  rm "$p"
  run --separate-stderr mr s1
  [ "$status" -eq 2 ]
}

# --- review round 1 -------------------------------------------------------------------------------

@test "R1: judge-layout refuses a planted patch that holds a .env file, before anything is written" {
  printf 'K=1\n' > .env && git add -f .env && git commit -q -m env
  printf '#!/bin/sh\ngrep -q K=1 .env\n' > envtest.sh && git add envtest.sh && git commit -q -m t
  cal plant s1 --file .env --oracle-file envtest.sh >/dev/null
  printf 'K=2\n' > .env
  cal planted s1 --oracle-version v1 --oracle-file envtest.sh -- sh envtest.sh >/dev/null 2>&1
  ev s1 after -- sh envtest.sh >/dev/null 2>&1
  printf '## Oracle\nK\n' > "$BATS_TEST_TMPDIR/reply.md"
  run JL --out "$BATS_TEST_TMPDIR/out" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *".env"* ]] && [[ "$output" == *"planted patch"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/out" ]
}

@test "R1: judge-layout sends a planted patch with a binary file only when it is named with --allow-binary" {
  printf 'a\000b\n' > blob.bin && git add blob.bin && git commit -q -m bin
  printf '#!/bin/sh\ncmp -s blob.bin blob.orig\n' > bintest.sh && cp blob.bin blob.orig && git add bintest.sh blob.orig && git commit -q -m t
  cal plant s1 --file blob.bin --oracle-file bintest.sh >/dev/null
  printf 'a\000c\n' > blob.bin
  cal planted s1 --oracle-version v1 --oracle-file bintest.sh -- sh bintest.sh >/dev/null 2>&1
  ev s1 after -- sh bintest.sh >/dev/null 2>&1
  grep -q 'GIT binary patch' .vetdd/evidence/s1/runs/001-planted.patch
  printf '## Oracle\nblob\n' > "$BATS_TEST_TMPDIR/reply.md"
  run JL --out "$BATS_TEST_TMPDIR/out" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"blob.bin"* ]] && [[ "$output" == *"--allow-binary"* ]] && [[ "$output" == *"planted patch"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/out" ]
  run JL --out "$BATS_TEST_TMPDIR/out" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD --allow-binary blob.bin s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$BATS_TEST_TMPDIR/out/c1/evidence/s1/runs/001-planted.patch" ]
}

@test "R1: a file git ignores is left out of the planted record (the evidence tree leaves it out too), and stderr says so" {
  mkdir -p ignored && printf 'i\n' > ignored/x.txt
  cal plant s1 --file value.txt --file ignored/x.txt --oracle-file test.sh >/dev/null
  printf '41\n' > value.txt && printf 'j\n' > ignored/x.txt
  run cal planted s1 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s1 '.runs[-1].planted.files | tojson')" = '["value.txt"]' ]
  ! grep -q 'ignored/x.txt' .vetdd/evidence/s1/runs/001-planted.patch || false
  [[ "$output" == *"ignored/x.txt"* ]]
  # Only an ignored file planted: no record of a patch (nothing of it is in the evidence tree).
  cal plant s2 --file ignored/x.txt --oracle-file test.sh >/dev/null
  printf 'k\n' > ignored/x.txt
  run cal planted s2 --oracle-file test.sh -- sh -c 'exit 1'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s2 '.runs[-1] | has("planted")')" = false ]
  [[ "$output" == *"ignored/x.txt"* ]]
}

@test "R1: plant refuses a file whose name holds a tab or another control character, before anything is saved" {
  printf 'x\n' > "$(printf 'a\tb.txt')"
  run cal plant s1 --file "$(printf 'a\tb.txt')" --oracle-file test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"control character"* ]]
  [ ! -e "$(state_dir s1)" ]
}

@test "R1: a planted patch is never written through a link at its name, to a directory or a file" {
  mkdir -p .vetdd/evidence/s1/runs "$BATS_TEST_TMPDIR/outside"
  ln -s "$BATS_TEST_TMPDIR/outside" .vetdd/evidence/s1/runs/001-planted.patch
  cal plant s1 --file value.txt --oracle-file test.sh >/dev/null
  printf '41\n' > value.txt
  run cal planted s1 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/outside")" ]
  [ -f .vetdd/evidence/s1/runs/001-planted.patch ] && [ ! -L .vetdd/evidence/s1/runs/001-planted.patch ]
  run check s1
  [[ "$output" != *"12:"* ]] || { echo "$output"; false; }
}

@test "R1: evidence.sh says when git cannot read the planted patch" {
  local st; st="$(state_dir s1)"
  cal plant s1 --file value.txt --oracle-file test.sh >/dev/null
  printf '41\n' > value.txt
  mkdir "$st/run.lock" && printf 'not a patch\n' > "$st/planted.patch"
  # Run as calibrate.sh runs it: from the process whose pid the state holds (sh -c stays the parent).
  run sh -c 'echo $$ > "$1/pid"; "$2/evidence.sh" s1 calibration --planted "$1/planted.patch" -- touch ran; exit $?' sh "$st" "$SCRIPTS"
  [ "$status" -eq 2 ]
  [[ "$output" == *"git cannot read it as a patch"* ]] || { echo "$output"; false; }
  [ ! -e ran ]
  rmdir "$st/run.lock"
  cal restore s1 >/dev/null
}

# --- review round 2 -------------------------------------------------------------------------------

@test "R2: evidence.sh takes --planted only from the process the planted state names (calibrate.sh's pid)" {
  local st; st="$(state_dir s1)"
  cal plant s1 --file value.txt --oracle-file test.sh >/dev/null
  printf '41\n' > value.txt
  mkdir "$st/run.lock" && git diff -- value.txt > "$st/planted.patch"
  echo 1 > "$st/pid"
  run ev s1 calibration --planted "$st/planted.patch" -- touch ran
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [ ! -e ran ] && [ ! -e .vetdd/evidence/s1/meta.json ]
  run sh -c 'echo $$ > "$1/pid"; "$2/evidence.sh" s1 calibration --planted "$1/planted.patch" -- true; exit $?' sh "$st" "$SCRIPTS"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s1 '.runs[-1].planted.files | tojson')" = '["value.txt"]' ]
  rmdir "$st/run.lock"; rm -f "$st/pid"
  cal restore s1 >/dev/null
}

@test "R2: with core.fileMode false the patch takes modes as the evidence tree does, and a change that leaves that tree as it was gets no record and says why" {
  git config core.fileMode false
  chmod +x value.txt
  cal plant s1 --file value.txt --oracle-file test.sh >/dev/null
  printf '41\n' > value.txt
  run cal planted s1 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  ! grep -q 100755 .vetdd/evidence/s1/runs/001-planted.patch || false
  chmod -x value.txt
  cal plant s2 --file value.txt --oracle-file test.sh >/dev/null
  chmod +x value.txt
  run cal planted s2 --oracle-file test.sh -- sh -c 'exit 1'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s2 '.runs[-1] | has("planted")')" = false ]
  [[ "$output" == *"conversion"* ]] || { echo "$output"; false; }
  [[ "$output" != *"only ignored files changed"* ]]
}

@test "R2: judge-layout checks a planted patch against its recorded sha256 before it goes" {
  planted_slice s1
  printf 'note\n' | cat - .vetdd/evidence/s1/runs/001-planted.patch > "$BATS_TEST_TMPDIR/p" && cp "$BATS_TEST_TMPDIR/p" .vetdd/evidence/s1/runs/001-planted.patch
  printf '## Oracle\nvalue.txt holds 42\n' > "$BATS_TEST_TMPDIR/reply.md"
  run JL --out "$BATS_TEST_TMPDIR/out" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"sha256"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/out" ]
}

@test "R2: judge-layout refuses a planted patch with a file git now ignores or that is no longer there, and names one the diff does not change" {
  planted_slice s1
  printf '## Oracle\nvalue.txt holds 42\n' > "$BATS_TEST_TMPDIR/reply.md"
  run JL --out "$BATS_TEST_TMPDIR/out1" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"value.txt"*"the diff does not change"* ]] || { echo "$output"; false; }
  printf 'value.txt\n' >> .gitignore
  run JL --out "$BATS_TEST_TMPDIR/out2" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"value.txt"* ]] && [[ "$output" == *"ignore"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/out2" ]
  git checkout -q -- .gitignore
  printf 'n\n' > new.txt
  cal plant s2 --file new.txt --oracle-file test.sh >/dev/null
  printf 'm\n' > new.txt
  cal planted s2 --oracle-file test.sh -- sh -c 'exit 1' >/dev/null 2>&1
  rm new.txt
  run JL --out "$BATS_TEST_TMPDIR/out3" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s2
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"new.txt"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/out3" ]
}
