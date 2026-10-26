#!/usr/bin/env bats
# mutate-ranges.sh (#62 items 3 and 4): the value for Stryker's --mutate, the lines a slice added or
# changed in current line numbers, by git blame over throwaway commits of the slice's first before
# tree, its last passing after tree, and the working tree.

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  make_repo
  mkdir -p src
  printf '%s\n' a1 a2 a3 a4 a5 > src/a.js
  git add -A && git commit -q -m product
}

mr() { "$SCRIPTS/mutate-ranges.sh" "$@"; }
# A red run (exit 1 is target_failure) and a green run of the slice, test.sh its oracle file.
red() { ev "$1" before --seam unit --oracle-version v1 --oracle-file test.sh -- false >/dev/null 2>&1; }
green() { ev "$1" after -- true >/dev/null 2>&1; }
cal() { "$SCRIPTS/calibrate.sh" "$@" >/dev/null 2>&1; }

# --- 1. one slice -------------------------------------------------------------------------------

@test "one slice: prints file:a-b over the lines it added or changed, in current numbers" {
  red s1
  printf '%s\n' a1 a2 B3 B4 b4x a5 > src/a.js
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:3-5" ]
}

@test "the first passing after of a version ends it: a rejected after before it, later afters of the version, and later edits do not" {
  red s1
  printf '%s\n' a1 X2 a3 a4 a5 > src/a.js
  ev s1 after -- false >/dev/null 2>&1 || true
  printf '%s\n' a1 X2 X3 a4 a5 > src/a.js
  green s1
  printf '%s\n' a1 X2 X3 X4 a5 > src/a.js
  green s1
  printf '%s\n' a1 X2 X3 X4 X5 > src/a.js
  ev s1 after -- false >/dev/null 2>&1 || true
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:2-3" ]
}

@test "a version bump after a later slice: the lines between versions are not the slice's, its own change in the new version is" {
  red s1
  printf '%s\n' a1 X2 a3 a4 a5 > src/a.js
  green s1
  red s2
  printf '%s\n' a1 X2 a3 X4 a5 > src/a.js
  green s2
  # s1's test is strengthened: v2's red, then its green on the tree that holds s2's line.
  printf 'echo stronger\n' >> test.sh
  ev s1 calibration --oracle-version v2 -- false >/dev/null 2>&1
  run --separate-stderr mr s1
  [ "$output" = "src/a.js:2-2" ] || { echo "before v2 is green: $output $stderr"; false; }
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:2-2" ]
  # v3: s1 changes a line of its own between v3's red and green.
  ev s1 calibration --oracle-version v3 -- false >/dev/null 2>&1
  printf '%s\n' a1 X2 a3 X4 Y5 > src/a.js
  green s1
  run --separate-stderr mr s1
  [ "$output" = "src/a.js:2-2,src/a.js:5-5" ] || { echo "$output $stderr"; false; }
  run --separate-stderr mr s2
  [ "$output" = "src/a.js:4-4" ]
}

@test "a slice without a before (a refactor, red planted): its first passing after to its last" {
  cal plant s1-refactor --file src/a.js --oracle-file test.sh
  printf '%s\n' a1 a2 a3 a4 BAD > src/a.js
  cal planted s1-refactor --oracle-file test.sh -- false
  [ "$(cat src/a.js | tail -n 1)" = a5 ]
  green s1-refactor
  printf '%s\n' a1 a2 R3 a4 a5 > src/a.js
  green s1-refactor
  run --separate-stderr mr s1-refactor
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:3-3" ]
}

@test "a slice with no before and no red: taken as a refactor, and stderr says so" {
  green s1
  printf '%s\n' a1 a2 R3 a4 a5 > src/a.js
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:3-3" ]
  [[ "$stderr" == *"refactor"* ]] || { echo "$stderr"; false; }
}

@test "a slice whose red is an unfix calibration (no before): the fix is its change, whatever afters follow" {
  printf '%s\n' a1 F2 a3 a4 a5 > src/a.js
  cal unfix s1 --file src/a.js --oracle-version v1 --oracle-file test.sh -- false
  [ "$(sed -n 2p src/a.js)" = F2 ]
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "one after: $output $stderr"; false; }
  [ "$output" = "src/a.js:2-2" ]
  # A coverage oracle recorded as after on the same tree, then a later slice, then Close's after again.
  green s1
  red s2
  printf '%s\n' a1 F2 a3 G4 a5 > src/a.js
  green s2
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:2-2" ]
}

@test "an after on the fixed tree, then an unfix red, then an after (the surface-slice order): the fix is the slice's change, not a refactor (#82 item 2)" {
  printf '%s\n' a1 F2 a3 a4 a5 > src/a.js
  ev s1 after --seam unit --oracle-version v1 --oracle-file test.sh -- true >/dev/null 2>&1
  cal unfix s1 --file src/a.js --oracle-version v1 --oracle-file test.sh -- false
  [ "$(mq s1 '[.runs[].kind] | join(" ")')" = "after calibration" ] || { cat .vetdd/evidence/s1/meta.json; false; }
  [ "$(sed -n 2p src/a.js)" = F2 ]
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$status $output $stderr"; false; }
  [ "$output" = "src/a.js:2-2" ]
  [[ "$stderr" != *"refactor"* ]] || { echo "$stderr"; false; }
  # Another after on the same tree (Close's coverage oracle) moves nothing.
  green s1
  run --separate-stderr mr s1
  [ "$output" = "src/a.js:2-2" ] || { echo "$status $output $stderr"; false; }
}

