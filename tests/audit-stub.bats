#!/usr/bin/env bats
# The undefined-imports audit (IDS's Audit step, principle 4's quick check): every product file the
# oracle imports is replaced by a stub whose exports are all undefined; the oracle must go red.
#   calibrate.sh stub   plants the stubs, runs the oracle as an audit-marked calibration, restores
#   evidence.sh --audit  puts the mark on the run
#   audit-note.sh        records why the audit does not apply
#   check-evidence       rule 10a (a stubbed oracle that still passed) and 10b (no audit for the final oracle)

load test_helper

setup() {
  make_repo
  printf 'export const f = (n: number) => n * 2;\n' > lib.ts
  printf 'def f(n):\n    return n * 2\n' > mod.py
  # real.sh sees the product: it goes red once lib.ts is a stub. vac.sh never reads it.
  printf '#!/bin/sh\ngrep -q "n \\* 2" lib.ts\n' > real.sh
  printf '#!/bin/sh\nexit 0\n' > vac.sh
  # spy.sh copies the file it is given while the oracle runs, so a test can see the stub.
  printf '#!/bin/sh\ncat "$1" > seen.out\nexit 0\n' > spy.sh
  git add -A && git commit -q -m product
  LIB='export const f = (n: number) => n * 2;'
}

cal() { "$SCRIPTS/calibrate.sh" "$@"; }
an() { "$SCRIPTS/audit-note.sh" "$@"; }
state_dir() { printf '%s/vetdd-calib/%s' "$(git rev-parse --git-dir)" "$1"; }
clean_tree() { git diff --quiet && git diff --cached --quiet; }
# GNU stat first: BSD stat has no -c (no output), but GNU stat -f prints file system data.
perm() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
no_control() { ! printf '%s' "$1" | LC_ALL=C grep -q "$(printf '[\001-\010\013-\037\177]')"; }
meta_unchanged() { [ ! -e "$REPO/.vetdd/evidence/$1/meta.json" ]; }

# --- calibrate.sh stub ---------------------------------------------------------------------------

@test "a vacuous test passes under the stub: exit 1, plainly said, the run marked, the file back" {
  run cal stub s1 --file lib.ts --seam unit --oracle-version v1 --oracle-file vac.sh -- sh vac.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"vacuous"* ]]
  [[ "$output" == *"observes nothing"* ]]
  [ "$(mq s1 '.runs[-1].kind')" = calibration ]
  [ "$(mq s1 '.runs[-1].outcome')" = pass ]
  [ "$(mq s1 '.runs[-1].audit.kind')" = undefined-imports ]
  [ "$(mq s1 '.oracle.seam')" = unit ]
  [ "$(mq s1 '.oracle.version')" = v1 ]
  [ "$(cat lib.ts)" = "$LIB" ]
  clean_tree
  [ ! -e "$(state_dir s1)" ]
}

@test "a real test goes red under the stub: exit 0, outcome target_failure, the file back" {
  run cal stub s1 --file lib.ts --oracle-file real.sh -- sh real.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s1 '.runs[-1].kind')" = calibration ]
  [ "$(mq s1 '.runs[-1].outcome')" = target_failure ]
  [ "$(mq s1 '.runs[-1].audit.kind')" = undefined-imports ]
  [ "$(cat lib.ts)" = "$LIB" ]
  clean_tree
  [ ! -e "$(state_dir s1)" ]
}

@test "a caught audit tells the reader to check the red is the test's own, not an import error" {
  run cal stub s1 --file lib.ts --oracle-file real.sh -- sh real.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"read the log"* ]]
}

@test "the stub matches the module system of each extension, in any letter case, and the python stub for .py" {
  local ext want
  for ext in ts tsx jsx mjs mts TS Mjs; do
    printf 'export const g = 1;\n' > "a.$ext"
    git add -A && git commit -q -m "a.$ext"
    rm -f seen.out
    run cal stub "e-$ext" --file "a.$ext" --oracle-file spy.sh -- sh spy.sh "a.$ext"
    [ "$status" -eq 1 ] || { echo "$ext: $output"; false; }
    [ "$(cat seen.out)" = 'export {};' ] || { echo "$ext: $(cat seen.out)"; false; }
    [ "$(cat "a.$ext")" = 'export const g = 1;' ]
  done
  # CommonJS: a .cjs is always CommonJS; a .js without "type": "module" is read either way.
  printf 'exports.g = 1;\n' > a.cjs
  printf 'exports.g = 1;\n' > a.js
  git add -A && git commit -q -m cjs
  run cal stub cj1 --file a.cjs --oracle-file spy.sh -- sh spy.sh a.cjs
  [ "$(cat seen.out)" = 'module.exports = {};' ] || { echo "cjs: $(cat seen.out)"; false; }
  # A .cts is CommonJS to Node's own TypeScript loader, so `export {};` would be a syntax error there.
  printf 'export const g = 1;\n' > a.cts
  git add -A && git commit -q -m cts
  run cal stub cj4 --file a.cts --oracle-file spy.sh -- sh spy.sh a.cts
  [ "$(cat seen.out)" = 'module.exports = {};' ] || { echo "cts: $(cat seen.out)"; false; }
  run cal stub cj2 --file a.js --oracle-file spy.sh -- sh spy.sh a.js
  [ "$(cat seen.out)" = 'if (typeof module !== "undefined") { module.exports = {}; }' ] || { echo "js: $(cat seen.out)"; false; }
  # A package that says "type": "module" makes a .js an ES module.
  printf '{"type": "module"}\n' > package.json
  git add -A && git commit -q -m esm
  run cal stub cj3 --file a.js --oracle-file spy.sh -- sh spy.sh a.js
  [ "$(cat seen.out)" = 'export {};' ] || { echo "esm js: $(cat seen.out)"; false; }
  run cal stub p1 --file mod.py --oracle-file spy.sh -- sh spy.sh mod.py
  [ "$status" -eq 1 ]
  [ "$(cat seen.out)" = "$(printf "def __getattr__(name):\n    if name.startswith('__') and name.endswith('__'):\n        raise AttributeError(name)\n    return None")" ]
  [ "$(cat mod.py)" = "$(printf 'def f(n):\n    return n * 2')" ]
}

@test "a stubbed CommonJS file loads: the oracle runs to its assertion instead of failing on syntax (N1)" {
  command -v node >/dev/null || skip "node not installed"
  printf 'exports.f = (n) => n * 2;\n' > c.cjs
  printf 'exports.f = (n) => n * 2;\n' > d.js
  # Exit 0 when f is undefined (the stub loaded and removed it): a syntax error would exit 1 on the stub.
  printf '#!/bin/sh\nnode -e "if (require(\\"./$1\\").f !== undefined) process.exit(1)"\n' > loads.sh
  git add -A && git commit -q -m cjs
  run cal stub l1 --file c.cjs --oracle-file loads.sh -- sh loads.sh c.cjs
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"vacuous"* ]]
  run cal stub l2 --file d.js --oracle-file loads.sh -- sh loads.sh d.js
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"vacuous"* ]]
}

