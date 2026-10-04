#!/usr/bin/env bats
# check-evidence rule 9a: a focused test (.only, fdescribe) left in a JS/TS oracle file runs only
# that test and skips the rest, so a green means less than it says. A tripwire for an accident,
# not a boundary: a rewording, a helper, or a file not named with --oracle-file passes it.

load test_helper

setup() { make_repo; }

# record_oracle <file> <content>: the content is the oracle file; the command is test.sh.
record_oracle() {
  printf '%s\n' "$2" > "$1"
  printf '0\n' > value.txt
  ev s1 before --oracle-version v1 --oracle-file "$1" -- sh test.sh
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh
}

@test "rule 9a fails an it.only in a TS oracle file and names the file and line" {
  record_oracle a.test.ts $'import { it } from "vitest";\nit.only("x", () => {});'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (9a: oracle file a.test.ts line 2 "* ]]
}

@test "rule 9a covers describe.only, test.only, suite.only, context.only, and fdescribe" {
  for body in 'describe.only("x", () => {});' 'test.only("x", () => {});' 'suite.only("x", () => {});' \
              'context.only("x", () => {});' 'fdescribe("x", () => {});' '  it.only ("x", () => {});' \
              'x; it.only("x", () => {});'; do
    rm -rf .vetdd
    record_oracle a.test.js "$body"
    run check s1
    [ "$status" -eq 1 ] || { echo "$body: $output"; false; }
    [[ "$output" == *"9a: "* ]] || { echo "$body: $output"; false; }
  done
}

@test "rule 9a ignores a commented-out .only" {
  record_oracle a.test.ts $'// it.only("x", () => {});\n  // describe.only("y", () => {});\n/* it.only("z") */\n/**\n * it.only("w")\n */\nit("ok", () => {});'
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "s1: OK" ]
}

@test "rule 9a ignores a trailing comment after the code and a name that only contains .only" {
  record_oracle a.test.ts $'it("ok", () => {}); // it.only("x")\nconst o = { only: 1 }; o.only(1);\nfit("kept", () => {});\nmyit.only("x");\nthis.it.only("y");'
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "rule 9a looks only at JS and TS extensions" {
  record_oracle test_a.py $'def f():\n    it.only("x")'
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "s1: OK" ]
}

@test "rule 9a checks every JS and TS extension" {
  for ext in js jsx mjs cjs ts tsx mts cts; do
    rm -rf .vetdd
    record_oracle "a.test.$ext" 'it.only("x", () => {});'
    run check s1
    [ "$status" -eq 1 ] || { echo "$ext: $output"; false; }
  done
}

@test "rule 9a reports each focused line" {
  record_oracle a.test.ts $'it.only("a", () => {});\nit("b", () => {});\ndescribe.only("c", () => {});'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 1 "* ]]
  [[ "$output" == *"line 3 "* ]]
}

@test "a control character in a recorded oracle path is stopped by rule 6 and never reaches 9a or the terminal" {
  record_oracle a.test.ts 'it("x", () => {});'
  jq '.oracle.files += [{"path": "b\u001b[2K.ts", "sha256": null}]' .vetdd/evidence/s1/meta.json > m && mv m .vetdd/evidence/s1/meta.json
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"6: oracle.files holds an entry"* ]]
  [[ "$output" != *"9a:"* ]]
  [[ "$output" != *$'\033'* ]]
}

@test "a clean TS oracle file is OK" {
  record_oracle a.test.ts $'import { it, expect } from "vitest";\nit("x", () => { expect(1).toBe(1); });'
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "s1: OK" ]
}

@test "rule 9a does not open a path that leaves the repository" {
  record_oracle a.test.ts 'it("x", () => {});'
  printf 'it.only("x")\n' > "$REPO/../outside.ts"
  ln -s ../outside.ts out.ts
  jq '.oracle.files += [{"path": "out.ts", "sha256": null}]' .vetdd/evidence/s1/meta.json > m && mv m .vetdd/evidence/s1/meta.json
  run check s1
  [[ "$output" == *"6: oracle file out.ts is a symbolic link or outside the repository"* ]]
  [[ "$output" != *"9a: oracle file out.ts"* ]]
}