@test "an unfix-shaped red whose HEAD moved before the after that follows it is not an unfix: taken as a refactor (verify mode, A.4's red reused; review r1)" {
  # A.4: the calibration red and pass on a clean tree.
  ev s1-verify calibration --oracle-version 1 --oracle-file test.sh --infra-exit 2 -- false >/dev/null 2>&1
  ev s1-verify calibration -- true >/dev/null 2>&1
  # Another change is committed before B; its lines hold HEAD's content in no red tree.
  printf '%s\n' a1 C2 a3 a4 a5 > src/a.js
  git commit -q -am other
  # B.1: the pre-change green, then the change, then the green.
  green s1-verify
  printf '%s\n' a1 C2 a3 a4 X5 > src/a.js
  green s1-verify
  run --separate-stderr mr s1-verify
  [ "$status" -eq 0 ] || { echo "$status $output $stderr"; false; }
  [ "$output" = "src/a.js:5-5" ]
  [[ "$stderr" == *"HEAD moved"*"refactor"* ]] || { echo "$stderr"; false; }
}

@test "verify mode: A.4's red, an untracked Stryker config, B.1's red of the new version and its pre-change green, the change, a green: the change is the slice's (review r2)" {
  # A.4 on a clean tree.
  ev s1-verify calibration --oracle-version 1 --oracle-file test.sh --infra-exit 2 -- false >/dev/null 2>&1
  ev s1-verify calibration -- true >/dev/null 2>&1
  # The wrapper (an oracle file) and the Stryker config, committed before B.1 as verify.md says: a
  # new oracle version. HEAD moved since A.4, so A.4's red is not an unfix of them.
  printf 'exit 0\n' > wrap.sh
  printf '%s\n' 'export default { testRunner: "command" };' > stryker.config.mjs
  git add wrap.sh stryker.config.mjs && git commit -q -m 'verify wrapper and Stryker config'
  ev s1-verify calibration --oracle-version 2 --oracle-file test.sh --oracle-file wrap.sh --infra-exit 2 -- false >/dev/null 2>&1
  green s1-verify
  printf '%s\n' a1 a2 a3 X4 a5 > src/a.js
  green s1-verify
  run --separate-stderr mr s1-verify
  [ "$status" -eq 0 ] || { echo "$status $output $stderr"; false; }
  [ "$output" = "src/a.js:4-4" ]
}

@test "the start is the first red that a passing after follows: an unfix red of a later version after an earlier one" {
  printf '%s\n' a1 F2 a3 a4 a5 > src/a.js
  cal unfix s1 --file src/a.js --oracle-version v1 --oracle-file test.sh -- false
  printf '%s\n' a1 F2 F3 a4 a5 > src/a.js
  printf 'echo stronger\n' >> test.sh
  cal unfix s1 --file src/a.js --oracle-version v2 --oracle-file test.sh -- false
  [ "$(mq s1 '[.runs[] | .kind + ":" + .outcome] | join(" ")')" = "calibration:target_failure calibration:target_failure" ] || { cat .vetdd/evidence/s1/meta.json; false; }
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$status $output $stderr"; false; }
  [ "$output" = "src/a.js:2-3" ]
}

@test "a v1 unfix red, then a v2 red planted before the first green, then an after: the start stays the unfix red (review r3, Codex P2)" {
  printf '%s\n' a1 F2 a3 a4 a5 > src/a.js
  cal unfix s1 --file src/a.js --oracle-version v1 --oracle-file test.sh -- false
  printf 'echo stronger\n' >> test.sh
  cal plant s1 --file src/a.js --oracle-version v2 --oracle-file test.sh
  printf '%s\n' a1 F2 a3 BAD a5 > src/a.js
  cal planted s1 --oracle-file test.sh -- false
  [ "$(sed -n 4p src/a.js)" = a4 ]
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$status $output $stderr"; false; }
  [ "$output" = "src/a.js:2-2" ]
  # Close's green again on the same tree moves nothing.
  green s1
  run --separate-stderr mr s1
  [ "$output" = "src/a.js:2-2" ] || { echo "$status $output $stderr"; false; }
}

@test "an after before the red that differs from the after after it: stderr names what is not counted (review r3)" {
  printf '%s\n' b1 > src/b.js && git add -A && git commit -q -m b
  ev s1 after --seam unit --oracle-version v1 --oracle-file test.sh -- true >/dev/null 2>&1
  printf '%s\n' a1 F2 a3 a4 a5 > src/a.js
  printf '%s\n' b1 B2 > src/b.js
  cal unfix s1 --file src/a.js --oracle-version v1 --oracle-file test.sh -- false
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$status $output $stderr"; false; }
  [ "$output" = "src/a.js:2-2" ]
  [[ "$stderr" == *"src/b.js"*"not counted"* ]] || { echo "$stderr"; false; }
  # The fix the red took out is counted, so it is not named (review r4).
  [[ "$stderr" != *"src/a.js"* ]] || { echo "$stderr"; false; }
  # The surface order on the fixed tree says nothing.
  rm -rf .vetdd
  ev s2 after --seam unit --oracle-version v1 --oracle-file test.sh -- true >/dev/null 2>&1
  cal unfix s2 --file src/a.js --file src/b.js --oracle-version v1 --oracle-file test.sh -- false
  green s2
  run --separate-stderr mr s2
  [ "$output" = "src/a.js:2-2,src/b.js:2-2" ] || { echo "$status $output $stderr"; false; }
  [[ "$stderr" != *"not counted"* ]] || { echo "$stderr"; false; }
}