@test "the restored file is newer than anything the stubbed run built (N3)" {
  printf 'export const f = 1;\n' > m.ts
  git add -A && git commit -q -m m
  touch -t 200001010000 m.ts
  printf '#!/bin/sh\necho built > built.out\nexit 1\n' > build.sh
  run cal stub mt --file m.ts --oracle-file build.sh -- sh build.sh
  [ "$status" -eq 0 ]
  [ -f built.out ]
  # Not older than the build output: a make-like tool must see the source as changed.
  [ ! built.out -nt m.ts ] || { echo "m.ts is older than built.out"; false; }
}

@test "every named file is stubbed in one run, and each comes back" {
  printf 'export const h = 1;\n' > other.ts && git add -A && git commit -q -m other
  printf '#!/bin/sh\ncat lib.ts other.ts mod.py > seen.out\n' > spy2.sh
  run cal stub s1 --file lib.ts --file other.ts --file mod.py --oracle-file spy2.sh -- sh spy2.sh
  [ "$status" -eq 1 ]
  [ "$(cat seen.out)" = "$(printf "export {};\nexport {};\ndef __getattr__(name):\n    if name.startswith('__') and name.endswith('__'):\n        raise AttributeError(name)\n    return None")" ]
  [ "$(cat lib.ts)" = "$LIB" ]
  [ "$(cat other.ts)" = 'export const h = 1;' ]
  clean_tree
}

@test "a file with another extension is a usage error before anything is parked or changed" {
  printf 'x\n' > Makefile && printf 'v\n' > notes.md && git add -A && git commit -q -m more
  run cal stub s1 --file lib.ts --file notes.md --oracle-file vac.sh -- sh vac.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"notes.md"* ]]
  [ "$(cat lib.ts)" = "$LIB" ]
  [ ! -e "$(state_dir s1)" ]
  meta_unchanged s1
  run cal stub s1 --file Makefile --oracle-file vac.sh -- sh vac.sh
  [ "$status" -eq 2 ]
  run cal stub s1 --file value.txt --oracle-file vac.sh -- sh vac.sh
  [ "$status" -eq 2 ]
  [ ! -e "$(state_dir s1)" ]
}

@test "a missing file, a link, a directory, and a file outside the repository are refused (exit 2)" {
  run cal stub s0 --file lib.ts --oracle-file vac.sh -- sh vac.sh  # the same call with a good file runs
  [ "$status" -eq 1 ]
  ln -s lib.ts link.ts
  printf 'x\n' > "$BATS_TEST_TMPDIR/outside.ts"
  local arg
  for arg in missing.ts link.ts sub "$BATS_TEST_TMPDIR/outside.ts"; do
    run cal stub s1 --file "$arg" --oracle-file vac.sh -- sh vac.sh
    [ "$status" -eq 2 ] || { echo "$arg: $output"; false; }
    [ ! -e "$(state_dir s1)" ]
    meta_unchanged s1
  done
  [ "$(cat lib.ts)" = "$LIB" ]
}

@test "an oracle file named in --file is refused, in any spelling, and never stubbed" {
  printf 'import { it } from "vitest";\n' > t.test.ts && git add -A && git commit -q -m t
  run cal stub s1 --file t.test.ts --oracle-file t.test.ts -- true
  [ "$status" -eq 2 ]
  [[ "$output" == *"oracle"* ]]
  run cal stub s1 --file lib.ts --file ./t.test.ts --oracle-file t.test.ts -- true
  [ "$status" -eq 2 ]
  [[ "$output" == *"oracle"* ]]
  [ "$(cat t.test.ts)" = 'import { it } from "vitest";' ]
  [ "$(cat lib.ts)" = "$LIB" ]
  meta_unchanged s1
}

@test "stub needs --file, --oracle-file, and a command, and refuses what plant and unfix refuse" {
  run cal stub s1 --oracle-file vac.sh -- sh vac.sh;      [ "$status" -eq 2 ]
  run cal stub s1 --file lib.ts -- sh vac.sh;             [ "$status" -eq 2 ]
  [[ "$output" == *"--oracle-file"* ]]
  run cal stub s1 --file lib.ts --oracle-file vac.sh;     [ "$status" -eq 2 ]
  run cal stub s1 --file lib.ts --oracle-file vac.sh --outcome target_failure -- sh vac.sh; [ "$status" -eq 2 ]
  run cal stub s1 --file lib.ts --oracle-version '1.0+rc' --oracle-file vac.sh -- sh vac.sh; [ "$status" -eq 2 ]
  [[ "$output" == *"--oracle-version"* ]]
  [ "$(cat lib.ts)" = "$LIB" ]
  meta_unchanged s1
  [ ! -e "$(state_dir s1)" ]
}

@test "an interrupted stub run leaves the original where restore finds it, and restore puts it back" {
  export VETDD_TEST_HOOKS=1
  printf '#!/bin/sh\nkill -9 "$VETDD_CALIBRATE_PID"\n' > killer.sh
  run cal stub s1 --file lib.ts --oracle-file real.sh -- sh killer.sh
  [ "$(cat lib.ts)" = 'export {};' ]
  [ -f "$(state_dir s1)/copies/lib.ts" ]
  run cal stub s1 --file lib.ts --oracle-file real.sh -- sh real.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"restore s1"* ]]
  run cal restore s1
  [ "$status" -eq 0 ]
  [ "$(cat lib.ts)" = "$LIB" ]
  clean_tree
  [ ! -e "$(state_dir s1)" ]
}

@test "a staged edit and an untracked product file come back byte for byte, index entry included" {
  printf 'export const f = (n: number) => n * 3;\n' > lib.ts && git add lib.ts
  printf 'export const f = (n: number) => n * 3; // later\n' > lib.ts
  printf 'export const fresh = 1;\n' > fresh.ts
  cp lib.ts "$BATS_TEST_TMPDIR/lib.ts.before"; cp fresh.ts "$BATS_TEST_TMPDIR/fresh.ts.before"
  git diff --cached > "$BATS_TEST_TMPDIR/cached.before"
  run cal stub s1 --file lib.ts --file fresh.ts --oracle-file vac.sh -- sh vac.sh
  [ "$status" -eq 1 ]
  cmp lib.ts "$BATS_TEST_TMPDIR/lib.ts.before"
  cmp fresh.ts "$BATS_TEST_TMPDIR/fresh.ts.before"
  [ "$(git diff --cached)" = "$(cat "$BATS_TEST_TMPDIR/cached.before")" ]
  [ -z "$(git ls-files -- fresh.ts)" ]
}

@test "the executable bit of a product file survives the stub" {
  chmod +x lib.ts
  run cal stub s1 --file lib.ts --oracle-file vac.sh -- sh vac.sh
  [ "$status" -eq 1 ]
  [ -x lib.ts ]
  printf '#!/bin/sh\n[ -x lib.ts ]\n' > x.sh
  run cal stub s2 --file lib.ts --oracle-file x.sh -- sh x.sh
  [ "$(mq s2 '.runs[-1].outcome')" = pass ]  # the stub keeps the mode, so the oracle saw an executable file
  [ -x lib.ts ]
}

