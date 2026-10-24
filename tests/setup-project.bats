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

# #57: with a core.hooksPath, git never runs the repository's hook. The warning prints one line for the
# hooksPath pre-commit that runs the installed vetdd hook (trusted code, never a file of the repository),
# and skips with a warning when that install is gone, so a removed vetdd blocks no commit.
chain_line() { printf '%s\n' "$1" | grep -E '^ +vetdd_hook=' | sed 's/^ *//'; }

# Puts the printed line into $HOME/hooks/pre-commit (core.hooksPath is set globally to $HOME/hooks).
# Fails when the output holds no line, so a test never goes on with an empty hook.
chain_into_global_hooks() {
  local line; line="$(chain_line "$1")"
  [ -n "$line" ] || { echo "no line in: $1"; return 1; }
  printf '#!/bin/sh\n%s\n' "$line" > "$HOME/hooks/pre-commit" && chmod +x "$HOME/hooks/pre-commit"
}

global_hooks_path() { mkdir -p "$HOME/hooks" && git config --global core.hooksPath "$HOME/hooks"; }

@test "#57: a set core.hooksPath prints the line that runs the installed vetdd hook, and that line works" {
  global_hooks_path
  run setup_project
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"WARNING"*"$HOME/hooks/pre-commit"* ]] || { echo "$output"; false; }
  [[ "$(chain_line "$output")" == *"/hooks/pre-commit"* ]] || { echo "$output"; false; }
  chain_into_global_hooks "$output"
  mkdir -p .vetdd/evidence
  printf 'x\n' > chained.txt && git add chained.txt
  run git commit -q -m chained
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"vetdd pre-commit"* ]]
}

@test "#57: through the line, a vetdd check that fails blocks the commit" {
  global_hooks_path
  run setup_project
  chain_into_global_hooks "$output"
  mkdir -p .vetdd/evidence/-bad && printf '{}\n' > .vetdd/evidence/-bad/meta.json
  local head; head="$(git rev-parse HEAD)"
  printf 'x\n' > blocked.txt && git add blocked.txt
  run git commit -q -m blocked
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *"commit blocked"* ]] || { echo "$output"; false; }
  [ "$(git rev-parse HEAD)" = "$head" ]
}

@test "#57: when the install the line points at is gone, the commit goes through with a warning" {
  global_hooks_path
  cp -R "$SCRIPTS" "$BATS_TEST_TMPDIR/gone"
  run "$BATS_TEST_TMPDIR/gone/setup-project.sh"
  [[ "$(chain_line "$output")" == *"$BATS_TEST_TMPDIR/gone/hooks/pre-commit"* ]] || { echo "$output"; false; }
  chain_into_global_hooks "$output"
  rm -rf "$BATS_TEST_TMPDIR/gone"
  mkdir -p .vetdd/evidence/-bad && printf '{}\n' > .vetdd/evidence/-bad/meta.json
  printf 'x\n' > through.txt && git add through.txt
  run git commit -q -m through
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"not found; skipped"* ]] || { echo "$output"; false; }
}

@test "#57: a hooksPath pre-commit that already mentions the installed hook gets no warning" {
  global_hooks_path
  run setup_project
  chain_into_global_hooks "$output"
  run setup_project
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *WARNING* ]] || { echo "$output"; false; }
  [ -z "$(chain_line "$output")" ]
}

@test "#57: the line never runs a hook the repository carries, even one that claims to be vetdd's" {
  global_hooks_path
  run setup_project
  chain_into_global_hooks "$output"
  printf '#!/bin/sh\n# vetdd pre-commit hook\ntouch "%s/foreign"\n' "$BATS_TEST_TMPDIR" > "$(hook_path)"
  printf 'y\n' > other.txt && git add other.txt
  git commit -q -m other
  [ ! -e "$BATS_TEST_TMPDIR/foreign" ]
}

@test "#57: a hooksPath that is this repository's own hooks directory gets no warning" {
  git config core.hooksPath .git/hooks
  run setup_project
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *WARNING* ]]
  git config core.hooksPath "$REPO/.git/hooks"
  run setup_project
  [[ "$output" != *WARNING* ]]
}

@test "#57: a hooksPath written with ~ is expanded by git" {
  mkdir -p "$HOME/hooks"
  git config --global core.hooksPath '~/hooks'
  run setup_project
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"$HOME/hooks/pre-commit"* ]] || { echo "$output"; false; }
}

@test "#57: with husky (core.hooksPath .husky/_), the warning prints no line for the shared .husky/pre-commit" {
  mkdir -p .husky/_
  git config core.hooksPath .husky/_
  run setup_project
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *WARNING*husky* ]] || { echo "$output"; false; }
  [ -z "$(chain_line "$output")" ]
  [[ "$output" != *'"$@"'* ]] || { echo "$output"; false; }
  [ ! -e .husky/pre-commit ]
}

