#!/usr/bin/env bats
# install.sh: check the prerequisites, back up an existing install, and copy skills/vetdd into
# <CLAUDE_CONFIG_DIR or ~/.claude>/skills/vetdd (Phase 7).

load test_helper

INSTALL="$BATS_TEST_DIRNAME/../install.sh"
SRC="$BATS_TEST_DIRNAME/../skills/vetdd"

setup() {
  isolate_git
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  DEST="$CLAUDE_CONFIG_DIR/skills/vetdd"
  # A codex with a file login, so the judge's prerequisite is met unless a test takes it away.
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$HOME/.codex"
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/codex" && chmod +x "$BATS_TEST_TMPDIR/bin/codex"
  printf '{"token":"t"}\n' > "$HOME/.codex/auth.json"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

# without <tool>...: a PATH holding every command of the current PATH except the tools named.
without() {
  local shim="$BATS_TEST_TMPDIR/shim" d f n skip
  rm -rf "$shim" && mkdir -p "$shim"
  local IFS=:
  for d in $PATH; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      n="${f##*/}"; skip=0
      for t in "$@"; do [ "$n" = "$t" ] && skip=1; done
      [ "$skip" -eq 1 ] || [ -e "$shim/$n" ] || [ ! -x "$f" ] || ln -s "$f" "$shim/$n"
    done
  done
  printf '%s' "$shim"
}

@test "installs a copy of skills/vetdd and names the next step" {
  run "$INSTALL"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  diff -r "$SRC" "$DEST"
  [[ "$output" == *"setup-project.sh"* ]]
}

@test "works from any directory" {
  cd "$BATS_TEST_TMPDIR"
  run "$INSTALL"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  diff -r "$SRC" "$DEST"
}

@test "--dest installs elsewhere" {
  run "$INSTALL" --dest "$BATS_TEST_TMPDIR/elsewhere/vetdd"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  diff -r "$SRC" "$BATS_TEST_TMPDIR/elsewhere/vetdd"
  [ ! -e "$DEST" ]
}

@test "an existing install is moved to skills-backup/vetdd-<time> and replaced" {
  mkdir -p "$DEST" && printf 'old\n' > "$DEST/SKILL.md" && printf 'stale\n' > "$DEST/gone.md"
  run "$INSTALL"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  diff -r "$SRC" "$DEST"
  local b; b="$(ls -d "$CLAUDE_CONFIG_DIR"/skills-backup/vetdd-* | head -1)"
  [ "$(cat "$b/SKILL.md")" = old ] && [ -f "$b/gone.md" ]
  [[ "$output" == *"$b"* ]]
}

@test "an install already up to date is left alone, with no backup" {
  "$INSTALL" >/dev/null
  run "$INSTALL"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"up to date"* ]]
  [ ! -e "$CLAUDE_CONFIG_DIR/skills-backup" ]
}

@test "an install that is a link (a development checkout) is backed up as the link and replaced by a copy" {
  mkdir -p "$CLAUDE_CONFIG_DIR/skills" "$BATS_TEST_TMPDIR/dev"
  ln -s "$BATS_TEST_TMPDIR/dev" "$DEST"
  run "$INSTALL"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -L "$DEST" ] && diff -r "$SRC" "$DEST"
  [ -L "$(ls -d "$CLAUDE_CONFIG_DIR"/skills-backup/vetdd-* | head -1)" ]
  [ -d "$BATS_TEST_TMPDIR/dev" ]
}

@test "a missing required tool stops it (exit 1), names every missing one, and installs nothing" {
  PATH="$(without jq perl)" run "$INSTALL"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *jq* ]] && [[ "$output" == *perl* ]]
  [ ! -e "$DEST" ]
}

@test "node is required (check-verdict.sh validates the judge's reply with it)" {
  PATH="$(without node)" run "$INSTALL"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *node* ]]
}

@test "without codex it installs and warns that the separate judge cannot run" {
  rm "$BATS_TEST_TMPDIR/bin/codex"
  PATH="$(without codex)" run "$INSTALL"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *codex* ]]
  diff -r "$SRC" "$DEST"
}

@test "with codex but no file login it installs and says how to log in for the judge" {
  rm "$HOME/.codex/auth.json"
  run "$INSTALL"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *'cli_auth_credentials_store = "file"'* ]]
}

@test "an unknown option is a usage error (exit 2) and installs nothing" {
  run "$INSTALL" --bogus
  [ "$status" -eq 2 ]
  [ ! -e "$DEST" ]
}