@test "a hard link to a product file does not keep the stub (the file is replaced, not written through)" {
  ln lib.ts twin.ts
  run cal stub s1 --file lib.ts --oracle-file vac.sh -- sh vac.sh
  [ "$status" -eq 1 ]
  [ "$(cat lib.ts)" = "$LIB" ]
  [ "$(cat twin.ts)" = "$LIB" ]
}

@test "a failed evidence recording never passes for a caught audit, and the file is back" {
  cal stub s1 --file lib.ts --oracle-file real.sh -- sh real.sh
  chmod 555 .vetdd/evidence/s1
  run cal stub s1 --file lib.ts --oracle-file real.sh -- sh real.sh
  chmod 755 .vetdd/evidence/s1
  [ "$status" -ne 0 ]
  [[ "$output" == *"no new calibration run"* ]]
  [ "$(cat lib.ts)" = "$LIB" ]
}

@test "messages carry no control characters, whatever the file is named" {
  local name; name="$(printf 'ev\033[2Jil.txt')"
  printf 'x\n' > "$name"
  run cal stub s0 --file lib.ts --oracle-file vac.sh -- sh vac.sh  # the same call with a good file runs
  [ "$status" -eq 1 ]
  run cal stub s1 --file "$name" --oracle-file vac.sh -- sh vac.sh
  [ "$status" -eq 2 ]
  no_control "$output" || { echo "control character in: $output" | cat -v; false; }
  run cal stub s1 --file "$name.ts" --oracle-file vac.sh -- sh vac.sh
  [ "$status" -eq 2 ]
  no_control "$output"
}

@test "plant, planted, unfix, and restore still work after stub" {
  run cal stub s1 --file lib.ts --oracle-file vac.sh -- sh vac.sh
  [ "$status" -eq 1 ]
  run cal plant s2 --file lib.ts --oracle-file vac.sh
  [ "$status" -eq 0 ]
  printf 'export {};\n' > lib.ts
  run cal planted s2 --oracle-file vac.sh -- sh vac.sh
  [ "$status" -eq 1 ]
  [ "$(cat lib.ts)" = "$LIB" ]
  # planted does not accept the state a stub run left behind.
  export VETDD_TEST_HOOKS=1
  printf '#!/bin/sh\nkill -9 "$VETDD_CALIBRATE_PID"\n' > killer.sh
  cal stub s3 --file lib.ts --oracle-file vac.sh -- sh killer.sh || true
  run cal planted s3 --oracle-file vac.sh -- sh vac.sh
  [ "$status" -eq 2 ]
  run cal restore s3
  [ "$status" -eq 0 ]
  [ "$(cat lib.ts)" = "$LIB" ]
}

# --- evidence.sh --audit -------------------------------------------------------------------------

@test "evidence.sh --audit undefined-imports marks a calibration run" {
  run ev s1 calibration --audit undefined-imports --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ]
  [ "$(mq s1 '.runs[0].audit | tojson')" = '{"kind":"undefined-imports"}' ]
  [ "$(mq s1 '.runs[0].kind')" = calibration ]
}

@test "a run without --audit has no audit key" {
  ev s1 calibration -- true
  [ "$(mq s1 '.runs[0] | has("audit")')" = false ]
}

@test "--audit takes only undefined-imports, only with calibration, and is refused before the command runs" {
  run ev s0 calibration --audit undefined-imports -- true;         [ "$status" -eq 0 ]
  run ev s1 calibration --audit other -- touch ran;                [ "$status" -eq 2 ]
  run ev s1 calibration --audit -- touch ran;                      [ "$status" -eq 2 ]
  run ev s1 calibration --audit "" -- touch ran;                   [ "$status" -eq 2 ]
  run ev s1 before --audit undefined-imports -- touch ran;         [ "$status" -eq 2 ]
  run ev s1 after --audit undefined-imports -- touch ran;          [ "$status" -eq 2 ]
  run ev s1 integrated --audit undefined-imports -- touch ran;     [ "$status" -eq 2 ]
  [ ! -e ran ]
  meta_unchanged s1
}

# --- audit-note.sh -------------------------------------------------------------------------------

