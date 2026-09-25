#!/usr/bin/env bats
# setup-project.sh: idempotent install of .vetdd/, .gitignore entry, and the pre-commit hook

load test_helper

setup() { make_repo; }

setup_project() { "$SCRIPTS/setup-project.sh" "$@"; }

hook_path() { echo "$REPO/.git/hooks/pre-commit"; }

@test "first run creates .vetdd/, ignores it, and installs an executable hook" {
  run setup_project
  [ "$status" -eq 0 ]
  [ -d "$REPO/.vetdd" ]
  [ "$(grep -cx '.vetdd/' .gitignore)" -eq 1 ]
  grep -qx 'ignored/' .gitignore
  [ -x "$(hook_path)" ]
  grep -q "vetdd" "$(hook_path)"
  [[ "$output" == *".gitignore"* ]]
  [[ "$output" == *"pre-commit"* ]]
}

@test "second run changes nothing and says so" {
  setup_project
  sum_before="$(cat .gitignore "$(hook_path)" | sha256_of /dev/stdin)"
  run setup_project
  [ "$status" -eq 0 ]
  [[ "$output" == *"no changes"* ]]
  [ "$(cat .gitignore "$(hook_path)" | sha256_of /dev/stdin)" = "$sum_before" ]
  [ ! -e "$REPO/.git/hooks/pre-commit.before-vetdd" ]
}

@test "an existing .vetdd entry in .gitignore is not duplicated" {
  printf '/.vetdd/\n' >> .gitignore
  setup_project
  [ "$(grep -c 'vetdd' .gitignore)" -eq 1 ]
}

@test "missing .gitignore is created" {
  git rm -q .gitignore
  setup_project
  [ "$(cat .gitignore)" = ".vetdd/" ]
}

@test ".gitignore without a trailing newline keeps its last line intact" {
  printf 'ignored/' > .gitignore
  setup_project
  grep -qx 'ignored/' .gitignore
  grep -qx '.vetdd/' .gitignore
}

@test "a foreign pre-commit hook is backed up with a warning" {
  printf '#!/bin/sh\necho foreign\n' > "$(hook_path)" && chmod +x "$(hook_path)"
  run setup_project
  [ "$status" -eq 0 ]
  [[ "$output" == *"warning"* ]] || [[ "$output" == *"WARNING"* ]]
  [ "$(cat "$REPO/.git/hooks/pre-commit.before-vetdd")" = "$(printf '#!/bin/sh\necho foreign')" ]
  grep -q "vetdd" "$(hook_path)"
}

@test "a foreign hook with an existing backup is left alone and the run fails" {
  printf '#!/bin/sh\necho foreign\n' > "$(hook_path)"
  printf 'old backup\n' > "$REPO/.git/hooks/pre-commit.before-vetdd"
  run setup_project
  [ "$status" -ne 0 ]
  grep -q foreign "$(hook_path)"
  [ "$(cat "$REPO/.git/hooks/pre-commit.before-vetdd")" = "old backup" ]
}

@test "core.hooksPath is never modified; a set hooksPath produces a warning" {
  setup_project
  run git config --get core.hooksPath
  [ "$status" -ne 0 ]
  git config --global core.hooksPath "$HOME/hooks"
  rm "$(hook_path)"
  run setup_project
  [ "$status" -eq 0 ]
  [[ "$output" == *"core.hooksPath"* ]]
  [ "$(git config --global --get core.hooksPath)" = "$HOME/hooks" ]
  [ ! -e "$HOME/hooks/pre-commit" ]
  [ -x "$(hook_path)" ]
}

@test "--repo sets up another repository from any cwd" {
  cd "$BATS_TEST_TMPDIR"
  run setup_project --repo "$REPO"
  [ "$status" -eq 0 ]
  [ -d "$REPO/.vetdd" ]
  [ -x "$(hook_path)" ]
}

@test "from a linked worktree the hook goes to the common hooks dir" {
  git worktree add -q "$BATS_TEST_TMPDIR/wt" -b wt
  cd "$BATS_TEST_TMPDIR/wt"
  setup_project
  [ -x "$(hook_path)" ]
  [ -d "$BATS_TEST_TMPDIR/wt/.vetdd" ]
}
