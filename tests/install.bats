#!/usr/bin/env bats
# install.sh: check the prerequisites, back up an existing install, and copy skills/vetdd into
# <CLAUDE_CONFIG_DIR or ~/.claude>/skills/vetdd (Phase 7).

load test_helper

INSTALL="$BATS_TEST_DIRNAME/../install.sh"
SRC="$BATS_TEST_DIRNAME/../skills/vetdd"

setup() {
  isolate_git
  unset CODEX_HOME
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

# old_skill <file>: an older vetdd install's SKILL.md.
old_skill() { printf -- '---\nname: vetdd\n---\nold\n' > "$1"; }

# same_as_tracked <dir>: <dir> holds exactly the files git tracks under skills/vetdd, with their content.
same_as_tracked() {
  local f
  diff <(git -C "$SRC" ls-files | LC_ALL=C sort) <(cd "$1" && find . ! -type d | sed 's|^\./||' | LC_ALL=C sort) || return 1
  git -C "$SRC" ls-files | while IFS= read -r f; do cmp -s "$SRC/$f" "$1/$f" || { echo "differs: $f"; exit 1; }; done
}

@test "installs a copy of skills/vetdd and names the next step" {
  run "$INSTALL"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  same_as_tracked "$DEST"
  [[ "$output" == *"setup-project.sh"* ]]
}

@test "works from any directory" {
  cd "$BATS_TEST_TMPDIR"
  run "$INSTALL"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  same_as_tracked "$DEST"
}

@test "--dest installs elsewhere" {
  run "$INSTALL" --dest "$BATS_TEST_TMPDIR/elsewhere/vetdd"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  same_as_tracked "$BATS_TEST_TMPDIR/elsewhere/vetdd"
  [ ! -e "$DEST" ]
}

@test "an existing install is moved to skills-backup/vetdd-<time> and replaced" {
  mkdir -p "$DEST" && old_skill "$DEST/SKILL.md" && printf 'stale\n' > "$DEST/gone.md"
  run "$INSTALL"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  same_as_tracked "$DEST"
  local b; b="$(ls -d "$CLAUDE_CONFIG_DIR"/skills-backup/vetdd-* | head -1)"
  grep -qx old "$b/SKILL.md" && [ -f "$b/gone.md" ]
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
  [ ! -L "$DEST" ] && same_as_tracked "$DEST"
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
  same_as_tracked "$DEST"
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

@test "r1: a --dest without a slash is taken from the current directory, and an old install there is backed up" {
  mkdir -p "$BATS_TEST_TMPDIR/here/vetdd" && old_skill "$BATS_TEST_TMPDIR/here/vetdd/SKILL.md"
  cd "$BATS_TEST_TMPDIR/here"
  run "$INSTALL" --dest vetdd
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  same_as_tracked "$BATS_TEST_TMPDIR/here/vetdd"
  grep -qx old "$(ls -d "$CLAUDE_CONFIG_DIR"/skills-backup/vetdd-* | head -1)/SKILL.md"
}

@test "r1: an empty --dest or / is a usage error" {
  run "$INSTALL" --dest ""
  [ "$status" -eq 2 ]
  run "$INSTALL" --dest /
  [ "$status" -eq 2 ]
}

@test "r1: when the new copy cannot be put in place, the old install comes back" {
  mkdir -p "$DEST" && old_skill "$DEST/SKILL.md"
  # A mv that fails only for the final step (moving the new copy out of the temporary directory).
  mkdir -p "$BATS_TEST_TMPDIR/mvbin"
  printf '#!/bin/sh\ncase "$1" in */.vetdd-install.*) exit 1 ;; esac\nexec /bin/mv "$@"\n' > "$BATS_TEST_TMPDIR/mvbin/mv"
  chmod +x "$BATS_TEST_TMPDIR/mvbin/mv"
  PATH="$BATS_TEST_TMPDIR/mvbin:$PATH" run "$INSTALL"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  grep -qx old "$DEST/SKILL.md"
}

@test "r1: an install whose content matches but whose scripts lost their execute bit is replaced" {
  "$INSTALL" >/dev/null
  chmod -x "$DEST/scripts/evidence.sh"
  run "$INSTALL"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -x "$DEST/scripts/evidence.sh" ]
}

@test "r1: files the checkout does not track (a .DS_Store, a scratch file) are not installed" {
  local tmp; tmp="$SRC/.vetdd-install-test-untracked"
  printf 'x\n' > "$tmp"
  run "$INSTALL"
  rm -f "$tmp"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$DEST/.vetdd-install-test-untracked" ]
}

@test "r1: a --dest whose parent others can write is refused" {
  mkdir -p "$BATS_TEST_TMPDIR/shared" && chmod 777 "$BATS_TEST_TMPDIR/shared"
  run "$INSTALL" --dest "$BATS_TEST_TMPDIR/shared/vetdd"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ ! -e "$BATS_TEST_TMPDIR/shared/vetdd" ]
}

@test "r1: run from standard input (no script path) it stops instead of copying from the current directory" {
  cd "$BATS_TEST_TMPDIR"
  run bash -s < "$INSTALL"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [ ! -e "$DEST" ]
}

