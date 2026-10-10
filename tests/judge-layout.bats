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
  [[ "$output" == *'judge.sh --rubric'* ]]
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

# --- review round 1 ------------------------------------------------------------------------------

@test "a staged new file not yet committed is in the diff (Y1)" {
  printf 'staged\n' > staged.txt && git add staged.txt
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '^+++ b/staged.txt$' "$OUT/c1/artifact/diff.patch"
  [ "$(git diff --cached --name-only)" = staged.txt ]
}

@test "the path is replaced only as a whole path: a longer path that starts with it is kept (Y2)" {
  printf '%s2/other and %s/x\n' "$REPO" "$REPO" >> .vetdd/evidence/s1/runs/001-before.log
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qF '2/other and <repo>/x' "$OUT/c1/evidence/s1/runs/001-before.log"
  ! grep -q '<repo>2/other' "$OUT/c1/evidence/s1/runs/001-before.log" || false
}

@test "the mutation copy sent is the one check-evidence judges: none when the latest mutation run after the final green is not usable (Y3)" {
  mkdir -p src && jq -j '.files["src/dueDate.ts"].source' "$FIX_STRYKER" > src/dueDate.ts
  printf 'mkdir -p .vetdd/reports\n[ -z "${REPORT:-}" ] || cp "$REPORT" .vetdd/reports/m.json\nexit 0\n' > mrun.sh
  git add -A && git commit -q -m p && record_good_slice s1 >/dev/null 2>&1
  jq --arg r "$REPO" '.projectRoot = $r | .config.testRunner = "command" | .config.commandRunner.command = "x" | .files["src/dueDate.ts"].mutants |= map(.status = "Killed")' "$FIX_STRYKER" > "$BATS_TEST_TMPDIR/k.json"
  REPORT="$BATS_TEST_TMPDIR/k.json" ev s1 calibration --audit mutation --mutation-report stryker-json:.vetdd/reports/m.json -- sh mrun.sh >/dev/null 2>&1
  ev s1 calibration --audit mutation --mutation-report stryker-json:.vetdd/reports/m.json -- sh mrun.sh >/dev/null 2>&1
  [ "$(jq -r '.runs[-1].audit.report.status' .vetdd/evidence/s1/meta.json)" = missing ]
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -z "$(ls "$OUT/c1/evidence/s1/runs" | grep mutation.json)" ]
}

@test "an --out inside the repository (outside .vetdd) is refused before anything is written (Y4)" {
  run JL --out "$REPO/judge-dir" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 2 ]
  [ ! -e "$REPO/judge-dir" ]
  run JL --out "$REPO/.vetdd/judge/c" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a check-blind that could not run is a local failure (exit 1), not 'not blind' (Y5)" {
  grep -q 'blind_rc' "$SCRIPTS/judge-layout.sh"
}

@test "a malformed meta.json fails the build instead of shipping an empty layout (Y6)" {
  jq '.runs[0] = "x"' .vetdd/evidence/s1/meta.json > m && mv m .vetdd/evidence/s1/meta.json
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "an untracked file whose name starts with : is taken literally (Y7)" {
  printf 'memo\n' > ':memo'
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qF '+++ b/:memo' "$OUT/c1/artifact/diff.patch"
}

@test "--allow-secrets passes to check-blind and to the printed judge command (Y8)" {
  printf '# password = "hunter2hunter2"\n' >> test.sh
  git add test.sh && git commit -q -m pw
  record_good_slice s2 >/dev/null 2>&1
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s2
  [ "$status" -eq 4 ] || { echo "$output"; false; }
  rm -rf "$BATS_TEST_TMPDIR/judge"
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD --allow-secrets 'c1/artifact/tests/*:assignment' s2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *'--allow-secrets c1/artifact/tests/\*:assignment'* ]] || { echo "$output"; false; }
}

@test "the mutation audit's log is not sent as a red-run log, the undefined-imports audit's is" {
  ev s1 calibration --audit undefined-imports -- sh -c 'exit 1' >/dev/null 2>&1 || true
  printf 'mkdir -p .vetdd/reports\nexit 1\n' > mrun.sh
  ev s1 calibration --audit mutation --mutation-report stryker-json:.vetdd/reports/m.json -- sh mrun.sh >/dev/null 2>&1 || true
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local ui mu
  ui="$(jq -r '[.runs[] | select(.audit.kind == "undefined-imports")][-1].log' .vetdd/evidence/s1/meta.json)"
  mu="$(jq -r '[.runs[] | select(.audit.kind == "mutation")][-1].log' .vetdd/evidence/s1/meta.json)"
  [ -f "$OUT/c1/evidence/s1/$ui" ]
  [ ! -e "$OUT/c1/evidence/s1/$mu" ]
}

# --- review round 2 ------------------------------------------------------------------------------

