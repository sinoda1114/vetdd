# Shared setup for vetdd bats tests.
# Each test gets an isolated git config and a fresh repository under $BATS_TEST_TMPDIR.

VETDD_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
SCRIPTS="$VETDD_ROOT/skills/vetdd/scripts"
SCHEMA="$VETDD_ROOT/skills/vetdd/schemas/evidence.schema.json"

isolate_git() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  git config --global user.name "vetdd test"
  git config --global user.email "vetdd@example.invalid"
  git config --global init.defaultBranch main
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
}

# Repository whose oracle is `sh test.sh`: it passes only when value.txt holds 42.
make_repo() {
  isolate_git
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/sub"
  cd "$REPO"
  git init -q
  printf 'ignored/\n' > .gitignore
  printf '#!/bin/sh\necho "value is $(cat value.txt)"\n[ "$(cat value.txt)" = "42" ]\n' > test.sh
  printf '0\n' > value.txt
  printf 'keep\n' > sub/keep.txt
  git add -A
  git commit -q -m init
}

# utf8_locale: a UTF-8 locale this machine has (en_US, or else ja_JP), or nothing; a test that needs
# one skips without it. Two kinds of locale bug need it (#50), and each shows only on some machines,
# so these tests pass elsewhere either way:
# - bash 3.2 matches a bracket range ([a-z], [A-Za-z0-9]) by the locale's collation, so [a-z] holds
#   H and é too (bash 5 matches ranges by code point): only under bash 3.2, as macOS /bin/bash is;
# - the macOS tools (BSD tr, awk) stop at an invalid UTF-8 byte ("Illegal byte sequence") under a
#   UTF-8 locale and cut the rest of their input: only with the macOS tools (GNU tr reads bytes).
# Run the suite under bash 3.2 with LANG and LC_ALL set to en_US.UTF-8 to see both (CI's
# bats-bash32 job runs on macOS with LANG=en_US.UTF-8). With REQUIRE_UTF8_LOCALE_TESTS=1 (that job
# sets it), a machine without one fails the test instead of skipping it. Not VETDD_: evidence.sh
# records the names of the VETDD_ variables it runs under.
utf8_locale() {
  local l
  l="$(locale -a 2>/dev/null | grep -ixE '(en_US|ja_JP)\.utf-?8' | LC_ALL=C sort | head -1)"
  [ -n "$l" ] || [ "${REQUIRE_UTF8_LOCALE_TESTS:-}" != 1 ] \
    || { echo "no en_US or ja_JP UTF-8 locale, and REQUIRE_UTF8_LOCALE_TESTS=1" >&2; return 1; }
  [ -z "$l" ] || printf '%s\n' "$l"
}

# The suite's own switches, VETDD_REQUIRE_FIXTURES and VETDD_REAL_STRYKER, are moved to names without
# the VETDD_ prefix before any test runs a script: evidence.sh records the names of the VETDD_
# variables it runs under (conditions.env_keys), so a switch left there would change what tests record.
# REQUIRE_FIXTURE_TESTS and REAL_STRYKER_TESTS are those internal names, not switches to set by hand:
# a VETDD_ value always replaces them, and the messages name the VETDD_ switch.
if [ -n "${VETDD_REQUIRE_FIXTURES+x}" ]; then
  export REQUIRE_FIXTURE_TESTS="$VETDD_REQUIRE_FIXTURES"; unset VETDD_REQUIRE_FIXTURES
fi
if [ -n "${VETDD_REAL_STRYKER+x}" ]; then
  export REAL_STRYKER_TESTS="$VETDD_REAL_STRYKER"; unset VETDD_REAL_STRYKER
fi

# needs_fixture <bin>: the test drives fixtures/ts-kata's own <bin> (vitest, tsc, tsx, stryker) under
# node, and skips when node or that bin is missing (install it with
# `npm ci --prefix fixtures/ts-kata --ignore-scripts`). With VETDD_REQUIRE_FIXTURES=1 (the CI jobs
# that install the fixture set it) the test fails instead, so a missing install never passes as a skip.
needs_fixture() {
  local why=""
  command -v node >/dev/null 2>&1 || why="node is not installed"
  [ -n "$why" ] || [ -x "$VETDD_ROOT/fixtures/ts-kata/node_modules/.bin/$1" ] \
    || why="fixtures/ts-kata/node_modules/.bin/$1 is missing (npm ci --prefix fixtures/ts-kata --ignore-scripts)"
  [ -n "$why" ] || return 0
  if [ "${REQUIRE_FIXTURE_TESTS:-}" = 1 ]; then
    echo "$why, and VETDD_REQUIRE_FIXTURES=1" >&2
    return 1
  fi
  skip "$why"
}

meta() { cat "$REPO/.vetdd/evidence/$1/meta.json"; }

# jq query against a slice's meta.json
mq() { jq -r "$2" "$REPO/.vetdd/evidence/$1/meta.json"; }

# Rewrite a slice's meta.json with a jq filter (simulates hand edits / tampering).
tamper() {
  local f="$REPO/.vetdd/evidence/$1/meta.json"
  jq "$2" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

ev() { "$SCRIPTS/evidence.sh" "$@"; }
check() { "$SCRIPTS/check-evidence.sh" "$@"; }

# stub_ev <slice> [evidence.sh options] -- <command...>: evidence.sh <slice> calibration --audit
# undefined-imports, run as calibrate.sh stub runs it (evidence.sh takes the option from nobody else): the
# slice's calibration state in stub mode, listing the stubbed file, with the pid of the process that runs
# evidence.sh. The stubbed file is ignored/stub.mjs holding the ES module stub, there only for the run, so
# the working tree is as it was afterwards.
stub_ev() {
  local slice="$1" st top rc=0; shift
  st="$(git rev-parse --absolute-git-dir)/vetdd-calib/$slice"
  top="$(git rev-parse --show-toplevel)"
  mkdir -p "$st" "$top/ignored" && printf 'export {};\n' > "$top/ignored/stub.mjs" \
    && echo stub > "$st/mode" && printf 'ignored/stub.mjs\n' > "$st/files" || return 1
  bash -c 'echo "$$" > "$1/pid"; shift; "$@"; rc=$?; exit "$rc"' stub_ev "$st" \
    "$SCRIPTS/evidence.sh" "$slice" calibration --audit undefined-imports "$@" || rc=$?
  rm -rf "$st"; rm -f "$top/ignored/stub.mjs"; rmdir "$top/ignored" 2>/dev/null || true
  return "$rc"
}

# note_text <name> <text>: write one line of text to .vetdd/notes/<name> in the repository and print
# its path (oracle-version.sh and audit-note.sh read their text files only from there).
note_text() {
  local top; top="$(git rev-parse --show-toplevel)"
  mkdir -p "$top/.vetdd/notes" && printf '%s\n' "$2" > "$top/.vetdd/notes/$1" && printf '%s\n' "$top/.vetdd/notes/$1"
}

# before (red) -> fix -> after (green) with test.sh as the oracle file.
record_good_slice() {
  local slice="$1"
  printf '0\n' > "$REPO/value.txt"
  ev "$slice" before --seam unit --oracle-version v1 --oracle-file test.sh -- sh test.sh
  printf '42\n' > "$REPO/value.txt"
  ev "$slice" after -- sh test.sh
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

validate_schema() {
  node "$BATS_TEST_DIRNAME/helpers/validate-schema.mjs" "$SCHEMA" "$1"
}