@test "audit-note records a not_applicable entry with kind, status, reason, and time" {
  printf 'a verify slice: the oracle drives the running app, there is no import to stub\n' > "$BATS_TEST_TMPDIR/r.txt"
  run an s1 --kind undefined-imports --not-applicable --reason-file "$BATS_TEST_TMPDIR/r.txt"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = 1 ]
  [ "$(mq s1 '.audits | length')" = 1 ]
  [ "$(mq s1 '.audits[0].kind')" = undefined-imports ]
  [ "$(mq s1 '.audits[0].status')" = not_applicable ]
  [ "$(mq s1 '.audits[0].reason')" = "a verify slice: the oracle drives the running app, there is no import to stub" ]
  [[ "$(mq s1 '.audits[0].recorded_at')" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
  # after_seq (PR7b, owner-approved): the last run number when the note was written, 0 with no run.
  [ "$(mq s1 '.audits[0] | keys | join(",")')" = "after_seq,kind,reason,recorded_at,status" ]
  [ "$(mq s1 '.audits[0].after_seq')" = 0 ]
  [ "$(mq s1 '.runs')" = "[]" ]
}

@test "audit-note keeps the runs and the version log of an existing meta.json" {
  printf 'r\n' > "$BATS_TEST_TMPDIR/r.txt"
  "$SCRIPTS/oracle-version.sh" s1 --version v1 --change initial --reason first
  ev s1 before --oracle-version v1 --oracle-file test.sh -- sh test.sh
  run an s1 --kind undefined-imports --not-applicable --reason-file "$BATS_TEST_TMPDIR/r.txt"
  [ "$status" -eq 0 ]
  [ "$(mq s1 '.runs | length')" = 1 ]
  [ "$(mq s1 '.oracle_versions | length')" = 1 ]
  ev s1 calibration -- true
  [ "$(mq s1 '.audits | length')" = 1 ]
}

@test "a second entry of the same kind is a usage error and leaves meta.json as it was" {
  printf 'r\n' > "$BATS_TEST_TMPDIR/r.txt"
  an s1 --kind undefined-imports --not-applicable --reason-file "$BATS_TEST_TMPDIR/r.txt"
  before="$(cat "$REPO/.vetdd/evidence/s1/meta.json")"
  printf 'again\n' > "$BATS_TEST_TMPDIR/r2.txt"
  run an s1 --kind undefined-imports --not-applicable --reason-file "$BATS_TEST_TMPDIR/r2.txt"
  [ "$status" -eq 2 ]
  [ "$(cat "$REPO/.vetdd/evidence/s1/meta.json")" = "$before" ]
}

@test "audit-note bad arguments are usage errors and write nothing" {
  printf 'r\n' > "$BATS_TEST_TMPDIR/r.txt"
  local R="$BATS_TEST_TMPDIR/r.txt"
  run an;                                                                              [ "$status" -eq 2 ]
  run an 'bad slice' --kind undefined-imports --not-applicable --reason-file "$R";     [ "$status" -eq 2 ]
  run an s1 --kind other --not-applicable --reason-file "$R";                          [ "$status" -eq 2 ]
  run an s1 --not-applicable --reason-file "$R";                                       [ "$status" -eq 2 ]
  run an s1 --kind undefined-imports --reason-file "$R";                               [ "$status" -eq 2 ]
  run an s1 --kind undefined-imports --not-applicable;                                 [ "$status" -eq 2 ]
  run an s1 --kind undefined-imports --not-applicable --reason inline;                 [ "$status" -eq 2 ]
  run an s1 --kind undefined-imports --not-applicable --reason-file;                   [ "$status" -eq 2 ]
  run an s1 --kind undefined-imports --not-applicable --reason-file "$R" --bogus x;    [ "$status" -eq 2 ]
  run an s1 s2 --kind undefined-imports --not-applicable --reason-file "$R";           [ "$status" -eq 2 ]
  run an s1 --kind undefined-imports --kind undefined-imports --not-applicable --reason-file "$R"; [ "$status" -eq 2 ]
  run an s1 --kind undefined-imports --not-applicable --reason-file "$R" --reason-file "$R"; [ "$status" -eq 2 ]
  meta_unchanged s1
}

@test "a text file with a control character, an empty file, a link, a directory, a big file, two lines, or a NUL is refused" {
  printf 'a\tb\n' > "$BATS_TEST_TMPDIR/tab.txt"; : > "$BATS_TEST_TMPDIR/empty.txt"
  printf 'x\n' > "$BATS_TEST_TMPDIR/real.txt"; ln -s real.txt "$BATS_TEST_TMPDIR/link.txt"
  mkdir "$BATS_TEST_TMPDIR/dir.txt"; head -c 5000 /dev/zero | tr '\0' 'a' > "$BATS_TEST_TMPDIR/big.txt"
  printf 'two\nlines\n' > "$BATS_TEST_TMPDIR/two.txt"; printf 'ab\000cd\n' > "$BATS_TEST_TMPDIR/nul.txt"
  printf 'a\033[2Jb\n' > "$BATS_TEST_TMPDIR/esc.txt"; printf 'a\302\233b\n' > "$BATS_TEST_TMPDIR/c1.txt"
  local f
  for f in tab empty link dir big two nul esc c1 nope; do
    run an s1 --kind undefined-imports --not-applicable --reason-file "$BATS_TEST_TMPDIR/$f.txt"
    [ "$status" -eq 2 ] || { echo "$f: $output"; false; }
    no_control "$output"
  done
  meta_unchanged s1
  [ ! -e .vetdd/evidence/s1 ]
}

@test "text read from a file is recorded verbatim, quotes and shell syntax included, and a Japanese reason works" {
  printf "x'; echo pwned; echo '\$(touch $BATS_TEST_TMPDIR/ran) \`id\`\n" > "$BATS_TEST_TMPDIR/r.txt"
  run an s1 --kind undefined-imports --not-applicable --reason-file "$BATS_TEST_TMPDIR/r.txt"
  [ "$status" -eq 0 ]
  [ "$(mq s1 '.audits[0].reason')" = "x'; echo pwned; echo '\$(touch $BATS_TEST_TMPDIR/ran) \`id\`" ]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
  printf 'import のない検証スライス\n' > "$BATS_TEST_TMPDIR/jp.txt"
  run an s2 --kind undefined-imports --not-applicable --reason-file "$BATS_TEST_TMPDIR/jp.txt"
  [ "$status" -eq 0 ]
  [ "$(mq s2 '.audits[0].reason')" = "import のない検証スライス" ]
}

@test "a text file named - or starting with a dash is a file, never standard input or an option" {
  printf 'from the dash file\n' > ./-
  run an s1 --kind undefined-imports --not-applicable --reason-file - < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s1 '.audits[0].reason')" = "from the dash file" ]
  printf 'from -n\n' > ./-n
  run an s2 --kind undefined-imports --not-applicable --reason-file -n < /dev/null
  [ "$status" -eq 0 ]
  [ "$(mq s2 '.audits[0].reason')" = "from -n" ]
}

@test "a link at .vetdd, .vetdd/evidence, or the slice directory is refused and nothing is made outside" {
  printf 'r\n' > "$BATS_TEST_TMPDIR/r.txt"
  mkdir -p "$BATS_TEST_TMPDIR/out"
  ln -s "$BATS_TEST_TMPDIR/out" .vetdd
  run an s1 --kind undefined-imports --not-applicable --reason-file "$BATS_TEST_TMPDIR/r.txt"
  [ "$status" -eq 2 ]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/out")" ]
  rm .vetdd; mkdir .vetdd; ln -s "$BATS_TEST_TMPDIR/out" .vetdd/evidence
  run an s1 --kind undefined-imports --not-applicable --reason-file "$BATS_TEST_TMPDIR/r.txt"
  [ "$status" -eq 2 ]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/out")" ]
  rm .vetdd/evidence; mkdir .vetdd/evidence; ln -s "$BATS_TEST_TMPDIR/out" .vetdd/evidence/s1
  run an s1 --kind undefined-imports --not-applicable --reason-file "$BATS_TEST_TMPDIR/r.txt"
  [ "$status" -eq 2 ]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/out")" ]
}

@test "a meta.json that is a link, a directory, for another slice, not JSON, or with a bad audits is refused and kept" {
  printf 'r\n' > "$BATS_TEST_TMPDIR/r.txt"
  local R="$BATS_TEST_TMPDIR/r.txt" m=.vetdd/evidence/s1/meta.json
  mkdir -p .vetdd/evidence/s1 && ln -s "$BATS_TEST_TMPDIR/real.txt" "$m"
  run an s1 --kind undefined-imports --not-applicable --reason-file "$R";  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/real.txt" ]
  rm "$m"; mkdir "$m"
  run an s1 --kind undefined-imports --not-applicable --reason-file "$R";  [ "$status" -eq 2 ]
  [[ "$output" != *"recorded"* ]]
  rmdir "$m"
  printf '{"slice_id": "other", "oracle": {"seam": null, "version": null, "files": []}, "runs": []}\n' > "$m"
  run an s1 --kind undefined-imports --not-applicable --reason-file "$R";  [ "$status" -eq 2 ]
  printf 'not json\n' > "$m"
  run an s1 --kind undefined-imports --not-applicable --reason-file "$R";  [ "$status" -eq 2 ]
  [ "$(cat "$m")" = "not json" ]
  rm "$m"; ev s1 calibration -- true
  tamper s1 '.audits = "x"'
  run an s1 --kind undefined-imports --not-applicable --reason-file "$R";  [ "$status" -eq 2 ]
  tamper s1 '.audits = ["x"]'
  run an s1 --kind undefined-imports --not-applicable --reason-file "$R";  [ "$status" -eq 2 ]
  [ "$(mq s1 '.audits | length')" = 1 ]
}