@test "the temporary index lives in a private temporary directory, never at a freed name (Z1)" {
  grep -q 'mktemp -d' "$SCRIPTS/judge-layout.sh"
  ! grep -q 'rm -f "$idx"$' "$SCRIPTS/judge-layout.sh" || false
}

@test "a binary file in the diff stops the build unless named with --allow-binary (Z2)" {
  printf 'a\0b' > blob.bin
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"blob.bin"* ]]
  [ ! -e "$OUT" ]
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD --allow-binary blob.bin s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q 'blob.bin' "$OUT/c1/artifact/diff.patch"
}

@test "an --out whose missing part climbs with .. is refused (Z3)" {
  run JL --out "$REPO/.vetdd/not-created/../../judge-dir" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 2 ]
  [ ! -e "$REPO/judge-dir" ]
  run JL --out "$BATS_TEST_TMPDIR/x/../y" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 2 ]
}

@test "a new file added with git add -f (ignored) is in the diff (Z4)" {
  mkdir -p ignored && printf 'forced\n' > ignored/forced.txt && git add -f ignored/forced.txt
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '^+++ b/ignored/forced.txt$' "$OUT/c1/artifact/diff.patch"
}

@test "a JSON-escaped path is replaced too, and a path that only ends with the root's name is kept (Z5)" {
  local esc; esc="$(printf '%s' "$REPO" | sed 's#/#\\/#g')"
  printf '{"cwd":"%s\\/x"} and /mnt%s/y\n' "$esc" "$REPO" >> .vetdd/evidence/s1/runs/001-before.log
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qF '{"cwd":"<repo>\/x"}' "$OUT/c1/evidence/s1/runs/001-before.log"
  grep -qF "/mnt$REPO/y" "$OUT/c1/evidence/s1/runs/001-before.log" || grep -qF "/mnt" "$OUT/c1/evidence/s1/runs/001-before.log"
  ! grep -qF '/mnt<repo>' "$OUT/c1/evidence/s1/runs/001-before.log" || false
}

@test "the diff ignores the user's color, prefix, and textconv settings (Z7)" {
  git config color.ui always && git config diff.noprefix true
  printf 'new\n' > added.txt
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '^+++ b/added.txt$' "$OUT/c1/artifact/diff.patch"
  ! grep -q "$(printf '\033')" "$OUT/c1/artifact/diff.patch" || false
}

@test "an unknown --allow-secrets kind is a usage error before anything is written; the printed command is shell-quoted (Z8)" {
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD --allow-secrets 'c1/x:nonsense' s1
  [ "$status" -eq 2 ]
  [ ! -e "$OUT" ]
  run JL --out "$BATS_TEST_TMPDIR/it's dir" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local cmd; cmd="$(printf '%s\n' "$output" | sed -n 's/^next: //p' | sed 's/--out <judge.json>.*//')"
  # The printed --candidates value, read back by a shell, is the directory itself.
  eval "set -- $cmd"
  local cand=""; while [ $# -gt 0 ]; do [ "$1" = --candidates ] && cand="$2"; shift; done
  # The physical path judge-layout.sh checked (the test directory may sit behind a link such as /var).
  [ "$cand" = "$(cd -P "$BATS_TEST_TMPDIR" && pwd -P)/it's dir" ] || { echo "got [$cand]"; false; }
}

@test "a check-blind that could not run is exit 1, not 4 (Y5, by behavior)" {
  local fake="$BATS_TEST_TMPDIR/fakescripts"
  cp -R "$SCRIPTS" "$fake"
  printf '#!/bin/sh\nexit 2\n' > "$fake/check-blind.sh"
  run "$fake/judge-layout.sh" --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "every new file going out in the diff is named on stderr" {
  printf 'new\n' > added.txt
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"new file in the diff: added.txt"* ]]
}

# --- PR review threads -----------------------------------------------------------------------------

@test "a staged rename into an ignored path keeps the destination in the diff, not only the removal" {
  # value.txt is tracked; move it under ignored/ in the index.
  mkdir -p ignored && git mv -f value.txt ignored/value.txt
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '^+++ b/ignored/value.txt$' "$OUT/c1/artifact/diff.patch"
}

@test "verify mode does not build its layout with judge-layout.sh, which does not copy verify artifacts" {
  ! sed -n '/^### B/,/^### C/p' "$SCRIPTS/../modes/verify.md" | grep -q 'judge-layout.sh' || false
}

# --- #28 -------------------------------------------------------------------------------------------

@test "#28: --out and everything in it are private to the user, also when the build stops not blind (exit 4)" {
  printf 'written by Claude\n' >> "$BATS_TEST_TMPDIR/reply.md"
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 4 ] || { echo "$output"; false; }
  [ "$(ls -ld "$OUT" | cut -c1-10)" = "drwx------" ]
  [ -z "$(find "$OUT" -perm -004 -o -perm -040 | head -1)" ]
}