@test "a v1 unfix red, then a plain v2 red on the fixed tree, then an after: the start stays the unfix red (review r5, Codex P2)" {
  printf '%s\n' a1 F2 a3 a4 a5 > src/a.js
  cal unfix s1 --file src/a.js --oracle-version v1 --oracle-file test.sh -- false
  printf 'echo stronger\n' >> test.sh
  ev s1 calibration --oracle-version v2 -- false >/dev/null 2>&1
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$status $output $stderr"; false; }
  [ "$output" = "src/a.js:2-2" ]
  green s1
  run --separate-stderr mr s1
  [ "$output" = "src/a.js:2-2" ] || { echo "$status $output $stderr"; false; }
}

@test "unfix reds of two versions before the first green: the lines of both count (review r4, Codex P2)" {
  printf '%s\n' b1 > src/b.js && git add -A && git commit -q -m b
  printf '%s\n' a1 F2 a3 a4 a5 > src/a.js
  cal unfix s1 --file src/a.js --oracle-version v1 --oracle-file test.sh -- false
  printf '%s\n' b1 G2 > src/b.js
  printf 'echo stronger\n' >> test.sh
  cal unfix s1 --file src/b.js --oracle-version v2 --oracle-file test.sh -- false
  [ "$(sed -n 2p src/b.js)" = G2 ]
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$status $output $stderr"; false; }
  [ "$output" = "src/a.js:2-2,src/b.js:2-2" ]
}

@test "a red after the first after with no passing after following it yet: not a start, so the slice cannot be attributed (exit 2)" {
  printf '%s\n' a1 F2 a3 a4 a5 > src/a.js
  ev s1 after --seam unit --oracle-version v1 --oracle-file test.sh -- true >/dev/null 2>&1
  cal unfix s1 --file src/a.js --oracle-version v1 --oracle-file test.sh -- false
  run --separate-stderr mr s1
  [ "$status" -eq 2 ] || { echo "$status $output $stderr"; false; }
  [ -z "$output" ]
}

@test "a before that passed (rejected) does not start the slice; the unfix red after it does" {
  printf '%s\n' a1 F2 a3 a4 a5 > src/a.js
  ev s1 before --oracle-version v1 --oracle-file test.sh -- true >/dev/null 2>&1 || true
  [ "$(mq s1 '.runs[0].accepted')" = false ]
  cal unfix s1 --file src/a.js --oracle-version v1 --oracle-file test.sh -- false
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:2-2" ]
}

@test "a version bumped before the first green: the product lines written under the earlier version count" {
  red s1
  printf '%s\n' a1 P2 a3 a4 a5 > src/a.js
  printf 'echo stronger\n' >> test.sh
  ev s1 calibration --oracle-version v2 -- false >/dev/null 2>&1
  printf '%s\n' a1 P2 P3 a4 a5 > src/a.js
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:2-3" ]
}

@test "a change of whitespace inside a literal is the slice's" {
  printf '%s\n' 'const greeting = "hello world";' 'const other = 1;' > src/w.js
  git add -A && git commit -q -m w
  red s1
  printf '%s\n' 'const greeting = "helloworld";' 'const other = 1;' > src/w.js
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/w.js:1-1" ]
}

@test "a line the slice copied from existing code is the slice's" {
  printf '%s\n' 'function a(input) {' '  if (input === undefined) throw new Error("input is required here");' '  return input;' '}' 'function b(input) {' '  return input * 2;' '}' > src/c.js
  git add -A && git commit -q -m c
  red s1
  printf '%s\n' 'function a(input) {' '  if (input === undefined) throw new Error("input is required here");' '  return input;' '}' 'function b(input) {' '  if (input === undefined) throw new Error("input is required here");' '  return input * 2;' '}' > src/c.js
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/c.js:6-6" ]
}

@test "a short line a later edit moved is still the slice's" {
  red s1
  printf '%s\n' a1 a2 'const EXIT_USAGE = 2;' a3 a4 a5 > src/a.js
  green s1
  printf '%s\n' 'const EXIT_USAGE = 2;' a1 a2 a3 a4 a5 > src/a.js
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:1-1" ]
}

@test "a later version starts at its red: a passing calibration before it does not" {
  red s1
  printf '%s\n' a1 X2 a3 a4 a5 > src/a.js
  green s1
  ev s1 calibration --oracle-version v2 -- true >/dev/null 2>&1
  red s2
  printf '%s\n' a1 X2 a3 X4 a5 > src/a.js
  green s2
  ev s1 calibration --oracle-version v2 -- false >/dev/null 2>&1
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:2-2" ]
}

@test "a red calibration that is not an unfix: the slice is taken as a refactor, and stderr says why" {
  printf '%s\n' a1 F2 a3 a4 a5 > src/a.js
  printf '%s\n' z1 > src/z.js
  # The fix is in a.js and z.js; unfix names only a.js, so z.js keeps its uncommitted change.
  cal unfix s1 --file src/a.js --oracle-version v1 --oracle-file test.sh -- false
  printf '%s\n' z1 z2 > src/z.js
  green s1
  green s1
  run --separate-stderr mr s1
  [[ "$stderr" == *"src/z.js"*"HEAD"* ]] || { echo "$stderr"; false; }
  [[ "$stderr" == *"refactor"* ]] || { echo "$stderr"; false; }
}