@test "#57: the line holds an install path with a space, a quote and a \$ intact" {
  global_hooks_path
  local odd="$BATS_TEST_TMPDIR/a b\"c\$d"
  cp -R "$SCRIPTS" "$odd"
  run "$odd/setup-project.sh"
  chain_into_global_hooks "$output"
  # The file holds the escaped path, and the second run finds it.
  run "$odd/setup-project.sh"
  [[ "$output" != *WARNING* ]] || { echo "$output"; false; }
  mkdir -p .vetdd/evidence
  printf 'x\n' > odd.txt && git add odd.txt
  run git commit -q -m odd
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"vetdd pre-commit"* ]] || { echo "$output"; false; }
}

# #64: a hooksPath inside the work tree (husky 9's .husky/_, husky 8's .husky, a tracked .githooks) holds
# files shared with the team: no line with this machine's install path, a pointer to check-evidence.sh.
in_tree_hooks_path_gets_no_line() {
  run setup_project
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *WARNING*"$1"*check-evidence.sh* ]] || { echo "$output"; false; }
  [ -z "$(chain_line "$output")" ] || { echo "$output"; false; }
  [[ "$output" != *'"$@"'* ]] || { echo "$output"; false; }
}

@test "#64: core.hooksPath .husky (husky 8) prints no line" {
  mkdir -p .husky
  git config core.hooksPath .husky
  in_tree_hooks_path_gets_no_line .husky
  [ ! -e .husky/pre-commit ]
}

@test "#64: core.hooksPath .githooks (a tracked hooks dir) prints no line" {
  mkdir -p .githooks
  git config core.hooksPath .githooks
  in_tree_hooks_path_gets_no_line .githooks
  [ ! -e .githooks/pre-commit ]
}

@test "#64: core.hooksPath .husky/_/ with a trailing slash prints no line" {
  mkdir -p .husky/_
  git config core.hooksPath .husky/_/
  in_tree_hooks_path_gets_no_line .husky/_/
}

@test "#64: an absolute hooksPath whose physical path is inside the work tree prints no line" {
  mkdir -p .githooks
  ln -s "$REPO/.githooks" "$BATS_TEST_TMPDIR/linked-hooks"
  git config --global core.hooksPath "$BATS_TEST_TMPDIR/linked-hooks"
  in_tree_hooks_path_gets_no_line linked-hooks
}

@test "#64: a hooksPath inside the git dir (not the hooks dir) still gets the line" {
  mkdir -p .git/myhooks
  git config core.hooksPath .git/myhooks
  run setup_project
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *WARNING*".git/myhooks/pre-commit"* ]] || { echo "$output"; false; }
  [ -n "$(chain_line "$output")" ] || { echo "$output"; false; }
}

@test "#64: in a linked worktree, a relative .git/hooks is not a directory: said so, no line" {
  git config core.hooksPath .git/hooks
  git worktree add -q "$BATS_TEST_TMPDIR/wt" -b wt
  cd "$BATS_TEST_TMPDIR/wt"
  run setup_project
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *WARNING*"not a directory"* ]] || { echo "$output"; false; }
  [ -z "$(chain_line "$output")" ] || { echo "$output"; false; }
  [ -f "$BATS_TEST_TMPDIR/wt/.git" ]
}

@test "#64: a hooksPath that does not exist is said so, with no line" {
  git config --global core.hooksPath "$HOME/no-such-hooks"
  run setup_project
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *WARNING*"$HOME/no-such-hooks"*"not a directory"* ]] || { echo "$output"; false; }
  [ -z "$(chain_line "$output")" ] || { echo "$output"; false; }
  [ ! -e "$HOME/no-such-hooks" ]
}

@test "#64: a hooksPath with a ~user git cannot expand gets a warning" {
  git config --global core.hooksPath '~vetdd-no-such-user-64/hooks'
  run setup_project
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *WARNING*"cannot expand"*"~vetdd-no-such-user-64/hooks"* ]] || { echo "$output"; false; }
  [ -z "$(chain_line "$output")" ] || { echo "$output"; false; }
}

@test "#64: through the line, an installed hook without the exec bit is skipped as not executable" {
  global_hooks_path
  cp -R "$SCRIPTS" "$BATS_TEST_TMPDIR/noexec"
  run "$BATS_TEST_TMPDIR/noexec/setup-project.sh"
  chain_into_global_hooks "$output"
  chmod -x "$BATS_TEST_TMPDIR/noexec/hooks/pre-commit"
  mkdir -p .vetdd/evidence/-bad && printf '{}\n' > .vetdd/evidence/-bad/meta.json
  printf 'x\n' > noexec.txt && git add noexec.txt
  run git commit -q -m noexec
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"not executable; skipped"* ]] || { echo "$output"; false; }
  [[ "$output" != *"not found"* ]] || { echo "$output"; false; }
}

@test "#64: a hooksPath pre-commit that mentions the hook but is not executable gets a warning" {
  global_hooks_path
  run setup_project
  chain_into_global_hooks "$output"
  chmod -x "$HOME/hooks/pre-commit"
  run setup_project
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *WARNING*"$HOME/hooks/pre-commit"*"not executable"* ]] || { echo "$output"; false; }
  [ -z "$(chain_line "$output")" ] || { echo "$output"; false; }
}
