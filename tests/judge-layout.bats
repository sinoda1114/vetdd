#!/usr/bin/env bats
# judge-layout.sh (#25): build the final judge's directory that references/final-judge-rubric.md
# "Layout" defines, instead of by hand: the diff (new files included, the index untouched), the reply
# draft, the check-evidence output, the oracle files, each slice's meta.json, its red-run logs, and the
# copy of its judged mutation report; absolute paths of this machine replaced; check-blind run on it.
# A negated command mid-test is written `! cmd || false`: bats does not fail a test on a bare `! cmd`.

load test_helper

FIX_STRYKER="$BATS_TEST_DIRNAME/fixtures/reports/stryker10-range.json"
JL() { "$SCRIPTS/judge-layout.sh" "$@"; }

setup() {
  make_repo
  record_good_slice s1 >/dev/null 2>&1
  printf '## Oracle\nvalue.txt holds 42\n' > "$BATS_TEST_TMPDIR/reply.md"
  OUT="$BATS_TEST_TMPDIR/judge/candidates"
}

@test "the layout holds the diff, the reply, the check-evidence output, the oracle files, meta.json, and the red-run logs only" {
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local C="$OUT/c1"
  grep -q '^+42$' "$C/artifact/diff.patch"
  cmp -s "$C/artifact/reply.md" "$BATS_TEST_TMPDIR/reply.md"
  [ "$(tail -1 "$C/artifact/check-evidence.txt")" = "exit 0" ]
  grep -q '^s1: OK$' "$C/artifact/check-evidence.txt"
  cmp -s "$C/artifact/tests/test.sh" test.sh
  cmp -s "$C/evidence/s1/meta.json" .vetdd/evidence/s1/meta.json
  [ -f "$C/evidence/s1/runs/001-before.log" ]
  # Green logs stay on the machine.
  [ ! -e "$C/evidence/s1/runs/002-after.log" ]
  # It prints the judge.sh command to run next.
  [[ "$output" == *'judge.sh" --rubric'* ]]
}

@test "a new untracked product file is in the diff, and the real index is left as it was" {
  printf 'new\n' > added.txt
  local before; before="$(git diff --cached --name-only; git ls-files)"
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '^+++ b/added.txt$' "$OUT/c1/artifact/diff.patch"
  [ "$(git diff --cached --name-only; git ls-files)" = "$before" ]
  # .vetdd is never part of the diff.
  ! grep -q '\.vetdd/' "$OUT/c1/artifact/diff.patch" || false
}

@test "a failing check-evidence is copied with its exit code, not hidden" {
  printf '7\n' > value.txt
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(tail -1 "$OUT/c1/artifact/check-evidence.txt")" = "exit 1" ]
  grep -q 's1: FAIL' "$OUT/c1/artifact/check-evidence.txt"
}

@test "the repository's absolute path is replaced with <repo> in every copied file" {
  printf 'ran in %s\n' "$REPO" >> .vetdd/evidence/s1/runs/001-before.log
  printf 'see %s/value.txt\n' "$REPO" >> "$BATS_TEST_TMPDIR/reply.md"
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  ! grep -rqF "$REPO" "$OUT" || false
  grep -q 'ran in <repo>' "$OUT/c1/evidence/s1/runs/001-before.log"
  grep -q 'see <repo>/value.txt' "$OUT/c1/artifact/reply.md"
}

@test "the undefined-imports audit log and the judged mutation copy are in; an older mutation copy is not" {
  mkdir -p src && jq -j '.files["src/dueDate.ts"].source' "$FIX_STRYKER" > src/dueDate.ts
  printf 'mkdir -p .vetdd/reports\ncp "$REPORT" .vetdd/reports/m.json\nexit "${EXIT:-0}"\n' > mrun.sh
  git add -A && git commit -q -m p && record_good_slice s1 >/dev/null 2>&1
  ev s1 calibration --audit undefined-imports -- sh -c 'exit 1' >/dev/null 2>&1 || true
  jq --arg r "$REPO" '.projectRoot = $r | .config.testRunner = "command" | .config.commandRunner.command = "x" | .files["src/dueDate.ts"].mutants |= map(.status = "Killed")' "$FIX_STRYKER" > "$BATS_TEST_TMPDIR/k.json"
  REPORT="$BATS_TEST_TMPDIR/k.json" ev s1 calibration --audit mutation --mutation-report stryker-json:.vetdd/reports/m.json -- sh mrun.sh >/dev/null 2>&1
  REPORT="$BATS_TEST_TMPDIR/k.json" ev s1 calibration --audit mutation --mutation-report stryker-json:.vetdd/reports/m.json -- sh mrun.sh >/dev/null 2>&1
  local first last
  first="$(jq -r '[.runs[] | select(.audit.kind == "mutation")][0].audit.report.copy' .vetdd/evidence/s1/meta.json)"
  last="$(jq -r '[.runs[] | select(.audit.kind == "mutation")][-1].audit.report.copy' .vetdd/evidence/s1/meta.json)"
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local seq; seq="$(jq -r '[.runs[] | select(.audit.kind == "undefined-imports")][-1].seq' .vetdd/evidence/s1/meta.json)"
  [ -f "$OUT/c1/evidence/s1/runs/$(printf '%03d' "$seq")-calibration.log" ]
  [ -f "$OUT/c1/evidence/s1/$last" ]
  [ ! -e "$OUT/c1/evidence/s1/$first" ]
}

@test "the result must pass the judge's blind check: a model name in the reply stops it (exit 4)" {
  printf 'written by Claude\n' >> "$BATS_TEST_TMPDIR/reply.md"
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 4 ]
  [[ "$output" == *"check-blind"* ]]
}

@test "usage errors: no slice, no reply, an unknown slice, an --out that exists, a bad base (exit 2), and nothing is written" {
  run JL --out "$OUT" --base HEAD s1
  [ "$status" -eq 2 ]
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD
  [ "$status" -eq 2 ]
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD nope
  [ "$status" -eq 2 ]
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base no-such-ref s1
  [ "$status" -eq 2 ]
  [ ! -e "$OUT" ]
  mkdir -p "$OUT"
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 2 ]
  [[ "$output" == *"exists"* ]]
}

@test "test mode's Close step 4 builds the layout with judge-layout.sh" {
  sed -n '/^## Close/,/^## /p' "$SCRIPTS/../modes/test.md" | grep -q 'judge-layout.sh'
}