@test "rule 9a ignores .only inside a string on the line" {
  record_oracle a.test.ts $'it("never write it.only(x) in a suite", () => {});\nit(\'or describe.only(y)\', () => {});\nconst s = `fdescribe(z)`;'
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "s1: OK" ]
}

@test "rule 9a still catches a focused test after a string on the same line" {
  record_oracle a.test.ts $'const n = "a"; it.only("x", () => {});'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9a: "* ]]
}

# --- the focus APIs of the common runners ---------------------------------------------------------

@test "rule 9a covers Playwright, each, concurrent, and specify forms" {
  for body in 'test.describe.only("x", () => {});' 'test.describe.serial.only("x", () => {});' \
              'test.describe.parallel.only("x", () => {});' 'it.only.each([1])("x", () => {});' \
              'test.only.each([1])("x", () => {});' 'describe.only.each([1])("x", () => {});' \
              'test.concurrent.only("x", async () => {});' 'specify.only("x", () => {});' \
              'it.only`a|b`("x", () => {});'; do
    rm -rf .vetdd
    record_oracle a.test.ts "$body"
    run check s1
    [ "$status" -eq 1 ] || { echo "$body: $output"; false; }
  done
}

@test "rule 9a leaves it.skip, it.each, and a plain describe alone" {
  record_oracle a.test.ts $'it.skip("a", () => {});\nit.each([1])("b", () => {});\ntest.describe("c", () => {});\nit.concurrent("d", async () => {});'
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# --- strings and comments are followed across the file --------------------------------------------

@test "rule 9a finds a real focused test after one inside a string on the same line" {
  record_oracle a.test.ts $'const name = "it.only(x)"; it.only("x", () => {});'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 1 "* ]]
}

@test "rule 9a is not fooled by an apostrophe, a URL, or an escaped quote before the call" {
  for body in $'const name = "user\'s test"; it.only("x", () => {});' \
              $'const u = "http://x"; it.only("x", () => {});' \
              $'const s = "say \\"hi\\""; it.only("x", () => {});'; do
    rm -rf .vetdd
    record_oracle a.test.ts "$body"
    run check s1
    [ "$status" -eq 1 ] || { echo "$body: $output"; false; }
  done
}

@test "rule 9a ignores a quoted example with an escaped quote" {
  record_oracle a.test.ts $'it("reject \\"it.only(x)\\" in examples", () => {});'
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "rule 9a follows block comments across lines and sees code after one" {
  record_oracle a.test.ts $'/*\nit.only("x", () => {});\n  describe.only("y")\n*/\nit("ok", () => {});'
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  rm -rf .vetdd
  record_oracle a.test.ts $'/* note */ it.only("x", () => {});'
  run check s1
  [ "$status" -eq 1 ]
}

@test "rule 9a ignores a focused test inside a multi-line template literal" {
  record_oracle a.test.ts $'const fixture = `\n  it.only("x", () => {});\n`;\nit("ok", () => {});'
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  rm -rf .vetdd
  record_oracle a.test.ts $'const fixture = `\n  it.only("x");\n`; it.only("real", () => {});'
  run check s1
  [ "$status" -eq 1 ]
}

@test "rule 9a fails closed on a line too long to scan, naming it" {
  record_oracle a.test.ts "$(printf 'const x = "%030000d";' 0)"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9a: oracle file a.test.ts line 1 is over 20000 characters"* ]]
}

@test "rule 9a fails when the scanner itself fails, never OK (A3)" {
  record_oracle a.test.ts 'it.only("x", () => {});'
  mkdir -p "$BATS_TEST_TMPDIR/badawk"
  printf '#!/bin/sh\nexit 2\n' > "$BATS_TEST_TMPDIR/badawk/awk"; chmod +x "$BATS_TEST_TMPDIR/badawk/awk"
  PATH="$BATS_TEST_TMPDIR/badawk:$PATH" run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9a: could not scan oracle file a.test.ts"* ]]
  [[ "$output" != *"s1: OK"* ]]
}