@test "a source file whose name git quotes is named on stderr, not dropped silently" {
  printf '%s\n' a1 > 'src/q"x.js' && git add -A && git commit -q -m q
  red s1
  printf '%s\n' a1 'const valueTheSliceAdded = computeSomething(1);' > 'src/q"x.js'
  green s1
  printf '%s\n' a1 > 'src/q"x.js'
  printf '%s\n' 'const valueTheSliceAdded = computeSomething(1);' > src/moved.js
  run --separate-stderr mr s1 --file src/moved.js
  [[ "$stderr" == *'q"x.js'* || "$stderr" == *'q\"x.js'* ]] || { echo "$status $output $stderr"; false; }
}

@test "another slice reindents the slice's lines between two of its versions: they stay the slice's (PR #78, Codex)" {
  printf '%s\n' 'function f() {' '  return "the original value";' '}' > src/f.js
  git add -A && git commit -q -m f
  red s1
  printf '%s\n' 'function f() {' '  return "the value the slice computed";' '}' > src/f.js
  green s1
  run --separate-stderr mr s1
  [ "$output" = "src/f.js:2-2" ] || { echo "after v1: $output $stderr"; false; }
  red s2
  printf '%s\n' 'function f() {' '    return "the value the slice computed";' '}' 'const g = 1;' > src/f.js
  green s2
  printf 'echo stronger\n' >> test.sh
  ev s1 calibration --oracle-version v2 -- false >/dev/null 2>&1
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/f.js:2-2" ]
}

# --- 2. a later slice moves the lines -----------------------------------------------------------

@test "a later slice adds lines above and inside: the first slice's ranges move and leave its lines out" {
  red s1
  printf '%s\n' a1 a2 s1x s1y a3 a4 a5 > src/a.js
  green s1
  red s2
  printf '%s\n' n1 n2 a1 a2 s1x n3 s1y a3 a4 a5 > src/a.js
  green s2
  # An edit no slice recorded belongs to neither.
  printf '%s\n' n1 n2 a1 a2 s1x n3 s1y a3 a4 a5 late > src/a.js
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:5-5,src/a.js:7-7" ]
  run --separate-stderr mr s2
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:1-2,src/a.js:6-6" ]
}

@test "a later refactor that reorders functions or reindents keeps the slice's lines" {
  printf '%s\n' 'function first() {' '  return "alpha beta gamma delta";' '}' 'function second() {' '  return "epsilon zeta eta theta";' '}' > src/f.js
  git add -A && git commit -q -m f
  red s1
  printf '%s\n' 'function first() {' '  return "alpha beta gamma delta";' '}' 'function second() {' '  const value = "the slice computes this value here";' '  return value + "epsilon zeta eta theta";' '}' > src/f.js
  green s1
  # The refactor puts second() first and indents its body further.
  printf '%s\n' 'function second() {' '    const value = "the slice computes this value here";' '    return value + "epsilon zeta eta theta";' '}' 'function first() {' '  return "alpha beta gamma delta";' '}' > src/f.js
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/f.js:2-3" ]
}

@test "a function a later refactor moved to a new file is followed with --file" {
  printf '%s\n' 'export function keep() { return "unchanged line of the product"; }' > src/g.js
  git add -A && git commit -q -m g
  red s1
  printf '%s\n' 'export function keep() { return "unchanged line of the product"; }' 'export function added() {' '  return "a line the slice wrote for its behavior";' '}' > src/g.js
  green s1
  printf '%s\n' 'export function keep() { return "unchanged line of the product"; }' > src/g.js
  printf '%s\n' 'export function added() {' '  return "a line the slice wrote for its behavior";' '}' > src/h.js
  run --separate-stderr mr s1 --file src/h.js
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/h.js:1-3" ]
}

@test "a later change that copies the slice's lines to a new file, leaving the source unchanged, is followed with --file (claude-kit#11, Codex)" {
  printf '%s\n' 'export function keep() { return "unchanged line of the product"; }' > src/g.js
  git add -A && git commit -q -m g
  red s1
  printf '%s\n' 'export function keep() { return "unchanged line of the product"; }' 'export function added() {' '  return "a line the slice wrote for its behavior";' '}' > src/g.js
  green s1
  # g.js stays as the slice left it; h.js is a copy of its function.
  printf '%s\n' 'export function added() {' '  return "a line the slice wrote for its behavior";' '}' > src/h.js
  run --separate-stderr mr s1 --file src/h.js
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/h.js:1-3" ]
}

@test "known limit: a copy into a file that already existed, the source left unchanged, is not followed (-C -C searches only for a new file; change the expectation if that changes)" {
  printf '%s\n' 'export function keep() { return "unchanged line of the product"; }' > src/g.js
  printf '%s\n' 'export const other = "a file that was already there";' > src/h.js
  git add -A && git commit -q -m g
  red s1
  printf '%s\n' 'export function keep() { return "unchanged line of the product"; }' 'export function added() {' '  return "a line the slice wrote for its behavior";' '}' > src/g.js
  green s1
  printf '%s\n' 'export const other = "a file that was already there";' 'export function added() {' '  return "a line the slice wrote for its behavior";' '}' > src/h.js
  run --separate-stderr mr s1 --file src/h.js
  [ "$status" -eq 3 ] || { echo "$status $output $stderr"; false; }
}

@test "a line a later change copied out of an oracle file into a new product file is not the slice's" {
  printf '%s\n' 'function f(a) {' '  return a;' '}' > src/f.js
  git add -A && git commit -q -m f
  red s1
  printf '%s\n' 'function f(a) {' '  return a + 1;' '}' > src/f.js
  printf '%s\n' 'function helperTheTestWrote(value) {' '  return computeTheValueOfTheThing(value) + 1;' '}' >> test.sh
  green s1
  printf '%s\n' 'function helperTheTestWrote(value) {' '  return computeTheValueOfTheThing(value) + 1;' '}' > src/n.js
  run --separate-stderr mr s1 --file src/n.js
  [ "$status" -eq 3 ] || { echo "$status $output $stderr"; false; }
}