@test "a link planted at a guessable temporary name is never written through, and the name comes from mktemp" {
  printf 'r\n' > "$BATS_TEST_TMPDIR/r.txt"
  ev s1 calibration -- true
  printf 'precious\n' > "$BATS_TEST_TMPDIR/target"
  local n
  for n in 1 2 3 $$; do ln -s "$BATS_TEST_TMPDIR/target" "$REPO/.vetdd/evidence/s1/meta.json.tmp.$n"; done
  run an s1 --kind undefined-imports --not-applicable --reason-file "$BATS_TEST_TMPDIR/r.txt"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/target")" = precious ]
  [ -z "$(ls "$REPO/.vetdd/evidence/s1" | grep -E '^meta\.json\.[A-Za-z0-9]{6}$')" ]
  grep -q 'mktemp "\$dir/meta.json' "$SCRIPTS/audit-note.sh"
  run ! grep -q 'tmp\.\$\$' "$SCRIPTS/audit-note.sh"
}

@test "nothing is written, and no empty slice directory is left, when the temporary file cannot be made" {
  printf 'r\n' > "$BATS_TEST_TMPDIR/r.txt"
  mkdir -p "$BATS_TEST_TMPDIR/nomktemp"
  printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/nomktemp/mktemp"; chmod +x "$BATS_TEST_TMPDIR/nomktemp/mktemp"
  PATH="$BATS_TEST_TMPDIR/nomktemp:$PATH" run an s1 --kind undefined-imports --not-applicable --reason-file "$BATS_TEST_TMPDIR/r.txt"
  [ "$status" -eq 2 ]
  [ ! -e .vetdd/evidence/s1 ]
}

@test "audit-note keeps the meta.json permissions the umask gives" {
  printf 'r\n' > "$BATS_TEST_TMPDIR/r.txt"
  ( umask 077; an s1 --kind undefined-imports --not-applicable --reason-file "$BATS_TEST_TMPDIR/r.txt" )
  [ "$(perm .vetdd/evidence/s1/meta.json)" = 600 ]
  ( umask 022; an s2 --kind undefined-imports --not-applicable --reason-file "$BATS_TEST_TMPDIR/r.txt" )
  [ "$(perm .vetdd/evidence/s2/meta.json)" = 644 ]
}

# --- schema --------------------------------------------------------------------------------------

@test "meta.json with an audit-marked run and audits[] validates against evidence.schema.json" {
  printf 'r\n' > "$BATS_TEST_TMPDIR/r.txt"
  ev s1 calibration --audit undefined-imports --oracle-file test.sh -- sh test.sh
  an s1 --kind undefined-imports --not-applicable --reason-file "$BATS_TEST_TMPDIR/r.txt"
  run validate_schema "$REPO/.vetdd/evidence/s1/meta.json"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = valid ]
}

@test "evidence without audit or audits still validates" {
  ev s1 calibration --oracle-file test.sh -- sh test.sh
  [ "$(mq s1 'has("audits")')" = false ]
  run validate_schema "$REPO/.vetdd/evidence/s1/meta.json"
  [ "$status" -eq 0 ]
}

# A mutation note is valid since PR7a (S3b); an unknown kind is still refused, and opts in to rule 10.
@test "the schema rejects a tampered audit or audits entry" {
  printf 'r\n' > "$BATS_TEST_TMPDIR/r.txt"
  ev s1 calibration --audit undefined-imports --oracle-file test.sh -- sh test.sh
  an s1 --kind undefined-imports --not-applicable --reason-file "$BATS_TEST_TMPDIR/r.txt"
  local f
  for f in '.runs[0].audit.kind = "mutation"' '.runs[0].audit.extra = 1' '.runs[0].audit = {}' '.runs[0].audit = "undefined-imports"' \
           '.audits[0].kind = "stryker"' '.audits[0].status = "done"' '.audits[0].status = "applicable"' '.audits[0].reason = ""' \
           'del(.audits[0].reason)' 'del(.audits[0].recorded_at)' '.audits[0].recorded_at = "yesterday"' '.audits[0].extra = 1' \
           'del(.audits[0].kind)' 'del(.audits[0].status)' '.audits = {}'; do
    cp "$REPO/.vetdd/evidence/s1/meta.json" "$BATS_TEST_TMPDIR/ok.json"
    jq "$f" "$BATS_TEST_TMPDIR/ok.json" > "$BATS_TEST_TMPDIR/bad.json"
    run validate_schema "$BATS_TEST_TMPDIR/bad.json"
    [ "$status" -ne 0 ] || { echo "accepted: $f"; false; }
  done
}

# --- check-evidence rule 10 ----------------------------------------------------------------------

# audit_run <slice> <command...>: an audit-marked calibration with the oracle of record_good_slice.
audit_run() {
  local s="$1"; shift
  ev "$s" calibration --audit undefined-imports --oracle-version v1 --oracle-file test.sh -- "$@" >/dev/null 2>&1 || true
}

@test "10a fails a slice whose stubbed oracle still passed, naming the run" {
  record_good_slice s1
  audit_run s1 true
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (10a: the audit run 3 (every import stubbed with undefined) still passed, so the test observes nothing; make the test call or check the product code)"* ]]
}

@test "10b fails a slice that opted in (an audits key) and has no audit for the final oracle" {
  record_good_slice s1
  tamper s1 '.audits = []'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (10b: no undefined-imports audit for the final oracle after a green run of it; run calibrate.sh stub"* ]]
  [[ "$output" == *"audit-note.sh s1 --kind undefined-imports --not-applicable --reason-file"* ]]
  [[ "$output" != *"10a"* ]]
}

@test "10b is satisfied by a caught audit run with the final oracle" {
  record_good_slice s1
  audit_run s1 sh -c 'exit 1'
  [ "$(mq s1 '.runs[-1].audit.kind')" = undefined-imports ]
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "s1: OK" ]
}

@test "10b is satisfied by a not_applicable entry written by audit-note.sh" {
  record_good_slice s1
  printf 'the oracle drives the app; there is no import to stub\n' > "$BATS_TEST_TMPDIR/r.txt"
  an s1 --kind undefined-imports --not-applicable --reason-file "$BATS_TEST_TMPDIR/r.txt"
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "s1: OK" ]
}

@test "10b is not satisfied by an entry without a reason, with another status or kind, or by a forced audit red" {
  record_good_slice s1
  printf 'r\n' > "$BATS_TEST_TMPDIR/r.txt"
  an s1 --kind undefined-imports --not-applicable --reason-file "$BATS_TEST_TMPDIR/r.txt"
  local f
  for f in '.audits[0].reason = ""' '.audits[0].reason = 5' '.audits[0].status = "done"' '.audits[0].kind = "stryker"'; do
    cp "$REPO/.vetdd/evidence/s1/meta.json" "$BATS_TEST_TMPDIR/keep.json"
    tamper s1 "$f"
    run check s1
    [ "$status" -eq 1 ] || { echo "$f: $output"; false; }
    [[ "$output" == *"10b:"* ]]
    cp "$BATS_TEST_TMPDIR/keep.json" "$REPO/.vetdd/evidence/s1/meta.json"
  done
  # A red forced with --outcome on a command that exited 0 is not a caught audit.
  record_good_slice s2
  ev s2 calibration --audit undefined-imports --outcome target_failure --oracle-version v1 --oracle-file test.sh -- true >/dev/null 2>&1 || true
  run check s2
  [ "$status" -eq 1 ]
  [[ "$output" == *"s2: FAIL (10b:"* ]]
}

