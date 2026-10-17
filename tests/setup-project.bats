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

# #57: with a global core.hooksPath, git never runs the repository's hook. The warning prints one line
# that runs the installed vetdd hook (trusted code, never a file of the repository), which does nothing
# in a repository without .vetdd/evidence.
chain_line() { printf '%s\n' "$1" | grep -E '^ +"' | sed 's/^ *//'; }

@test "#57: a set core.hooksPath prints the line that runs the installed vetdd hook, and that line works" {
  mkdir -p "$HOME/hooks"
  git config --global core.hooksPath "$HOME/hooks"
  run setup_project
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"$HOME/hooks/pre-commit"* ]]
  local line; line="$(chain_line "$output")"
  [[ "$line" == *'/hooks/pre-commit" "$@" || exit $?' ]] || { echo "$output"; false; }
  [[ "$line" == "\"$SCRIPTS/hooks/pre-commit\""* ]] || [[ "$line" == *"/scripts/hooks/pre-commit"* ]]
  printf '#!/bin/sh\n%s\n' "$line" > "$HOME/hooks/pre-commit" && chmod +x "$HOME/hooks/pre-commit"
  mkdir -p .vetdd/evidence
  printf 'x\n' > chained.txt && git add chained.txt
  run git commit -q -m chained
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"vetdd pre-commit"* ]]
}

@test "#57: a hooksPath pre-commit that already holds the line is reported as chained, not warned about" {
  mkdir -p "$HOME/hooks"
  git config --global core.hooksPath "$HOME/hooks"
  run setup_project
  printf '#!/bin/sh\n%s\n' "$(chain_line "$output")" > "$HOME/hooks/pre-commit" && chmod +x "$HOME/hooks/pre-commit"
  run setup_project
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *WARNING* ]]
  [[ "$output" == *"appears to chain"* ]]
}

@test "#57 r2: the chained line never runs a hook the repository carries, even one that claims to be vetdd's" {
  mkdir -p "$HOME/hooks"
  git config --global core.hooksPath "$HOME/hooks"
  run setup_project
  printf '#!/bin/sh\n%s\n' "$(chain_line "$output")" > "$HOME/hooks/pre-commit" && chmod +x "$HOME/hooks/pre-commit"
  printf '#!/bin/sh\n# vetdd pre-commit hook\ntouch "%s/foreign"\n' "$BATS_TEST_TMPDIR" > "$(hook_path)"
  printf 'y\n' > other.txt && git add other.txt
  git commit -q -m other
  [ ! -e "$BATS_TEST_TMPDIR/foreign" ]
}

@test "#57 r1: a hooksPath that is this repository's own hooks directory gets no warning and no chaining advice" {
  git config core.hooksPath .git/hooks
  run setup_project
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *WARNING* ]]
  [ -z "$(chain_line "$output")" ]
  git config core.hooksPath "$REPO/.git/hooks"
  run setup_project
  [[ "$output" != *WARNING* ]]
}

@test "#57 r1: a hooksPath written with ~ is expanded, and an unset HOME does not stop the setup" {
  mkdir -p "$HOME/hooks"
  git config --global core.hooksPath '~/hooks'
  run setup_project
  [[ "$output" == *"$HOME/hooks/pre-commit"* ]]
  git config core.hooksPath '~/hooks'
  HOME= run "$SCRIPTS/setup-project.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "#57 r1: a commented line is not taken as chained" {
  mkdir -p "$HOME/hooks"
  git config --global core.hooksPath "$HOME/hooks"
  run setup_project
  printf '#!/bin/sh\n# %s\n' "$(chain_line "$output")" > "$HOME/hooks/pre-commit" && chmod +x "$HOME/hooks/pre-commit"
  run setup_project
  [[ "$output" == *WARNING* ]]
}

@test "#57 r2: with husky (core.hooksPath .husky/_), the line in .husky/pre-commit counts as chained, executable or not" {
  mkdir -p .husky/_
  git config core.hooksPath .husky/_
  run setup_project
  [[ "$output" == *".husky/pre-commit"* ]]
  printf '%s\n' "$(chain_line "$output")" > .husky/pre-commit
  run setup_project
  [[ "$output" != *WARNING* ]] || { echo "$output"; false; }
  [[ "$output" == *"appears to chain"* ]]
}

@test "#57 r2: a chained line with a CRLF ending or trailing blanks still counts" {
  mkdir -p "$HOME/hooks"
  git config --global core.hooksPath "$HOME/hooks"
  run setup_project
  printf '#!/bin/sh\r\n%s  \r\n' "$(chain_line "$output")" > "$HOME/hooks/pre-commit" && chmod +x "$HOME/hooks/pre-commit"
  run setup_project
  [[ "$output" == *"appears to chain"* ]]
}