@test "#28: an --out whose parent others could write without the sticky bit is refused; a private parent is fine" {
  # Anyone who can write a directory without the sticky bit can rename the layout away and swap in another.
  mkdir -m 777 "$BATS_TEST_TMPDIR/open"; chmod 777 "$BATS_TEST_TMPDIR/open"
  run JL --out "$BATS_TEST_TMPDIR/open/c" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"parent"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/open/c" ]
  # A missing parent is made private to the user.
  run JL --out "$BATS_TEST_TMPDIR/new/deeper/c" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ls -ld "$BATS_TEST_TMPDIR/new/deeper" | cut -c1-10)" = "drwx------" ]
}

@test "#28: a file:// URL and a path that ends a sentence have the repository path replaced too" {
  printf 'at file://%s/src/x.mjs:3\nran in %s.\n' "$REPO" "$REPO" >> .vetdd/evidence/s1/runs/001-before.log
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qF 'at file://<repo>/src/x.mjs:3' "$OUT/c1/evidence/s1/runs/001-before.log"
  grep -qF 'ran in <repo>.' "$OUT/c1/evidence/s1/runs/001-before.log"
  ! grep -rqF "$REPO" "$OUT" || false
}

@test "#28: --allow-binary matches a name with non-ASCII characters" {
  printf 'a\0b' > "$(printf 'b\303\274.bin')"
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD --allow-binary "$(printf 'b\303\274.bin')" s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "#28: --allow-binary matches a renamed binary by its new name" {
  printf 'a\0b' > old.bin && git add old.bin && git commit -qm bin
  git mv old.bin new.bin
  # Both sides leave as base85 (git diff --binary carries the removed content as the reverse patch).
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD --allow-binary new.bin s1
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"old.bin"* ]]
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD --allow-binary new.bin --allow-binary old.bin s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "#28: an --allow-secrets value check-blind would refuse is a usage error before anything is written" {
  local v
  for v in 'c1/x:' 'c1/x:email,' ':email'; do
    run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD --allow-secrets "$v" s1
    [ "$status" -eq 2 ] || { echo "$v: $output"; false; }
    [ ! -e "$OUT" ]
  done
}

@test "#28: a check-evidence.sh that cannot run stops the build (exit 1)" {
  local fake="$BATS_TEST_TMPDIR/fakescripts"
  cp -R "$SCRIPTS" "$fake"
  chmod -x "$fake/check-evidence.sh"
  run "$fake/judge-layout.sh" --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "#28: a red-run log the record names but the repository lacks stops the build (exit 1)" {
  rm .vetdd/evidence/s1/runs/001-before.log
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"001-before.log"* ]]
}

@test "#28: a staged new file removed from the working tree is skipped; a staged one is named once" {
  printf 'gone\n' > gone.txt && git add gone.txt && rm gone.txt
  printf 'kept\n' > kept.txt && git add kept.txt
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'new file in the diff: kept.txt')" -eq 1 ]
  grep -q '^+++ b/kept.txt$' "$OUT/c1/artifact/diff.patch"
}

@test "#28 r1: an --out with a trailing slash is built (its parent exists)" {
  mkdir -p "$(dirname "$OUT")"
  run JL --out "$OUT/" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$OUT/c1/artifact/diff.patch" ]
}

@test "#28 r1: the layout is built at the checked physical path, not through a link another user could swap" {
  mkdir -m 700 "$BATS_TEST_TMPDIR/safe"; ln -s "$BATS_TEST_TMPDIR/safe" "$BATS_TEST_TMPDIR/link"
  local phys; phys="$(cd -P "$BATS_TEST_TMPDIR/safe" && pwd -P)"
  run JL --out "$BATS_TEST_TMPDIR/link/c" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"built $phys/c"* ]]
  [[ "$output" == *"--candidates $phys/c"* ]]
}

@test "#28 r1: under an unsafe parent nothing is created, not even the missing directories in between" {
  mkdir -m 777 "$BATS_TEST_TMPDIR/open"; chmod 777 "$BATS_TEST_TMPDIR/open"
  run JL --out "$BATS_TEST_TMPDIR/open/new/c" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [ ! -e "$BATS_TEST_TMPDIR/open/new" ]
}

@test "#28 r1: a file: URL with JSON-escaped slashes has the repository path replaced" {
  local esc; esc="$(printf '%s' "$REPO" | sed 's#/#\\/#g')"
  printf '{"u":"file:\\/\\/%s\\/x.mjs"}\n' "$esc" >> .vetdd/evidence/s1/runs/001-before.log
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qF '"file:\/\/<repo>\/x.mjs"' "$OUT/c1/evidence/s1/runs/001-before.log"
}