@test "a textconv diff driver does not change the lines blame sees" {
  printf 'src/*.js diff=up\n' > .gitattributes && git add .gitattributes && git commit -q -m attr
  git config diff.up.textconv 'sh -c "echo converted"'
  red s1
  printf '%s\n' a1 a2 B3 a4 a5 > src/a.js
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:3-3" ]
}

# --- 3. two slices in one file, nothing committed -----------------------------------------------

@test "two slices editing one file in single mode, uncommitted: each gets only its own lines" {
  red s1
  printf '%s\n' a1 X2 a3 a4 a5 > src/a.js
  green s1
  red s2
  printf '%s\n' a1 X2 a3 X4 a5 > src/a.js
  green s2
  # A diff from the base would give both lines to each slice.
  [ "$(git diff -U0 HEAD -- src/a.js | grep -c '^+[^+]')" = "2" ]
  run --separate-stderr mr s1
  [ "$output" = "src/a.js:2-2" ]
  run --separate-stderr mr s2
  [ "$output" = "src/a.js:4-4" ]
}

# --- 4. an untracked new file -------------------------------------------------------------------

@test "an untracked new product file of the slice: all of its lines" {
  red s1
  printf '%s\n' n1 n2 n3 > src/new.js
  printf '%s\n' a1 a2 a3 a4 a5 a6 > src/a.js
  green s1
  [ "$(git status --porcelain -- src/new.js)" = "?? src/new.js" ]
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:6-6,src/new.js:1-3" ]
}

# --- 5. which files -----------------------------------------------------------------------------

@test "without --file: every file the slice changed except its oracle files and .vetdd/" {
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  printf '%s\n' b1 b2 > src/b.js
  printf 'echo stronger\n' >> test.sh
  mkdir -p .vetdd/notes && printf 'n\n' > .vetdd/notes/x.js
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:1-1,src/b.js:1-2" ]
}

@test "an oracle file of an earlier oracle version is still left out" {
  printf 'echo t2\n' > t2.sh && git add t2.sh && git commit -q -m t2
  ev s1 before --seam unit --oracle-version v1 --oracle-file t2.sh -- false >/dev/null 2>&1
  printf 'echo t2 changed\n' > t2.sh
  ev s1 calibration --oracle-version v2 --oracle-file test.sh -- false >/dev/null 2>&1
  printf 'echo t2 changed again\n' > t2.sh
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:1-1" ]
}

@test "--file limits the output to the files named, in the order named, once each" {
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  printf '%s\n' b1 b2 > src/b.js
  green s1
  run --separate-stderr mr s1 --file src/b.js
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/b.js:1-2" ]
  run --separate-stderr mr s1 --file src/b.js --file src/a.js --file ./src/b.js
  [ "$output" = "src/b.js:1-2,src/a.js:1-1" ]
}

@test "--file of an oracle file, a missing file, or a file outside the repository: exit 2" {
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  green s1
  run --separate-stderr mr s1 --file test.sh
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"test.sh"*"oracle file"* ]] || { echo "$stderr"; false; }
  run --separate-stderr mr s1 --file src/none.js
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"src/none.js"* ]]
  printf 'x\n' > "$BATS_TEST_TMPDIR/out.js"
  run --separate-stderr mr s1 --file "$BATS_TEST_TMPDIR/out.js"
  [ "$status" -eq 2 ]
  run --separate-stderr mr s1 --file
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "--file of a gitignored file: exit 2, it is in no tree" {
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  green s1
  mkdir -p ignored && printf 'x\n' > ignored/i.js
  run --separate-stderr mr s1 --file ignored/i.js
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"ignored/i.js"* ]]
}

@test "--file of a file the slice did not change: nothing printed, a note naming it, exit 3" {
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  green s1
  run --separate-stderr mr s1 --file sub/keep.txt
  [ "$status" -eq 3 ]
  [ -z "$output" ]
  [[ "$stderr" == *"sub/keep.txt"* ]]
}

@test "from a subdirectory: paths are relative to it, and a changed file outside it is left out with a note" {
  mkdir -p lib && printf 'z1\n' > lib/z.js && git add lib && git commit -q -m lib
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  printf '%s\n' z1 z2 > lib/z.js
  green s1
  cd src
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "a.js:1-1" ]
  [[ "$stderr" == *"lib/z.js"* ]]
  run --separate-stderr mr s1 --file a.js
  [ "$output" = "a.js:1-1" ]
}

