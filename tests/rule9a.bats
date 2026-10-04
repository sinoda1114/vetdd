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
  record_oracle a.test.ts $'// it.only("x", () => {});\n  // describe.only("y", () => {});\n/* it.only("z") */\n * it.only("w")\nit("ok", () => {});'
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

@test "rule 9a never prints control characters from the file name or the line" {
  record_oracle a.test.ts 'it.only("x", () => {});'
  run check s1
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
