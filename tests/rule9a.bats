#!/usr/bin/env bats
# check-evidence rule 9a: a focused test (.only, fdescribe) left in a JS/TS oracle file runs only
# that test and skips the rest, so a green means less than it says. A tripwire for an accident,
# not a boundary: a rewording, a helper, or a file not named with --oracle-file passes it.

load test_helper

setup() { make_repo; }

# record_oracle <file> <content>: the content is the oracle file; the command is test.sh. A JS/TS
# oracle is asked for the mutation audit (rule 10c, #25); these tests are about 9a, so it gets a note.
record_oracle() {
  printf '%s\n' "$2" > "$1"
  printf '0\n' > value.txt
  ev s1 before --oracle-version v1 --oracle-file "$1" -- sh test.sh
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh
  printf 'rule 9a test: no product to mutate\n' > "$BATS_TEST_TMPDIR/mut-note.txt"
  "$SCRIPTS/audit-note.sh" s1 --kind mutation --not-applicable --reason-file "$BATS_TEST_TMPDIR/mut-note.txt" >/dev/null
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
  [ "$status" -eq 1 ]
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

@test "rule 9a fails closed on a line too long to scan that holds a focus, naming it" {
  record_oracle a.test.ts "$(printf 'const x = "%030000d"; it.only("x", () => {});' 0)"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9a: oracle file a.test.ts line 1 is over 20000 characters"* ]]
  rm -rf .vetdd
  record_oracle a.test.ts "$(printf 'const x = "%030000d"; fdescribe("x", () => {});' 0)"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9a: oracle file a.test.ts line 1 is over 20000 characters"* ]]
}

# --- #7: a long line with no only or fdescribe text in it is not a FAIL ------------------------------

# long_code <count>: one minified-looking line of <count> statements (9 characters each), then a
# regular expression and a division, with no only or fdescribe text.
long_code() {
  printf 'f("a",1);%.0s' $(seq 1 "$1")
  printf 'var r=/x/g,d=a/b;'
}

@test "rule 9a passes a minified line over 20000 characters that holds no only or fdescribe (#7)" {
  record_oracle a.test.js "$(long_code 3000)"$'\nit("ok", () => {});'
  run check s1
  [ "$status" -eq 0 ] || { echo "${output:0:400}"; false; }
  [ "$output" = "s1: OK" ]
}

@test "rule 9a still finds a focused test on a short line after a long one (#7)" {
  record_oracle a.test.js "$(long_code 3000)"$'\nit.only("x", () => {});'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9a: oracle file a.test.js line 2 holds a focused test"* ]] || { echo "${output:0:400}"; false; }
}

@test "rule 9a reads the comments and templates a long line opens or closes (#7)" {
  # The long line closes the comment opened above it: the focus after it is code.
  record_oracle a.test.js $'/* start\n'"x */ $(long_code 3000)"$'\nit.only("x", () => {});'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 3 holds a focused test"* ]] || { echo "${output:0:400}"; false; }
  [[ "$output" != *"could not be scanned to the end"* ]] || { echo "${output:0:400}"; false; }
  # The long line opens a template literal: the focus inside it is text.
  rm -rf .vetdd
  record_oracle a.test.js "$(long_code 3000) const t = \`"$'\nit.only("x");\n`;\nit("ok", () => {});'
  run check s1
  [ "$status" -eq 0 ] || { echo "${output:0:400}"; false; }
}

@test "rule 9a sees a focused call split across the end of a long line (#7)" {
  record_oracle a.test.js "$(long_code 3000) it"$'\n.only("x", () => {});'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 2 holds a focused test"* ]] || { echo "${output:0:400}"; false; }
  # A focus the line before left open (it.only, then its call on the long line) is not let through.
  rm -rf .vetdd
  record_oracle a.test.js $'it.only\n'"(\"x\", () => {}); $(long_code 3000)"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9a: oracle file a.test.js line 2 "* ]] || { echo "${output:0:400}"; false; }
}

@test "rule 9a reads a long line in linear time, not quadratic (#7)" {
  # The scanner alone, on a line of statements and a regular expression at one length and at twice
  # it. A quadratic path (substr per character, which measures the whole line on every call in macOS
  # awk 20200816, or a regular expression blanked one space at a time) makes the longer take about
  # four times as long; the linear scan about twice (measured here: under 1.5 seconds for the longer).
  eval "$(sed -n '/^focused_lines() {$/,/^}$/p' "$SCRIPTS/check-evidence.sh")"
  printf '%s\n' "$(long_code 15000)const r=/$(printf '%0300000d' 0)/;" > short.js
  printf '%s\n' "$(long_code 30000)const r=/$(printf '%0600000d' 0)/;" > long.js
  local t0 t1 t2 o1 o2
  t0=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  o1=$(focused_lines short.js)
  t1=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  o2=$(focused_lines long.js)
  t2=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  [ -z "$o1" ] && [ -z "$o2" ] || { echo "found: $o1 $o2"; false; }
  perl -e 'my ($a, $b) = ($ARGV[1] - $ARGV[0], $ARGV[2] - $ARGV[1]); print "$a $b\n"; exit($b < 3 * $a ? 0 : 1)' "$t0" "$t1" "$t2"
}

@test "rule 9a still reads what a long line it does not search opens and closes (#7)" {
  # The long line holds the text only in its code, so it is not searched, but it closes the comment
  # opened above it: the focus after it is code, and the file is read to its end.
  record_oracle a.test.js $'/* start\n'"x */ const readonly = 1; $(long_code 3000)"$'\nit.only("x", () => {});'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 2 is over 20000 characters"* ]] || { echo "${output:0:400}"; false; }
  [[ "$output" == *"line 3 holds a focused test"* ]] || { echo "${output:0:400}"; false; }
  [[ "$output" != *"could not be scanned to the end"* ]] || { echo "${output:0:400}"; false; }
}

@test "rule 9a searches a long line whose only text is in strings and comments (#7)" {
  record_oracle a.test.js "const k = \"readonly\"; $(long_code 3000) /* only once */ g(\`fdescribe\`); // it.only("x")"$'\nit("ok", () => {});'
  run check s1
  [ "$status" -eq 0 ] || { echo "${output:0:400}"; false; }
}

@test "rule 9a fails closed when awk does not split a line into characters (#7)" {
  # A stand-in awk that runs the real one with the self-check made to see a one-field split.
  local real
  real="$(command -v awk)"
  mkdir -p "$BATS_TEST_TMPDIR/oddawk"
  printf '#!/usr/bin/env perl\nexec "%s", map { s/split\\("ab", t, ""\\)/split("ab", t, "z")/r } @ARGV;\n' "$real" \
    > "$BATS_TEST_TMPDIR/oddawk/awk"
  chmod +x "$BATS_TEST_TMPDIR/oddawk/awk"
  record_oracle a.test.ts 'it("ok", () => {});'
  PATH="$BATS_TEST_TMPDIR/oddawk:$PATH" run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9a: could not scan oracle file a.test.ts"* ]] || { echo "$output"; false; }
}

@test "rule 9a fails closed on a line over 1000000 characters, which it does not read (#7)" {
  record_oracle a.test.js "$(printf 'const x = "%01000001d";' 0)"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9a: oracle file a.test.js line 1 is over 1000000 characters"* ]] || { echo "${output:0:400}"; false; }
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

# --- regular expression literals, line continuations, spacing, extension case (round 2) -----------

@test "rule 9a is not thrown off by a regular expression holding /* or a backtick (B1)" {
  for re in 'p.replace(/\/*$/, "")' 'p.split(/[/*]/)' 'p.replace(/a\/*b/, "")' 'p.replace(/[`]/, "")' 'p.match(/https?:\/\//)'; do
    rm -rf .vetdd
    record_oracle a.test.ts "$(printf 'expect(%s).toBe("a");\nit.only("x", () => {});' "$re")"
    run check s1
    [ "$status" -eq 1 ] || { echo "$re: $output"; false; }
    [[ "$output" == *"line 2 "* ]] || { echo "$re: $output"; false; }
  done
}

@test "rule 9a still treats a division as a division, not a regular expression (B1)" {
  record_oracle a.test.ts $'const r = a / b; const t = c /* note */ / d;\nit.only("x", () => {});'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 2 "* ]]
}

@test "rule 9a fails closed when a comment or template stays open to the end of the file (B1)" {
  record_oracle a.test.ts $'it("a", () => {});\n/* never closed\nit.only("x", () => {});'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"9a: oracle file a.test.ts could not be scanned to the end"* ]]
  rm -rf .vetdd
  record_oracle a.test.ts $'const t = `never closed\nit("a");'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not be scanned to the end"* ]]
}

