#!/usr/bin/env bats
# Repository hygiene checks that encode past review findings (principle 9).

load test_helper

@test "tests never write to the shared /tmp; they use \$BATS_TEST_TMPDIR" {
  # /tmp is world-writable and predictable names can be pre-seeded with symlinks (ai-review R37).
  run grep -nE '(^|[^A-Za-z_])[/]tmp[/]' "$VETDD_ROOT"/tests/*.bats "$VETDD_ROOT"/tests/*.bash
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "the eval scripts create temporary files only inside a private mktemp -d directory" {
  # A sibling like "$tmp.prompt" is a predictable name beside a random one (review E16).
  local f
  for f in judge check-blind sanitize-candidates; do
    run grep -c 'mktemp -d ' "$SCRIPTS/$f.sh"
    [ "$output" -ge 1 ] || { echo "$f.sh: no mktemp -d"; false; }
    run sh -c 'grep -n "mktemp" "$1" | grep -v "mktemp -d "' _ "$SCRIPTS/$f.sh"
    [ "$status" -eq 1 ] || { echo "$f.sh: $output"; false; }
  done
}

@test "#50: utf8_locale fails instead of returning nothing when REQUIRE_UTF8_LOCALE_TESTS=1 (the bash 3.2 CI job)" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho C\necho POSIX\n' > "$BATS_TEST_TMPDIR/bin/locale"
  chmod +x "$BATS_TEST_TMPDIR/bin/locale"
  # Cleared here: the macOS job runs every test with it set.
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" REQUIRE_UTF8_LOCALE_TESTS= run utf8_locale
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" REQUIRE_UTF8_LOCALE_TESTS=1 run utf8_locale
  [ "$status" -eq 1 ]
  [[ "$output" == *"REQUIRE_UTF8_LOCALE_TESTS"* ]]
  # The macOS job sets it.
  grep -q 'REQUIRE_UTF8_LOCALE_TESTS: "1"' "$VETDD_ROOT/.github/workflows/extra.yml"
}

# fixture_suite <dir> <bin>: a one-test suite under <dir>/tests that loads this test_helper and calls
# needs_fixture <bin>; its VETDD_ROOT is <dir>, so <dir>/fixtures/ts-kata stands in for the fixture.
# The test also fails when a VETDD_ test switch is still in its environment (evidence.sh records the
# names of the VETDD_ variables it runs under).
fixture_suite() {
  mkdir -p "$1/tests"
  printf 'load %s\n@test "inner" {\n  needs_fixture %s\n  [ -z "$(env | grep -E "^VETDD_(REQUIRE_FIXTURES|REAL_STRYKER)=")" ]\n  echo "inner ran"\n}\n' \
    "$VETDD_ROOT/tests/test_helper" "$2" > "$1/tests/inner.bats"
}

# inner_bats <env assignments...>: run the inner suite under a clean set of the switches.
inner_bats() {
  run env -u VETDD_REQUIRE_FIXTURES -u REQUIRE_FIXTURE_TESTS -u VETDD_REAL_STRYKER -u REAL_STRYKER_TESTS \
    "$@" "$VETDD_ROOT/node_modules/.bin/bats" --show-output-of-passing-tests "$BATS_TEST_TMPDIR/root/tests/inner.bats"
}

@test "#12: with VETDD_REQUIRE_FIXTURES=1 a fixture test fails when the fixture has no node_modules" {
  fixture_suite "$BATS_TEST_TMPDIR/root" vitest
  inner_bats VETDD_REQUIRE_FIXTURES=1
  [ "$status" -eq 1 ] || { echo "status $status: $output"; false; }
  [[ "$output" == *"not ok 1 inner"* ]] || { echo "$output"; false; }
  [[ "$output" == *"fixtures/ts-kata/node_modules/.bin/vitest is missing"* ]] || { echo "$output"; false; }
  [[ "$output" == *"VETDD_REQUIRE_FIXTURES=1"* ]] || { echo "$output"; false; }
  [[ "$output" != *"# skip"* ]] || { echo "$output"; false; }
}

@test "#12: without VETDD_REQUIRE_FIXTURES (or with another value) the same fixture test skips" {
  fixture_suite "$BATS_TEST_TMPDIR/root" vitest
  inner_bats
  [ "$status" -eq 0 ] || { echo "status $status: $output"; false; }
  [[ "$output" == *"ok 1 inner # skip fixtures/ts-kata/node_modules/.bin/vitest is missing (npm ci --prefix fixtures/ts-kata --ignore-scripts)"* ]] \
    || { echo "$output"; false; }
  inner_bats VETDD_REQUIRE_FIXTURES=0
  [ "$status" -eq 0 ] || { echo "status $status: $output"; false; }
  [[ "$output" == *"ok 1 inner # skip"* ]] || { echo "$output"; false; }
}

@test "#12: with the fixture installed the test runs, and neither VETDD_ switch reaches it" {
  fixture_suite "$BATS_TEST_TMPDIR/root" tsc
  mkdir -p "$BATS_TEST_TMPDIR/root/fixtures/ts-kata/node_modules/.bin"
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/root/fixtures/ts-kata/node_modules/.bin/tsc"
  chmod +x "$BATS_TEST_TMPDIR/root/fixtures/ts-kata/node_modules/.bin/tsc"
  inner_bats VETDD_REQUIRE_FIXTURES=1 VETDD_REAL_STRYKER=1
  [ "$status" -eq 0 ] || { echo "status $status: $output"; false; }
  [[ "$output" == *"inner ran"* ]] || { echo "$output"; false; }
  [[ "$output" != *"# skip"* ]] || { echo "$output"; false; }
}

@test "#12: with VETDD_REQUIRE_FIXTURES=1 a missing node fails too" {
  fixture_suite "$BATS_TEST_TMPDIR/root" tsc
  mkdir -p "$BATS_TEST_TMPDIR/root/fixtures/ts-kata/node_modules/.bin" "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/root/fixtures/ts-kata/node_modules/.bin/tsc"
  chmod +x "$BATS_TEST_TMPDIR/root/fixtures/ts-kata/node_modules/.bin/tsc"
  # A PATH without node: the system directories, and this bash first.
  [ -z "$(PATH=/usr/bin:/bin command -v node)" ] || skip "node is in /usr/bin or /bin here"
  ln -s "$(command -v bash)" "$BATS_TEST_TMPDIR/bin/bash"
  inner_bats PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" VETDD_REQUIRE_FIXTURES=1
  [ "$status" -eq 1 ] || { echo "status $status: $output"; false; }
  [[ "$output" == *"node is not installed"* ]] || { echo "$output"; false; }
}

@test "#12: every test that needs fixtures/ts-kata's dependencies asks needs_fixture, never a bare skip" {
  # A skip on the fixture's node_modules written in a test would pass CI silently again.
  run sh -c 'grep -hnE "(^|[^a-z_-])skip \"" "$1"/tests/*.bats | grep -E "node_modules|ts-kata|fixture" | grep -v "@test"' _ "$VETDD_ROOT"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  run grep -c 'needs_fixture ' "$VETDD_ROOT"/tests/audit-stub.bats "$VETDD_ROOT"/tests/dogfood-25.bats \
    "$VETDD_ROOT"/tests/ladder-type-oracle.bats "$VETDD_ROOT"/tests/rule10c.bats "$VETDD_ROOT"/tests/test-report.bats \
    "$VETDD_ROOT"/tests/verify-ts-kata.bats
  [[ "$output" != *":0"* ]] || { echo "$output"; false; }
}

@test "#12: both CI jobs that run the suite install the fixture with npm ci and set VETDD_REQUIRE_FIXTURES=1" {
  local wf="$VETDD_ROOT/.github/workflows/extra.yml"
  [ "$(grep -c 'npm ci --prefix fixtures/ts-kata --ignore-scripts' "$wf")" -ge 1 ]
  [ "$(grep -c 'VETDD_REQUIRE_FIXTURES: "1"' "$wf")" -ge 2 ]
  [ "$(grep -c 'VETDD_REAL_STRYKER: "1"' "$wf")" -ge 1 ]
  run grep -nE 'npm install|npm i ' "$wf"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}