@test "r2: a copy that is not a git checkout, unpacked inside another repository, installs all its files" {
  local outer="$BATS_TEST_TMPDIR/outer"
  mkdir -p "$outer/dl" && git -C "$outer" init -q
  cp "$INSTALL" "$outer/dl/install.sh" && mkdir -p "$outer/dl/skills" && cp -R "$SRC" "$outer/dl/skills/vetdd"
  run "$outer/dl/install.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$DEST/SKILL.md" ] && [ -x "$DEST/scripts/setup-project.sh" ]
}

@test "r2: when git cannot list the checkout's files, it stops and keeps the install in place" {
  mkdir -p "$DEST" && old_skill "$DEST/SKILL.md"
  printf 'not an index\n' > "$BATS_TEST_TMPDIR/bad-index"
  GIT_INDEX_FILE="$BATS_TEST_TMPDIR/bad-index" run "$INSTALL"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  grep -qx old "$DEST/SKILL.md"
}

@test "r2: an existing directory at --dest that is not a vetdd install is refused, untouched" {
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/other"
  printf -- '---\nname: other\n---\n' > "$CLAUDE_CONFIG_DIR/skills/other/SKILL.md"
  run "$INSTALL" --dest "$CLAUDE_CONFIG_DIR/skills/"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ -f "$CLAUDE_CONFIG_DIR/skills/other/SKILL.md" ]
  [ ! -e "$CLAUDE_CONFIG_DIR/skills-backup" ]
}

@test "r2: every trailing slash of --dest is dropped" {
  run "$INSTALL" --dest "$BATS_TEST_TMPDIR/t/vetdd//"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  same_as_tracked "$BATS_TEST_TMPDIR/t/vetdd"
}

@test "r2: a parent that is a link to a directory of the user's is accepted" {
  mkdir -p "$BATS_TEST_TMPDIR/real-skills" "$BATS_TEST_TMPDIR/l"
  ln -s "$BATS_TEST_TMPDIR/real-skills" "$BATS_TEST_TMPDIR/l/skills"
  run "$INSTALL" --dest "$BATS_TEST_TMPDIR/l/skills/vetdd"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  same_as_tracked "$BATS_TEST_TMPDIR/real-skills/vetdd"
}

@test "r2: a parent that is a link to a place others can write is refused" {
  mkdir -p "$BATS_TEST_TMPDIR/shared" "$BATS_TEST_TMPDIR/l" && chmod 777 "$BATS_TEST_TMPDIR/shared"
  ln -s "$BATS_TEST_TMPDIR/shared" "$BATS_TEST_TMPDIR/l/skills"
  run "$INSTALL" --dest "$BATS_TEST_TMPDIR/l/skills/vetdd"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ ! -e "$BATS_TEST_TMPDIR/shared/vetdd" ]
}

@test "r2: an ancestor others can write (without the sticky bit) is refused" {
  mkdir -p "$BATS_TEST_TMPDIR/share/x" && chmod 777 "$BATS_TEST_TMPDIR/share"
  run "$INSTALL" --dest "$BATS_TEST_TMPDIR/share/x/vetdd"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ ! -e "$BATS_TEST_TMPDIR/share/x/vetdd" ]
}

@test "r2: a parent the group can write is refused, unless the group is the user's own" {
  [ "$(id -gn)" != "$(id -un)" ] || skip "the primary group is the user's own here"
  mkdir -p "$BATS_TEST_TMPDIR/grp" && chmod 775 "$BATS_TEST_TMPDIR/grp"
  run "$INSTALL" --dest "$BATS_TEST_TMPDIR/grp/vetdd"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "r2: a script replaced by a link to a non-executable copy is not taken as up to date" {
  "$INSTALL" >/dev/null
  cp "$DEST/scripts/evidence.sh" "$BATS_TEST_TMPDIR/ev.sh" && chmod -x "$BATS_TEST_TMPDIR/ev.sh"
  rm "$DEST/scripts/evidence.sh" && ln -s "$BATS_TEST_TMPDIR/ev.sh" "$DEST/scripts/evidence.sh"
  run "$INSTALL"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -L "$DEST/scripts/evidence.sh" ] && [ -x "$DEST/scripts/evidence.sh" ]
}

@test "r2: installed files are never writable by group or others, whatever the checkout's modes" {
  local f="$SRC/references/stall.md" m
  m="$(ls -l "$f" | cut -c1-10)"
  chmod go+w "$f"
  run "$INSTALL"
  chmod go-w "$f"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -z "$(find "$DEST" \( -perm -g+w -o -perm -o+w \) ! -type l)" ]
}

@test "r2: a codex file login others can read is reported with the fix" {
  chmod 644 "$HOME/.codex/auth.json"
  run "$INSTALL"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"chmod 600"* ]]
}

@test "r3: a tracked file missing from the working tree stops it (exit 1) and keeps the install in place" {
  "$INSTALL" >/dev/null
  local f="$SRC/references/stall.md"
  mv "$f" "$BATS_TEST_TMPDIR/stall.md.saved"
  run "$INSTALL"
  mv "$BATS_TEST_TMPDIR/stall.md.saved" "$f"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"references/stall.md"* ]]
  [ -f "$DEST/references/stall.md" ]
}

@test "r3: installed files belong to the user running it, with the checkout's execute bits" {
  run "$INSTALL"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -z "$(find "$DEST" ! -user "$(id -u)")" ]
  [ -x "$DEST/scripts/evidence.sh" ] && [ ! -x "$DEST/SKILL.md" ]
}