@test "only files Stryker mutates are printed: a README.md, package.json, or .css the slice changed is named on stderr and left out (#74 item 6)" {
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  printf '%s\n' 'export const b = 1;' > src/b.ts
  printf '%s\n' 'export const c = 1;' > src/c.MJS
  # Stryker 10 parses .vue .svelte .html .htm too (getFormat in @stryker-mutator/instrumenter).
  printf '%s\n' '<script>const d = 1;</script>' > src/d.vue
  printf '%s\n' '<script>let e = 1;</script>' > src/e.Svelte
  printf '%s\n' '<script>var f = 1;</script>' > src/f.htm
  printf '# readme\n' > README.md
  printf '{"name": "x"}\n' > package.json
  printf 'a {}\n' > src/s.css
  # Never handed to Stryker, so a name it would misread is left out, not refused.
  printf 'n\n' > 'notes,1.md'
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$status $output $stderr"; false; }
  [ "$output" = "src/a.js:1-1,src/b.ts:1-1,src/c.MJS:1-1,src/d.vue:1-1,src/e.Svelte:1-1,src/f.htm:1-1" ]
  local f
  for f in README.md package.json src/s.css 'notes,1.md'; do
    [[ "$stderr" == *"$f: not a file Stryker mutates"* ]] || { echo "$f: $stderr"; false; }
  done
  [[ "$stderr" != *"src/a.js"* ]] || { echo "$stderr"; false; }
  # Named with --file: left out the same way.
  run --separate-stderr mr s1 --file README.md --file src/a.js
  [ "$status" -eq 0 ] || { echo "$status $output $stderr"; false; }
  [ "$output" = "src/a.js:1-1" ]
  [[ "$stderr" == *"README.md: not a file Stryker mutates"* ]] || { echo "$stderr"; false; }
  run --separate-stderr mr s1 --file package.json
  [ "$status" -eq 3 ]
  [ -z "$output" ]
  [[ "$stderr" == *"package.json: not a file Stryker mutates"* ]] || { echo "$stderr"; false; }
}

@test "a slice whose only product change is a README.md: nothing printed, exit 3, the file named and the mutation note pointed to (#74 item 6)" {
  red s1
  printf '# readme\n' > README.md
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 3 ]
  [ -z "$output" ]
  [[ "$stderr" == *"README.md: not a file Stryker mutates"* ]] || { echo "$stderr"; false; }
  [[ "$stderr" == *"audit-note.sh s1 --kind mutation --not-applicable"* ]] || { echo "$stderr"; false; }
}

# --- 6. deletions -------------------------------------------------------------------------------

@test "a deletion-only change: no range for that file, and a note on stderr naming it" {
  printf '%s\n' c1 c2 > src/c.js && git add -A && git commit -q -m c
  red s1
  printf '%s\n' a1 a2 a4 a5 > src/a.js
  rm "$REPO/src/c.js"
  printf '%s\n' b1 > src/b.js
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/b.js:1-1" ]
  [[ "$stderr" == *"src/a.js"* ]] || { echo "$stderr"; false; }
  [[ "$stderr" == *"src/c.js"* ]] || { echo "$stderr"; false; }
}

@test "only deletions: nothing printed, exit 3, the file named" {
  red s1
  printf '%s\n' a1 a2 a4 a5 > src/a.js
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 3 ]
  [ -z "$output" ]
  [[ "$stderr" == *"src/a.js"* ]]
}

@test "a file the slice changed and a later edit moved away: a note that says to name its new path" {
  red s1
  printf '%s\n' a1 X2 a3 a4 a5 > src/a.js
  printf '%s\n' b1 b2 > src/b.js
  green s1
  git mv -f src/a.js src/moved.js 2>/dev/null || mv "$REPO/src/a.js" "$REPO/src/moved.js"
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/b.js:1-2" ]
  [[ "$stderr" == *"src/a.js"*"--file"* ]] || { echo "$stderr"; false; }
  run --separate-stderr mr s1 --file src/moved.js
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/moved.js:2-2" ]
}

# --- verify mode (#71) ---------------------------------------------------------------------------

@test "verify mode: after a calibration red, the pre-change green to the last one is the change; after a before, a green on the unchanged tree leaves nothing (as verify.md says)" {
  ev s1-verify calibration --oracle-version 1 --oracle-file test.sh --infra-exit 2 -- false >/dev/null 2>&1
  ev s1-verify calibration -- true >/dev/null 2>&1
  green s1-verify
  printf '%s\n' a1 X2 a3 a4 a5 > src/a.js
  green s1-verify
  run --separate-stderr mr s1-verify
  [ "$status" -eq 0 ] || { echo "$status $output $stderr"; false; }
  [ "$output" = "src/a.js:2-2" ]
  git checkout -q -- src/a.js
  red s2-verify
  green s2-verify
  printf '%s\n' a1 a2 a3 Y4 a5 > src/a.js
  green s2-verify
  run --separate-stderr mr s2-verify
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"same tree"* ]] || { echo "$stderr"; false; }
  grep -- '- \*\*Mutation\.\*\*' "$SCRIPTS/../modes/verify.md" | grep -q '"the same tree"'
}

# --- 7. a test-only slice -----------------------------------------------------------------------

@test "a slice with no product change: prints nothing, exit 3, points to the mutation note" {
  red s1
  printf 'echo stronger\n' >> test.sh
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 3 ]
  [ -z "$output" ]
  [[ "$stderr" == *"audit-note.sh s1 --kind mutation --not-applicable"* ]] || { echo "$stderr"; false; }
  [[ "$stderr" == *"modes/test.md"* ]]
}

@test "a slice whose before and after trees are the same cannot be attributed: exit 2, pointing to a new red rather than the note (review r4, r5)" {
  red s1
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"same tree"* ]] || { echo "$stderr"; false; }
  [[ "$stderr" == *"unchanged tree"*"--oracle-version"* ]] || { echo "$stderr"; false; }
  [[ "$stderr" != *"audit-note.sh"* ]] || { echo "$stderr"; false; }
}

@test "an empty refactor (its afters all on one tree): exit 3, and the note is right (review r5)" {
  green s1
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 3 ]
  [ -z "$output" ]
  [[ "$stderr" == *"empty refactor"*"audit-note.sh s1 --kind mutation --not-applicable"* ]] || { echo "$stderr"; false; }
}

# --- 8. errors ----------------------------------------------------------------------------------