@test "10b is not satisfied by an audit of another oracle, and a different version is a different oracle" {
  record_good_slice s1
  audit_run s1 sh -c 'exit 1'
  printf '\n# a stronger test\n' >> test.sh
  ev s1 calibration --oracle-version v2 --oracle-file test.sh -- sh -c 'exit 1' >/dev/null 2>&1
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh >/dev/null 2>&1
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (10b: no undefined-imports audit for the final oracle"* ]]
  [[ "$output" != *"10a"* ]]
  ev s1 calibration --audit undefined-imports --oracle-version v2 --oracle-file test.sh -- sh -c 'exit 1' >/dev/null 2>&1
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "s1: OK" ]
}

@test "10a looks at the final oracle: a vacuous audit of a version left behind is history" {
  ev s1 before --oracle-version v1 --oracle-file test.sh -- sh test.sh >/dev/null 2>&1
  audit_run s1 true
  printf '\n# the test now checks the product\n' >> test.sh
  ev s1 calibration --oracle-version v2 --oracle-file test.sh -- sh -c 'exit 1' >/dev/null 2>&1
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh >/dev/null 2>&1
  ev s1 calibration --audit undefined-imports --oracle-version v2 --oracle-file test.sh -- sh -c 'exit 1' >/dev/null 2>&1
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "s1: OK" ]
}

@test "10b does not ask old evidence, or a slice that never opted in" {
  record_good_slice s1
  [ "$(mq s1 'has("audits")')" = false ]
  [ "$(mq s1 '[.runs[] | has("audit")] | any')" = false ]
  run check s1
  [ "$status" -eq 0 ]
  [ "$output" = "s1: OK" ]
  # A slice with a version log and a test report, as recorded before the audit existed, is exempt too.
  record_good_slice s2
  "$SCRIPTS/oracle-version.sh" s2 --version v1 --change initial --reason first
  run check s2
  [ "$output" = "s2: OK" ]
}

@test "10b asks a slice that has an audit-marked run even without an audits key" {
  record_good_slice s1
  audit_run s1 sh -c 'exit 1'
  [ "$(mq s1 'has("audits")')" = false ]
  printf '\n# edit\n' >> test.sh
  ev s1 calibration --oracle-version v2 --oracle-file test.sh -- sh -c 'exit 1' >/dev/null 2>&1
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh >/dev/null 2>&1
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"10b:"* ]]
}

@test "rule 10 still runs when rule 6 returns early" {
  record_good_slice s1
  audit_run s1 true
  tamper s1 '.oracle.files[0].path = "/etc/passwd"'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"6: oracle.files holds an entry that is not a repo-relative path"* ]]
  [[ "$output" == *"10a:"* ]]
  [[ "$output" == *"10b:"* ]]
}

@test "rule 10 fails closed: a malformed audit record is a problem, never OK" {
  record_good_slice s1
  audit_run s1 sh -c 'exit 1'
  tamper s1 '.runs[2].audit = "undefined-imports"'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"10: could not evaluate"* ]]
  record_good_slice s2
  tamper s2 '.audits = "x"'
  run check s2
  [ "$status" -eq 1 ]
  [[ "$output" == *"s2: FAIL (10: audits is not an array"* ]]
  record_good_slice s3
  audit_run s3 true
  tamper s3 '.runs[2].seq = "3\u001b[2J"'
  run check s3
  [ "$status" -eq 1 ]
  no_control "$output" || { echo "$output" | cat -v; false; }
}

@test "an audit run is not a red: it cannot stand in for the before run (rules 1 and 8)" {
  # A stubbed product is not a defect: the red of a slice has to come from the real one.
  printf '42\n' > value.txt
  ev s1 calibration --audit undefined-imports --oracle-version v1 --oracle-file test.sh -- sh -c 'exit 1' >/dev/null 2>&1
  ev s1 after -- sh test.sh >/dev/null 2>&1
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (1: no red run"* ]]
  [[ "$output" == *"8: no red run with the oracle of the final green run"* ]]
  [[ "$output" != *"forced with --outcome"* ]]
}

@test "an audit run does not hide the latest run of a command from rule 9b" {
  FIX="$BATS_TEST_DIRNAME/fixtures/reports"
  printf 'mkdir -p .vetdd/reports\n[ -z "${REPORT:-}" ] || cp "$REPORT" .vetdd/reports/r.json\nexit "${EXIT:-0}"\n' > runner.sh
  local T1="closingDate closes on the 20th of the same month when invoiced before the cutoff"
  jq --arg n "$T1" '(.testResults[].assertionResults[] | select(.fullName == $n) | .status) = "skipped"' \
    "$FIX/vitest5-pass.json" > "$BATS_TEST_TMPDIR/skip.json"
  REPORT="$FIX/vitest5-pass.json" EXIT=1 ev s1 before --oracle-version v1 --oracle-file test.sh --test-report jest-json:.vetdd/reports/r.json -- sh runner.sh >/dev/null 2>&1 || true
  REPORT="$BATS_TEST_TMPDIR/skip.json" EXIT=0 ev s1 after --oracle-version v1 --oracle-file test.sh --test-report jest-json:.vetdd/reports/r.json -- sh runner.sh >/dev/null 2>&1
  EXIT=1 ev s1 calibration --oracle-version v1 --oracle-file test.sh -- sh runner.sh >/dev/null 2>&1 || true
  tamper s1 '.runs[2].audit = {"kind": "undefined-imports"}'
  run check s1
  [[ "$output" == *"9b: test \"$T1\""* ]]
}

# --- docs ----------------------------------------------------------------------------------------

@test "the rubric is version 5 or later and names rule 10, and the test mode says to run calibrate.sh stub" {
  head -1 "$SCRIPTS/../references/final-judge-rubric.md" | grep -qxE '# Final judge rubric \(version ([5-9]|[1-9][0-9]+)\)'
  grep -q '10a' "$SCRIPTS/../references/final-judge-rubric.md"
  grep -q '10b' "$SCRIPTS/../references/final-judge-rubric.md"
  # The content test stays (round 1, N2): the rubric names the undefined-imports case itself.
  grep -q 'every import returned' "$SCRIPTS/../references/final-judge-rubric.md"
  grep -q 'calibrate.sh" stub' "$SCRIPTS/../modes/test.md"
  grep -q 'audit-note.sh' "$SCRIPTS/../modes/test.md"
  grep -q 'audit-note.sh' "$SCRIPTS/../modes/verify.md"
}

# --- real vitest ---------------------------------------------------------------------------------

@test "integration: real vitest 5 in a ts-kata copy, through calibrate.sh stub" {
  local kata="$VETDD_ROOT/fixtures/ts-kata"
  [ -x "$kata/node_modules/.bin/vitest" ] || skip "fixtures/ts-kata/node_modules is missing"
  local K="$BATS_TEST_TMPDIR/kata"
  mkdir -p "$K" && cp -R "$kata/package.json" "$kata/tsconfig.json" "$kata/src" "$K/"
  ln -s "$kata/node_modules" "$K/node_modules"
  printf 'export function f(n: number): number { return n * 2; }\n' > "$K/src/x.ts"
  printf 'import { expect, it } from "vitest";\nimport { f } from "./x.js";\nit("vacuous", () => { expect(true).toBe(true); });\n' > "$K/src/vac.test.ts"
  printf 'import { expect, it } from "vitest";\nimport { f } from "./x.js";\nit("real", () => { expect(f(2)).toBe(4); });\n' > "$K/src/real.test.ts"
  cd "$K" && git init -q && printf 'node_modules\n' > .gitignore && git add -A && git commit -q -m init
  run "$SCRIPTS/calibrate.sh" stub k1 --file src/x.ts --oracle-file src/vac.test.ts -- ./node_modules/.bin/vitest run src/vac.test.ts
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(jq -r '.runs[-1].outcome' .vetdd/evidence/k1/meta.json)" = pass ]
  [ "$(jq -r '.runs[-1].audit.kind' .vetdd/evidence/k1/meta.json)" = undefined-imports ]
  run "$SCRIPTS/calibrate.sh" stub k2 --file src/x.ts --oracle-file src/real.test.ts -- ./node_modules/.bin/vitest run src/real.test.ts
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -r '.runs[-1].outcome' .vetdd/evidence/k2/meta.json)" = target_failure ]
  grep -q 'TypeError' .vetdd/evidence/k2/runs/001-calibration.log
  [ "$(cat src/x.ts)" = 'export function f(n: number): number { return n * 2; }' ]
  [ -z "$(git status --porcelain --untracked-files=all | grep -v '^?? .vetdd/')" ]
}