@test "rule 9a follows a string continued with a backslash at the end of the line (B2)" {
  record_oracle a.test.ts $'const s = "abc \\\nit.only(x)";\nit("ok", () => {});'
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  rm -rf .vetdd
  record_oracle a.test.ts $'const s = "abc \\\ndef"; it.only("real", () => {});'
  run check s1
  [ "$status" -eq 1 ]
}

@test "rule 9a sees .only split from its call by spacing, a comment, or a line break (B3)" {
  for body in $'it .only("x", () => {});' $'it/* note */.only("x", () => {});' $'it.only\n("x", () => {});' \
              $'test.describe\n  .only("x", () => {});' $'it.only.each([1])\n("x", () => {});'; do
    rm -rf .vetdd
    record_oracle a.test.ts "$body"
    run check s1
    [ "$status" -eq 1 ] || { echo "$body: $output"; false; }
  done
}

@test "rule 9a does not take a property named only on another object for a focus (B3)" {
  record_oracle a.test.ts $'const o = { only: 1 };\nconst v = o.only;\nexpect(list.only).toBe(1);\nit("ok", () => {});'
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "rule 9a reads JS and TS extensions in any letter case (B4)" {
  for ext in TS Tsx JS mjs; do
    rm -rf .vetdd
    record_oracle "a.test.$ext" 'it.only("x", () => {});'
    run check s1
    [ "$status" -eq 1 ] || { echo "$ext: $output"; false; }
  done
}

# --- round 3: CRLF, long call chains, property access, JSX, closing a continued string -------------

@test "rule 9a gives the same answer for CRLF and LF files (D1)" {
  for body in $'it.only("x", () => {});' $'it.only\n("x", () => {});' $'test.describe\n  .only("x", () => {});' \
              $'const s = "abc \\\ndef"; it.only("real", () => {});'; do
    rm -rf .vetdd
    record_oracle a.test.ts "$(printf '%s' "$body" | sed 's/$/\r/')"
    run check s1
    [ "$status" -eq 1 ] || { echo "crlf: $body: $output"; false; }
  done
}

@test "rule 9a sees a call split over several lines, blank lines, and a long comment (D2)" {
  for body in $'it\n.only\n("x", () => {});' $'it.only\n\n\n("x", () => {});' \
              "$(printf 'it.only\n/* %0600d */\n("x", () => {});' 0)" \
              $'it.only("a"); test\n.only("b", () => {});'; do
    rm -rf .vetdd
    record_oracle a.test.ts "$body"
    run check s1
    [ "$status" -eq 1 ] || { echo "$body: $output"; false; }
  done
  rm -rf .vetdd
  record_oracle a.test.ts $'it.only("a"); test\n.only("b", () => {});'
  run check s1
  [[ "$output" == *"line 2 "* ]]
}

@test "rule 9a leaves a property access alone however it is spaced (D3)" {
  record_oracle a.test.ts $'this . it.only("x", () => {});\nthis.\n  it.only("y", () => {});\nobj /* c */ . describe.only("z");'
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "rule 9a is not thrown off by JSX closing tags in a TSX file (D4)" {
  record_oracle a.test.tsx $'const el = <div></div>; it.only("x", () => { render(<p>a</p>) });'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 1 "* ]]
}

@test "rule 9a reads a slash after a closed continued string or a postfix increment as division (D5)" {
  record_oracle a.test.ts $'const t = `a\nb` / 2; it.only("x"); const r = 1 / 3;'
  run check s1
  [ "$status" -eq 1 ]
  rm -rf .vetdd
  record_oracle a.test.ts $'i++ / 2; it.only("a/b", () => {}); j-- / 2;'
  run check s1
  [ "$status" -eq 1 ]
}

# --- round 4: a division that continues on the next line, an arrow function returning a regex -------

@test "rule 9a keeps what the previous line ended with, so a slash that starts a line is a division (F1)" {
  record_oracle a.test.ts $'const ratio = width\n  / height; it.only("w/h", () => {});'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 2 "* ]]
  rm -rf .vetdd
  record_oracle a.test.ts $'const re =\n  /x"y/;\nit.only("a", () => {});'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 3 "* ]]
}

@test "rule 9a reads a regular expression after an arrow as a regular expression (F1)" {
  record_oracle a.test.ts $'const hasTick = (s) => /`/.test(s);\nit.only("a", () => {});'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 2 "* ]]
  rm -rf .vetdd
  record_oracle a.test.ts $'const f = (s) => /\\/*$/.test(s);\nit.only("a", () => {});'
  run check s1
  [ "$status" -eq 1 ]
}

@test "rule 9a sees a focused call with a type argument (test.only<T>)" {
  record_oracle a.test.ts $'test.only<number>("x", () => {});'
  run check s1
  [ "$status" -eq 1 ]
}