@test "a slice without evidence, without a before and two passing afters, or without a passing after: exit 2" {
  run --separate-stderr mr s1
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"s1"* ]]
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"no before run and fewer than two passing after runs"* ]] || { echo "$stderr"; false; }
  red s2
  ev s2 after -- false >/dev/null 2>&1 || true
  run --separate-stderr mr s2
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"after"* ]] || { echo "$stderr"; false; }
  [ -z "$output" ]
}

@test "a tree object that is gone (git gc) or a malformed tree hash: exit 2" {
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  green s1
  tamper s1 '.runs[0].tree.tree_hash = "1234567890abcdef1234567890abcdef12345678"'
  run --separate-stderr mr s1
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"1234567890abcdef1234567890abcdef12345678"* ]] || { echo "$stderr"; false; }
  [[ "$stderr" == *"gc"* ]]
  tamper s1 '.runs[0].tree.tree_hash = "HEAD"'
  run --separate-stderr mr s1
  [ "$status" -eq 2 ]
  tamper s1 '.runs[0].tree.tree_hash = null'
  run --separate-stderr mr s1
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "usage errors: no slice, a bad slice id, an unknown argument, outside a repository: exit 2" {
  run --separate-stderr mr
  [ "$status" -eq 2 ]
  run --separate-stderr mr ../x
  [ "$status" -eq 2 ]
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  green s1
  run --separate-stderr mr s1 --bogus
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--bogus"* ]]
  cd "$BATS_TEST_TMPDIR"
  run --separate-stderr mr s1
  [ "$status" -eq 2 ]
}

@test "a meta.json that is not the slice's evidence: exit 2" {
  mkdir -p .vetdd/evidence/s1
  printf 'not json\n' > .vetdd/evidence/s1/meta.json
  run --separate-stderr mr s1
  [ "$status" -eq 2 ]
}

# --- 9. nothing changes -------------------------------------------------------------------------

@test "the throwaway commits leave no ref and change neither HEAD, the index, nor the working tree" {
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  printf '%s\n' n1 > src/new.js
  green s1
  printf 'staged\n' > staged.js && git add staged.js
  local st1 st2 idx1 idx2 refs1 refs2 head1 head2 log1 log2
  st1="$(git status --porcelain=v1 --untracked-files=all)"
  idx1="$(cksum < .git/index)"
  refs1="$(git for-each-ref --format='%(refname) %(objectname)')"
  head1="$(git rev-parse HEAD; git symbolic-ref HEAD)"
  log1="$(git reflog --all | wc -l)"
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  idx2="$(cksum < .git/index)"
  st2="$(git status --porcelain=v1 --untracked-files=all)"
  refs2="$(git for-each-ref --format='%(refname) %(objectname)')"
  head2="$(git rev-parse HEAD; git symbolic-ref HEAD)"
  log2="$(git reflog --all | wc -l)"
  [ "$idx1" = "$idx2" ]
  [ "$st1" = "$st2" ]
  [ "$refs1" = "$refs2" ]
  [ "$head1" = "$head2" ]
  [ "$log1" = "$log2" ]
  [ -z "$(git stash list)" ]
}

@test "works without a git identity, with an ignore-revs file configured, and with commit signing on" {
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  green s1
  git config --global --unset user.name
  git config --global --unset user.email
  git config --global commit.gpgsign true
  git config --global gpg.program false
  git config --global blame.ignoreRevsFile .no-such-file
  run --separate-stderr env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL \
    EMAIL= "$SCRIPTS/mutate-ranges.sh" s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:1-1" ]
}

# --- 10. paths ----------------------------------------------------------------------------------

@test "a path with spaces is printed as is" {
  red s1
  printf '%s\n' m1 m2 > "src/my file.js"
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/my file.js:1-2" ]
  run --separate-stderr mr s1 --file "src/my file.js"
  [ "$output" = "src/my file.js:1-2" ]
}

@test "a path Stryker would split or read as a pattern is refused with a message: exit 2" {
  local p
  for p in 'src/a,b.js' 'src/[x].js' 'src/x*.js' 'src/x:1-2.js' 'src/{x}.js' '!x.js' \
    "src/a';id;'.js" 'src/a"b.js' 'src/a`b.js' 'src/a$b.js' 'src/a;b.js' 'src/a&b.js' 'src/a|b.js' 'src/a<b.js' 'src/a>b.js'; do
    rm -rf "$REPO/.vetdd"
    red s1
    printf '%s\n' q1 > "$p"
    green s1
    run --separate-stderr mr s1
    [ "$status" -eq 2 ] || { echo "$p: $status $output $stderr"; false; }
    [ -z "$output" ]
    [[ "$stderr" == *"$p"* ]] || { echo "$stderr"; false; }
    rm -f -- "$REPO/$p"
  done
  # A bidirectional control or a zero-width space: named with its bytes shown as ?.
  for p in "src/a$(printf '\342\200\256')b.js" "src/a$(printf '\342\200\213')b.js" "src/a$(printf '\357\273\277')b.js" \
    "src/a$(printf '\342\201\240')b.js" "src/a$(printf '\330\234')b.js" "src/a$(printf '\342\200\250')b.js" "src/a$(printf '\341\240\216')b.js"; do
    rm -rf "$REPO/.vetdd"
    red s1
    printf '%s\n' q1 > "$p"
    green s1
    run --separate-stderr mr s1
    [ "$status" -eq 2 ] || { echo "$status $output $stderr"; false; }
    [ -z "$output" ]
    [[ "$stderr" == *"src/a??b.js"* || "$stderr" == *"src/a???b.js"* ]] || { echo "$stderr"; false; }
    rm -f -- "$REPO/$p"
  done
  rm -rf "$REPO/.vetdd"
  red s1
  printf '%s\n' q1 > 'src/a,b.js'
  green s1
  run --separate-stderr mr s1
  [[ "$stderr" == *"comma"* ]] || { echo "$stderr"; false; }
}