@test "an audit run's report never replaces the latest report in rule 9b (N4)" {
  printf 'mkdir -p .vetdd/reports\n[ -z "${REPORT:-}" ] || cp "$REPORT" .vetdd/reports/r.json\nexit "${EXIT:-0}"\n' > runner.sh
  FIX="$BATS_TEST_DIRNAME/fixtures/reports"; PASS="$FIX/vitest5-pass.json"
  T1="closingDate closes on the 20th of the same month when invoiced before the cutoff"
  jq --arg n "$T1" '(.testResults[].assertionResults[] | select(.fullName == $n) | .status) = "skipped"' "$PASS" > "$BATS_TEST_TMPDIR/skip.json"
  R=.vetdd/reports/r.json
  REPORT="$PASS" EXIT=1 ev s1 before --oracle-version v1 --oracle-file test.sh --test-report "jest-json:$R" -- sh runner.sh >/dev/null 2>&1 || true
  REPORT="$BATS_TEST_TMPDIR/skip.json" EXIT=0 ev s1 after --oracle-version v1 --oracle-file test.sh --test-report "jest-json:$R" -- sh runner.sh >/dev/null 2>&1 || true
  run check s1
  [[ "$output" == *"9b: "* ]]
  # An audit run with its own report, recorded afterwards, must not make the 9b error go away.
  REPORT="$PASS" EXIT=1 ev s1 calibration --audit undefined-imports --oracle-version v1 --oracle-file test.sh --test-report "jest-json:$R" -- sh runner.sh >/dev/null 2>&1 || true
  run check s1
  [[ "$output" == *"9b: "* ]] || { echo "$output"; false; }
}

@test "the judge rubric keeps the content test for undefined imports and leaves audit runs out of criterion 1 (N2)" {
  local rub="$BATS_TEST_DIRNAME/../skills/vetdd/references/final-judge-rubric.md"
  sed -n '/^## 3\. /,/^## 4\. /p' "$rub" | grep -q 'would still pass if every import returned `undefined`'
  sed -n '/^## 1\. /,/^## 2\. /p' "$rub" | grep -q '`audit`'
}

# --- round 2 ---------------------------------------------------------------------------------------

@test "a read-only product file is stubbed and comes back read-only with its content" {
  chmod 444 lib.ts
  run cal stub ro1 --file lib.ts --oracle-file spy.sh -- sh spy.sh lib.ts
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(cat seen.out)" = 'export {};' ]
  [ "$(cat lib.ts)" = "$LIB" ]
  [ "$(perm lib.ts)" = 444 ]
  [ ! -e "$(state_dir ro1)" ]
  chmod 644 lib.ts
}

@test "restoring a python file drops the bytecode cache the stub run left" {
  mkdir -p __pycache__
  printf 'stale' > __pycache__/mod.cpython-399.pyc
  printf 'keep' > __pycache__/other.cpython-399.pyc
  run cal stub py1 --file mod.py --oracle-file spy.sh -- sh spy.sh mod.py
  [ "$status" -eq 1 ]
  [ ! -e __pycache__/mod.cpython-399.pyc ]
  [ -e __pycache__/other.cpython-399.pyc ]
  [ "$(cat mod.py)" = "$(printf 'def f(n):\n    return n * 2')" ]
}

@test "test mode sends a vacuous audit through unfix and a new after, not a before on the fixed tree" {
  local doc="$SCRIPTS/../modes/test.md"
  # The step-5 sentence about a vacuous test must name the order that gives a red on the new version.
  grep -q 'oracle-version.sh.*calibrate.sh unfix' "$doc"
  ! grep -q 'record its `before` again, and audit again' "$doc" || false
}

# --- round 3 ---------------------------------------------------------------------------------------

@test "a symlinked __pycache__ is left alone: the pyc files it points at survive a python stub run" {
  mkdir outside_cache
  printf 'keep' > outside_cache/mod.cpython-399.pyc
  ln -s "$PWD/outside_cache" __pycache__
  git add -A && git commit -q -m link
  run cal stub py2 --file mod.py --oracle-file spy.sh -- sh spy.sh mod.py
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ -e outside_cache/mod.cpython-399.pyc ]
  [ "$(cat mod.py)" = "$(printf 'def f(n):\n    return n * 2')" ]
}

@test "an audit run that asked for a report does not make 9c warn about the real green (round 3)" {
  printf 'mkdir -p .vetdd/reports\n[ -z "${REPORT:-}" ] || cp "$REPORT" .vetdd/reports/r.json\nexit "${EXIT:-0}"\n' > runner.sh
  printf 'echo t\n' > test.sh
  FIX="$BATS_TEST_DIRNAME/fixtures/reports"; PASS="$FIX/vitest5-pass.json"; R=.vetdd/reports/r.json
  # The same command throughout, so the audit run and the real green fall in one group.
  EXIT=1 ev s1 before --oracle-version v1 --oracle-file test.sh -- sh runner.sh >/dev/null 2>&1 || true
  EXIT=0 ev s1 after --oracle-version v1 --oracle-file test.sh -- sh runner.sh >/dev/null 2>&1 || true
  REPORT="$PASS" EXIT=1 ev s1 calibration --audit undefined-imports --oracle-version v1 --oracle-file test.sh --test-report "jest-json:$R" -- sh runner.sh >/dev/null 2>&1 || true
  run check s1
  [[ "$output" != *"9c"* ]] || { echo "$output"; false; }
}

