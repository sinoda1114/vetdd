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