@test "a path with a newline is refused: the output stays one line" {
  red s1
  printf '%s\n' q1 > "src/a
b.js"
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 2 ] || { echo "$status $output $stderr"; false; }
  [ -z "$output" ]
}

@test "a meta.json whose run oracle is malformed: exit 2, the oracle files are never mutated by mistake" {
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  printf 'echo changed\n' >> test.sh
  green s1
  tamper s1 '.runs[1].oracle.files = [1]'
  run --separate-stderr mr s1
  [ "$status" -eq 2 ] || { echo "$status $output $stderr"; false; }
  [ -z "$output" ]
}

@test "a changed file a later edit renamed away is noted, even when its old name would be refused" {
  red s1
  printf '%s\n' q1 > 'src/a,b.js'
  printf '%s\n' b1 > src/b.js
  green s1
  mv "$REPO/src/a,b.js" "$REPO/src/a-b.js"
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$status $output $stderr"; false; }
  [ "$output" = "src/b.js:1-1" ]
  [[ "$stderr" == *"src/a,b.js"*"--file"* ]] || { echo "$stderr"; false; }
}

@test "a symbolic link the slice added is not a file to mutate" {
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  ln -s a.js src/link.js
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:1-1" ]
}

# --- docs ---------------------------------------------------------------------------------------

@test "the script's header names its usage and exit codes" {
  sed -n '2,/^set -u/p' "$SCRIPTS/mutate-ranges.sh" | grep -q 'Usage: mutate-ranges.sh <slice-id> \[--file <path>\]'
  sed -n '2,/^set -u/p' "$SCRIPTS/mutate-ranges.sh" | grep -q 'Exit 0'
  sed -n '2,/^set -u/p' "$SCRIPTS/mutate-ranges.sh" | grep -q ' 3 '
}

@test "test mode takes the ranges from mutate-ranges.sh, keeps the widening rule, and drops git diff -U0" {
  local doc="$SCRIPTS/../modes/test.md"
  sed -n '/^### Mutation/,/^## /p' "$doc" | grep -qF 'mutate-ranges.sh" <slice>'
  ! grep -q 'git diff -U0' "$doc" || false
  sed -n '/^### Mutation/,/^## /p' "$doc" | grep -q 'widen'
  sed -n '/^### Mutation/,/^## /p' "$doc" | grep -q "Attention"
  sed -n '/^## Close/,/^## Traps/p' "$doc" | grep -q 'mutate-ranges.sh'
}

@test "swarm and arena Close run each slice's mutation audit on mutate-ranges.sh over the integrated tree" {
  grep -q 'mutate-ranges.sh <slice>' "$SCRIPTS/../parallel/swarm.md"
  grep -q 'mutate-ranges.sh' "$SCRIPTS/../parallel/arena.md"
}

@test "the documented use stops on exit 2 or 3 instead of running Stryker with an empty --mutate (#74 item 7)" {
  local doc="$SCRIPTS/../modes/test.md" sec
  # No command substitution inside --mutate: it would go on with an empty value when the script fails.
  ! grep -rn -- '--mutate "$(' "$SCRIPTS" "$SCRIPTS/../modes" "$SCRIPTS/../parallel" "$SCRIPTS/../SKILL.md" || false
  sed -n '2,/^set -u/p' "$SCRIPTS/mutate-ranges.sh" | grep -qF 'r="$(mutate-ranges.sh <slice>)" && npx --no-install stryker run <config> --mutate "$r"'
  sec="$(sed -n '/^### Mutation/,/^## /p' "$doc" | tr '\n' ' ')"
  [[ "$sec" == *'r="$("$VETDD/scripts/mutate-ranges.sh" <slice>)" &&'* ]] || { echo "$sec"; false; }
  [[ "$sec" == *'--mutate "$r"'* ]]
  # Exit 3 points to the test-only note, in the doc and in the script's header.
  [[ "$sec" == *'Exit 3'*'audit-note.sh <slice> --kind mutation --not-applicable'* ]] || { echo "$sec"; false; }
  sed -n '2,/^set -u/p' "$SCRIPTS/mutate-ranges.sh" | tr '\n' ' ' | grep -qF '3 when there is nothing to mutate'
  sed -n '2,/^set -u/p' "$SCRIPTS/mutate-ranges.sh" | tr '\n' ' ' | grep -q 'audit-note.sh <slice> --kind mutation --not-applicable'
}

@test "the header and test mode say only files Stryker mutates are printed, and a red after the first after can start the slice" {
  local doc="$SCRIPTS/../modes/test.md" sec
  sed -n '2,/^set -u/p' "$SCRIPTS/mutate-ranges.sh" | tr '\n' ' ' | grep -q 'VETDD_STRYKER_RE'
  grep -q '^VETDD_STRYKER_RE=' "$SCRIPTS/lib/common.sh"
  sec="$(sed -n '/^### Mutation/,/^## /p' "$doc" | tr '\n' ' ')"
  [[ "$sec" == *'only files Stryker mutates'*'.vue'* ]] || { echo "$sec"; false; }
  [[ "$sec" == *'the first red that a passing `after` follows'* ]] || { echo "$sec"; false; }
}