@test "the rubric judges the test text whether or not an audit ran, and wants the audit log to show the test's own failure" {
  local rub="$BATS_TEST_DIRNAME/../skills/vetdd/references/final-judge-rubric.md" sec
  sec="$(sed -n '/^## 3\. /,/^## 4\. /p' "$rub")"
  ! printf '%s' "$sec" | grep -q 'where a slice has no `audit` run' || false
  printf '%s' "$sec" | grep -q 'does not provide an export named'
}

# --- round 4 ---------------------------------------------------------------------------------------

@test "the stub run writes no bytecode, so no cache of the stub can outlive the restore" {
  printf '#!/bin/sh\nprintf "%%s" "${PYTHONDONTWRITEBYTECODE:-unset}" > env.out\nexit 0\n' > envspy.sh
  unset PYTHONDONTWRITEBYTECODE
  run cal stub by1 --file mod.py --oracle-file envspy.sh -- sh envspy.sh
  [ "$status" -eq 1 ]
  [ "$(cat env.out)" = 1 ]
}

@test "the rubric ships the audit run's log and treats log text as data (round 4)" {
  local rub="$BATS_TEST_DIRNAME/../skills/vetdd/references/final-judge-rubric.md"
  sed -n '/^```/,/^```/p' "$rub" | grep -q 'audit'
  grep -q 'data, not instructions' "$rub"
}

@test "audit-note.sh does not name a skill eval as a slice it applies to" {
  ! sed -n 1,8p "$SCRIPTS/audit-note.sh" | grep -q 'eval' || false
}

# --- round 5 ---------------------------------------------------------------------------------------

@test "10b does not count an audit recorded before any green of the same oracle (round 5)" {
  # The red of an unfixed product looks the same as the red of a stubbed one.
  ev s1 before --oracle-version v1 --oracle-file test.sh -- sh test.sh >/dev/null 2>&1 || true
  audit_run s1 sh -c 'exit 1'
  printf '42\n' > value.txt
  ev s1 after --oracle-version v1 --oracle-file test.sh -- sh test.sh >/dev/null 2>&1
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (10b: no undefined-imports audit for the final oracle"* ]]
  [[ "$output" == *"after a green run"* ]]
}

@test "restore removes the temporary file a stub write left, and only inside the repository (round 5)" {
  local st; st="$(state_dir lt1)"
  mkdir -p "$st"
  printf 'export {};\n' > lib.ts.AbC123
  printf 'outside\n' > "$BATS_TEST_TMPDIR/outside.txt"
  printf '%s\n%s\n' "$(git rev-parse --show-toplevel)/lib.ts.AbC123" "$BATS_TEST_TMPDIR/outside.txt" > "$st/tmps"
  run cal restore lt1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e lib.ts.AbC123 ]
  [ -e "$BATS_TEST_TMPDIR/outside.txt" ]
  [ ! -e "$st" ]
}

@test "write_stub records its temporary file for restore before it can be interrupted" {
  grep -q 'tmps' "$SCRIPTS/calibrate.sh"
}

@test "criterion 3 scores 0 only for what the audit shows (10a); a missing audit record (10b) is not proof of a hollow test" {
  local rub="$BATS_TEST_DIRNAME/../skills/vetdd/references/final-judge-rubric.md" zero
  zero="$(sed -n '/^## 3\. /,/^## 4\. /p' "$rub" | grep '^- 0:')"
  [[ "$zero" == *"10a"* ]]
  [[ "$zero" != *"10b"* ]]
}

@test "a .ts file in a package that says commonjs gets the CommonJS stub (round 5)" {
  printf '{"type": "commonjs"}\n' > package.json
  printf 'export const g = 1;\n' > cj.ts
  git add -A && git commit -q -m cjts
  run cal stub ct1 --file cj.ts --oracle-file spy.sh -- sh spy.sh cj.ts
  [ "$(cat seen.out)" = 'if (typeof module !== "undefined") { module.exports = {}; }' ] || { echo "ts: $(cat seen.out)"; false; }
  [ "$(cat cj.ts)" = 'export const g = 1;' ]
}

@test "the python stub run reads and writes bytecode only in an empty cache directory of its own (round 5)" {
  printf '#!/bin/sh\nprintf "%%s" "${PYTHONPYCACHEPREFIX:-unset}" > env.out\nls -A "$PYTHONPYCACHEPREFIX" | wc -l | tr -d " " > env.count\nexit 0\n' > envspy.sh
  unset PYTHONPYCACHEPREFIX
  run cal stub pp1 --file mod.py --oracle-file envspy.sh -- sh envspy.sh
  [ "$status" -eq 1 ]
  [ "$(cat env.count)" = 0 ]
  case "$(cat env.out)" in "$(cd "$(git rev-parse --git-dir)" && pwd -P)"/*) ;; *) echo "prefix: $(cat env.out)"; false ;; esac
  [ ! -e "$(cat env.out)" ]
}

# --- round 6 ---------------------------------------------------------------------------------------

@test "a not_applicable note recorded before the final oracle's first run does not satisfy 10b (round 6)" {
  record_good_slice s1
  printf 'r\n' > "$BATS_TEST_TMPDIR/r.txt"
  an s1 --kind undefined-imports --not-applicable --reason-file "$BATS_TEST_TMPDIR/r.txt"
  run check s1
  [ "$output" = "s1: OK" ]
  # Written before the final oracle first ran: by run number (after_seq 0 is before run 1), and by
  # time for a note without after_seq.
  tamper s1 '.audits[0].after_seq = 0'
  run check s1
  [[ "$output" == *"s1: FAIL (10b:"* ]]
  tamper s1 '.audits[0] |= del(.after_seq) | .audits[0].recorded_at = "2000-01-01T00:00:00Z"'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (10b:"* ]]
}

@test "a note written for version 1 stops counting once version 2 has run (round 6)" {
  record_good_slice s1
  printf 'r\n' > "$BATS_TEST_TMPDIR/r.txt"
  an s1 --kind undefined-imports --not-applicable --reason-file "$BATS_TEST_TMPDIR/r.txt"
  sleep 1
  printf '\n# the test now checks the product\n' >> test.sh
  ev s1 calibration --oracle-version v2 --oracle-file test.sh -- sh -c 'exit 1' >/dev/null 2>&1
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh >/dev/null 2>&1
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"10b:"* ]]
}

@test "a note is not counted when no run of the final oracle has a start time (fail closed)" {
  record_good_slice s1
  printf 'r\n' > "$BATS_TEST_TMPDIR/r.txt"
  an s1 --kind undefined-imports --not-applicable --reason-file "$BATS_TEST_TMPDIR/r.txt"
  tamper s1 '.runs |= map(del(.started_at)) | .audits[0] |= del(.after_seq)'
  run check s1
  [[ "$output" == *"10b:"* ]]
}

@test "the rubric scores a missing audit record at 1 and lists the CommonJS load errors (round 6)" {
  local rub="$BATS_TEST_DIRNAME/../skills/vetdd/references/final-judge-rubric.md" sec one
  sec="$(sed -n '/^## 3\. /,/^## 4\. /p' "$rub")"
  one="$(printf '%s\n' "$sec" | grep '^- 1:')"
  [[ "$one" == *"audit record"* ]]
  [[ "$sec" == *"TS2580"* ]]
  [[ "$sec" == *"module is not defined"* ]]
}
