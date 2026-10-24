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
# bats-bash32 job runs on macOS with LANG=en_US.UTF-8). With VETDD_REQUIRE_UTF8_LOCALE=1 (that job
# sets it), a machine without one fails the test instead of skipping it.
utf8_locale() {
  local l
  l="$(locale -a 2>/dev/null | grep -ixE '(en_US|ja_JP)\.utf-?8' | LC_ALL=C sort | head -1)"
  [ -n "$l" ] || [ "${VETDD_REQUIRE_UTF8_LOCALE:-}" != 1 ] \
    || { echo "no en_US or ja_JP UTF-8 locale, and VETDD_REQUIRE_UTF8_LOCALE=1" >&2; return 1; }
  [ -z "$l" ] || printf '%s\n' "$l"
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