# --- #35 -------------------------------------------------------------------------------------------

@test "#35: a verify script under .claude/skills/ does not stop the blind check: the directory is sent as .agent/" {
  mkdir -p .claude/skills/verify-x
  printf '#!/bin/sh\n[ "$(cat value.txt)" = "42" ]\n' > .claude/skills/verify-x/verify-a.sh
  git add .claude && git commit -qm verify
  printf '0\n' > value.txt
  ev s2 before --seam unit --oracle-version v1 --oracle-file .claude/skills/verify-x/verify-a.sh -- sh .claude/skills/verify-x/verify-a.sh >/dev/null 2>&1
  printf '42\n' > value.txt
  ev s2 after -- sh .claude/skills/verify-x/verify-a.sh >/dev/null 2>&1
  printf 'new\n' > .claude/skills/verify-x/notes.txt
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD~1 s2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$OUT/c1/artifact/tests/.agent/skills/verify-x/verify-a.sh" ]
  grep -q '^+++ b/.agent/skills/verify-x/notes.txt$' "$OUT/c1/artifact/diff.patch"
  grep -q '"\.agent/skills/verify-x/verify-a\.sh"' "$OUT/c1/evidence/s2/meta.json"
  if grep -rqi 'claude' "$OUT"; then grep -rni claude "$OUT"; false; fi
  [ -z "$(find "$OUT" -iname '*claude*')" ]
}

@test "#35: a model name elsewhere still stops the build (only the .claude directory is renamed)" {
  printf 'written by Claude\n' >> "$BATS_TEST_TMPDIR/reply.md"
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 4 ]
}

@test "#35: test mode takes a surface slice's red as before while the fix is not in the tree, unfix once it is" {
  local l; l="$(grep -F 'another surface than the agreed unit seam' "$SCRIPTS/../modes/test.md")"
  [[ "$l" == *'as `before` while the fix is not in the tree'* ]]
  [[ "$l" == *'`calibrate.sh unfix` once it is'* ]]
}

@test "#35: verify mode warns that Stryker does not link a node_modules that is itself a link" {
  grep -q 'node_modules.*symbolic link\|symbolic link.*node_modules' "$SCRIPTS/../modes/verify.md"
}

@test "#35: the rubric's Layout says the author's tool directory is sent as .agent/" {
  grep -q '\.agent/' "$SCRIPTS/../references/final-judge-rubric.md"
}

@test "#35 r1: the real final rubric passes the judge's blind check (judge.sh copies it into the judge's input)" {
  mkdir -p "$BATS_TEST_TMPDIR/rb" && cp "$SCRIPTS/../references/final-judge-rubric.md" "$BATS_TEST_TMPDIR/rb/rubric.md"
  run "$SCRIPTS/check-blind.sh" "$BATS_TEST_TMPDIR/rb" --profile judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "#35 r1: a removed line naming .claude/ in the diff is renamed too" {
  printf '.claude/\n' >> .gitignore && git add .gitignore && git commit -qm ignore
  sed -i.bak '$d' .gitignore && rm -f .gitignore.bak
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx -- '-.agent/' "$OUT/c1/artifact/diff.patch"
}

@test "#35 r1: a .claude path and an .agent path that would meet after renaming stop the build (exit 1)" {
  mkdir -p .claude/x .agent/x
  printf 'one\n' > .claude/x/t.sh; printf 'two\n' > .agent/x/t.sh
  git add -f .claude .agent && git commit -qm both
  printf '0\n' > value.txt
  ev s3 before --seam unit --oracle-version v1 --oracle-file test.sh --oracle-file .claude/x/t.sh --oracle-file .agent/x/t.sh -- sh test.sh >/dev/null 2>&1
  printf '42\n' > value.txt
  ev s3 after -- sh test.sh >/dev/null 2>&1
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s3
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *".agent"* ]]
}

@test "#35 r1: the user's home directory is replaced with <home> (a .claude path under it no longer stops the build)" {
  local home; home="$(cd -P "$HOME" && pwd -P)"
  printf 'ran %s/.claude/skills/vetdd/scripts/evidence.sh\n' "$HOME" >> .vetdd/evidence/s1/runs/001-before.log
  run JL --out "$OUT" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qF 'ran <home>/.agent/skills/vetdd/scripts/evidence.sh' "$OUT/c1/evidence/s1/runs/001-before.log"
  if grep -rqF "$home/" "$OUT"; then grep -rnF "$home/" "$OUT"; false; fi
}

@test "#35 r1: verify mode's node_modules link survives a sandbox reused for the next mutant (ln -sfn)" {
  grep -q 'ln -sfn ../../node_modules node_modules' "$SCRIPTS/../modes/verify.md"
}
