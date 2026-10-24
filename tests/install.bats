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

# shim_final_move <shell code>: an mv and a perl that run <shell code> when they are asked to move the
# new copy out of its temporary directory (an argument naming .vetdd-install.), then do the real work.
shim_final_move() {
  local d="$BATS_TEST_TMPDIR/movebin" t real
  mkdir -p "$d"
  for t in mv perl; do
    real="$(command -v "$t")"
    printf '#!/bin/sh\ncase "$*" in */.vetdd-install.*) %s ;; esac\nexec "%s" "$@"\n' "$1" "$real" > "$d/$t"
    chmod +x "$d/$t"
  done
  printf '%s' "$d"
}

# gid_of <path>: the numeric group of <path>.
gid_of() { ls -ldn "$1" | awk '{print $4}'; }

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
  mkdir -p "$CLAUDE_CONFIG_DIR/skills" "$BATS_TEST_TMPDIR/dev" && old_skill "$BATS_TEST_TMPDIR/dev/SKILL.md"
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
  # Only the final step (moving the new copy out of the temporary directory) fails.
  local mb; mb="$(shim_final_move 'exit 1')"
  PATH="$mb:$PATH" run "$INSTALL"
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

# Issue #48: a --dest in a shared place, behind a link, or racing another installer.

# shared_sticky: a root-owned sticky directory everyone can write (a shared temporary place), or nothing.
shared_sticky() {
  local d
  for d in /var/tmp /Users/Shared /dev/shm; do
    [ -z "$(find "$d" -maxdepth 0 -perm -1002 -user 0 2>/dev/null)" ] || { printf '%s' "$d"; return; }
  done
}

@test "i48: a --dest directly in a shared sticky directory is refused, nothing created" {
  local sh; sh="$(shared_sticky)"; [ -n "$sh" ] || skip "no root-owned shared sticky directory here"
  local d="$sh/vetdd-i48-${BATS_TEST_TMPDIR##*/}-$$-$RANDOM"
  [ ! -e "$d" ] || skip "$d exists"
  run "$INSTALL" --dest "$d"
  if [ -e "$d" ]; then rm -rf "$d"; false; fi
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"someone else can write"* ]]
}

@test "i48: a --dest in a private directory inside a shared sticky one is accepted (a sticky ancestor is fine)" {
  local sh; sh="$(shared_sticky)"; [ -n "$sh" ] || skip "no root-owned shared sticky directory here"
  local d; d="$(mktemp -d "$sh/vetdd-i48.XXXXXX")"
  run "$INSTALL" --dest "$d/vetdd"
  local ok=0; same_as_tracked "$d/vetdd" || ok=1
  rm -rf "$d"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$ok" -eq 0 ]
}

@test "i48: a refused --dest creates nothing (missing parents are made only below a safe directory)" {
  mkdir -p "$BATS_TEST_TMPDIR/shared" && chmod 777 "$BATS_TEST_TMPDIR/shared"
  run "$INSTALL" --dest "$BATS_TEST_TMPDIR/shared/new/sub/vetdd"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ ! -e "$BATS_TEST_TMPDIR/shared/new" ]
}

@test "i48: a --dest ending in . or .. is a usage error" {
  mkdir -p "$DEST" && old_skill "$DEST/SKILL.md"
  run "$INSTALL" --dest "$DEST/."
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  run "$INSTALL" --dest "$DEST/scripts/.."
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  grep -qx old "$DEST/SKILL.md"
}

@test "i48: a parent whose access-control list lets others add files is refused" {
  mkdir -p "$BATS_TEST_TMPDIR/acl"
  if [ "$(uname)" = Darwin ]; then
    chmod +a "everyone allow add_file,add_subdirectory,delete_child" "$BATS_TEST_TMPDIR/acl"
  else
    command -v setfacl >/dev/null 2>&1 || skip "no setfacl"
    setfacl -m u:nobody:rwx "$BATS_TEST_TMPDIR/acl" 2>/dev/null || skip "the file system takes no ACL"
  fi
  run "$INSTALL" --dest "$BATS_TEST_TMPDIR/acl/vetdd"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ ! -e "$BATS_TEST_TMPDIR/acl/vetdd" ]
}

@test "i48: an access-control list that only denies (a macOS home) is accepted" {
  [ "$(uname)" = Darwin ] || skip "macOS ACLs"
  mkdir -p "$BATS_TEST_TMPDIR/deny"
  chmod +a "group:everyone deny delete" "$BATS_TEST_TMPDIR/deny"
  run "$INSTALL" --dest "$BATS_TEST_TMPDIR/deny/vetdd"
  chmod -N "$BATS_TEST_TMPDIR/deny"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "i48: a link along --dest that belongs to someone else is refused" {
  mkdir -p "$BATS_TEST_TMPDIR/real-skills" "$BATS_TEST_TMPDIR/l"
  ln -s "$BATS_TEST_TMPDIR/real-skills" "$BATS_TEST_TMPDIR/l/skills"
  # A find that reports the link as nobody's the user's or root's (a test cannot make one).
  local fb="$BATS_TEST_TMPDIR/findbin" realfind; realfind="$(command -v find)"
  mkdir -p "$fb"
  printf '#!/bin/sh\n[ "$1" != "%s" ] || exit 0\nexec "%s" "$@"\n' "$BATS_TEST_TMPDIR/l/skills" "$realfind" > "$fb/find"
  chmod +x "$fb/find"
  PATH="$fb:$PATH" run "$INSTALL" --dest "$BATS_TEST_TMPDIR/l/skills/vetdd"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"$BATS_TEST_TMPDIR/l/skills is a link"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/real-skills/vetdd" ]
}

@test "i48: a --dest that is a link to a directory that is not a vetdd install is refused, untouched" {
  mkdir -p "$CLAUDE_CONFIG_DIR/skills" "$BATS_TEST_TMPDIR/mine/notes"
  printf 'keep\n' > "$BATS_TEST_TMPDIR/mine/notes/a.md"
  ln -s "$BATS_TEST_TMPDIR/mine" "$DEST"
  run "$INSTALL"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"not a vetdd install"* ]]
  [ -L "$DEST" ] && [ -f "$BATS_TEST_TMPDIR/mine/notes/a.md" ] && [ ! -e "$BATS_TEST_TMPDIR/mine/SKILL.md" ]
  [ ! -e "$CLAUDE_CONFIG_DIR/skills-backup" ]
}

@test "i48: the parent is resolved once: a link swapped after the checks does not move the install" {
  mkdir -p "$BATS_TEST_TMPDIR/real-skills" "$BATS_TEST_TMPDIR/l" "$BATS_TEST_TMPDIR/shared"
  chmod 777 "$BATS_TEST_TMPDIR/shared"
  ln -s "$BATS_TEST_TMPDIR/real-skills" "$BATS_TEST_TMPDIR/l/skills"
  # A find that, when the checks reach /, points the link at the shared directory (once).
  local fb="$BATS_TEST_TMPDIR/findbin" realfind; realfind="$(command -v find)"
  mkdir -p "$fb"
  printf '#!/bin/sh\nif [ "$1" = / ] && [ ! -e "%s/swapped" ]; then : > "%s/swapped"; rm "%s"; ln -s "%s" "%s"; fi\nexec "%s" "$@"\n' \
    "$fb" "$fb" "$BATS_TEST_TMPDIR/l/skills" "$BATS_TEST_TMPDIR/shared" "$BATS_TEST_TMPDIR/l/skills" "$realfind" > "$fb/find"
  chmod +x "$fb/find"
  PATH="$fb:$PATH" run "$INSTALL" --dest "$BATS_TEST_TMPDIR/l/skills/vetdd"
  [ -e "$fb/swapped" ]
  [ ! -e "$BATS_TEST_TMPDIR/shared/vetdd" ]
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  same_as_tracked "$BATS_TEST_TMPDIR/real-skills/vetdd"
}

@test "i48: directories it creates for --dest are not writable by group or others, whatever the umask" {
  umask 000
  run "$INSTALL" --dest "$BATS_TEST_TMPDIR/made/a/b/vetdd"
  umask 022
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -z "$(find "$BATS_TEST_TMPDIR/made" -type d \( -perm -g+w -o -perm -o+w \))" ]
  same_as_tracked "$BATS_TEST_TMPDIR/made/a/b/vetdd"
}

@test "i48: the skills-backup directory it creates is not writable by group or others, whatever the umask" {
  mkdir -p "$DEST" && old_skill "$DEST/SKILL.md"
  umask 000
  run "$INSTALL"
  umask 022
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -d "$CLAUDE_CONFIG_DIR/skills-backup" ]
  [ -z "$(find "$CLAUDE_CONFIG_DIR/skills-backup" -maxdepth 0 \( -perm -g+w -o -perm -o+w \))" ]
}

@test "i48: backup names already taken (even twice) are skipped, never moved into" {
  mkdir -p "$DEST" && old_skill "$DEST/SKILL.md"
  local bk="$CLAUDE_CONFIG_DIR/skills-backup" ts=20260101-000000 db="$BATS_TEST_TMPDIR/datebin" n
  mkdir -p "$bk/vetdd-$ts" "$bk/vetdd-$ts-1" "$db"
  : > "$bk/vetdd-$ts/mark" && : > "$bk/vetdd-$ts-1/mark"
  # A date with a fixed time that also takes the names an installer would try next (its pid).
  printf '#!/bin/sh\nfor p in $PPID $(ps -o ppid= -p $PPID); do mkdir -p "%s/vetdd-%s-$p" && : > "%s/vetdd-%s-$p/mark"; done\necho %s\n' \
    "$bk" "$ts" "$bk" "$ts" "$ts" > "$db/date"
  chmod +x "$db/date"
  PATH="$db:$PATH" run "$INSTALL"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  same_as_tracked "$DEST"
  for n in "$bk"/vetdd-"$ts"*; do
    [ ! -f "$n/mark" ] || [ "$(ls -A "$n")" = mark ] || { echo "moved into $n: $(ls -A "$n")"; false; }
  done
  [ "$(grep -lx old "$bk"/vetdd-"$ts"*/SKILL.md | wc -l | tr -d ' ')" -eq 1 ]
}

@test "i48: another installer creating --dest before the final move: it stops, never nests the copy" {
  mkdir -p "$DEST" && old_skill "$DEST/SKILL.md"
  local mb; mb="$(shim_final_move "mkdir -p '$DEST' && echo other > '$DEST/other.txt'")"
  PATH="$mb:$PATH" run "$INSTALL"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ ! -e "$DEST/vetdd" ] && [ "$(ls -A "$DEST")" = other.txt ]
  local b; b="$(ls -d "$CLAUDE_CONFIG_DIR"/skills-backup/vetdd-* | head -1)"
  grep -qx old "$b/SKILL.md"
  [[ "$output" == *"$b"* ]]
}

@test "i48: interrupted (Ctrl-C) between the backup and the final move, the old install comes back" {
  mkdir -p "$DEST" && old_skill "$DEST/SKILL.md"
  local mb; mb="$(shim_final_move 'kill -INT $PPID; kill -INT $$')"
  PATH="$mb:$PATH" run "$INSTALL"
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  grep -qx old "$DEST/SKILL.md"
  [ -z "$(ls -A "$CLAUDE_CONFIG_DIR/skills" | grep -v '^vetdd$')" ]
}

@test "i48: a TERM while the old install is being moved to the backup still puts it back" {
  mkdir -p "$DEST" && old_skill "$DEST/SKILL.md"
  local mb="$BATS_TEST_TMPDIR/termbin" realmv; realmv="$(command -v mv)"
  mkdir -p "$mb"
  printf '#!/bin/sh\ncase "$*" in */.vetdd-backup.*) kill -TERM $PPID ;; esac\nexec "%s" "$@"\n' "$realmv" > "$mb/mv"
  chmod +x "$mb/mv"
  PATH="$mb:$PATH" run "$INSTALL"
  [ "$status" -eq 143 ] || { echo "$output"; false; }
  grep -qx old "$DEST/SKILL.md"
  [[ "$output" == *"moved the old install back"* ]]
}

@test "i48: putting the old install back across file systems never nests it in a directory that appeared" {
  mkdir -p "$DEST" && old_skill "$DEST/SKILL.md"
  local fb="$BATS_TEST_TMPDIR/restorebin" realmv realperl; realmv="$(command -v mv)"; realperl="$(command -v perl)"
  mkdir -p "$fb"
  # perl: the final move fails, and renaming the backup back fails as across file systems.
  printf '#!/bin/sh\ncase "$3" in */.vetdd-install.*|*/skills-backup/vetdd-*) exit 1 ;; esac\nexec "%s" "$@"\n' "$realperl" > "$fb/perl"
  # mv: copying the backup back, it finds a directory just made at --dest.
  printf '#!/bin/sh\ncase "$1" in */skills-backup/vetdd-*) mkdir -p "%s" && : > "%s/other" ;; esac\nexec "%s" "$@"\n' "$DEST" "$DEST" "$realmv" > "$fb/mv"
  chmod +x "$fb/perl" "$fb/mv"
  PATH="$fb:$PATH" run "$INSTALL"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(ls -A "$DEST")" = other ]
  local kept; kept="$(printf '%s\n' "$output" | sed -n 's/^install.sh: the old install stays at //p')"
  [ -n "$kept" ] && grep -qx old "$kept/SKILL.md"
}

# shim_dies_after <case pattern on the arguments>: a perl that does the move, then is stopped by a
# Ctrl-C (to itself and to install.sh) when its arguments match.
shim_dies_after() {
  local fb="$BATS_TEST_TMPDIR/diebin" realperl; realperl="$(command -v perl)"
  mkdir -p "$fb"
  printf '#!/bin/sh\n"%s" "$@"; r=$?\ncase "$*" in %s) kill -INT $PPID; kill -INT $$ ;; esac\nexit $r\n' "$realperl" "$1" > "$fb/perl"
  chmod +x "$fb/perl"
  printf '%s' "$fb"
}

@test "i48: a Ctrl-C that stops the final move after it was made leaves the new copy installed" {
  mkdir -p "$DEST" && old_skill "$DEST/SKILL.md"
  local fb; fb="$(shim_dies_after '*/.vetdd-install.*')"
  PATH="$fb:$PATH" run "$INSTALL"
  [ "$status" -eq 130 ] || { echo "$output"; false; }
  same_as_tracked "$DEST"
  [[ "$output" != *"cannot put"* ]]
}

@test "i48: a Ctrl-C that stops the rename to the backup name after it was made still puts the old install back" {
  mkdir -p "$DEST" && old_skill "$DEST/SKILL.md"
  local fb; fb="$(shim_dies_after '*/.vetdd-backup.*/skills-backup/vetdd-*')"
  PATH="$fb:$PATH" run "$INSTALL"
  [ "$status" -eq 130 ] || { echo "$output"; false; }
  grep -qx old "$DEST/SKILL.md"
  [[ "$output" == *"moved the old install back"* ]]
}

# fake_linux_acl <getfacl output>: a uname that says Linux and a getfacl that prints <getfacl output>
# (or fails, when it is "fail").
fake_linux_acl() {
  local fb="$BATS_TEST_TMPDIR/aclbin"
  mkdir -p "$fb"
  printf '#!/bin/sh\necho Linux\n' > "$fb/uname"
  if [ "$1" = fail ]; then printf '#!/bin/sh\nexit 1\n' > "$fb/getfacl"
  else printf '#!/bin/sh\ncat <<"X"\n%s\nX\n' "$1" > "$fb/getfacl"; fi
  chmod +x "$fb/uname" "$fb/getfacl"
  printf '%s' "$fb"
}

@test "i48: Linux ACL: a named user that may write is refused, unless the mask takes the write away" {
  mkdir -p "$BATS_TEST_TMPDIR/la"
  local fb
  fb="$(fake_linux_acl "$(printf '# group: 99999\nuser::rwx\nuser:4242:rwx\ngroup::r-x\nother::r-x')")"
  PATH="$fb:$PATH" run "$INSTALL" --dest "$BATS_TEST_TMPDIR/la/vetdd"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  fb="$(fake_linux_acl "$(printf '# group: 99999\nuser::rwx\nuser:4242:rwx\t#effective:r-x\ngroup::r-x\nmask::r-x\nother::r-x')")"
  PATH="$fb:$PATH" run "$INSTALL" --dest "$BATS_TEST_TMPDIR/la/vetdd"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "i48: Linux ACL: a default entry that lets others write what is made inside is refused" {
  mkdir -p "$BATS_TEST_TMPDIR/la"
  local fb
  fb="$(fake_linux_acl "$(printf '# group: 99999\nuser::rwx\ngroup::r-x\nother::r-x\ndefault:user::rwx\ndefault:group::r-x\ndefault:other::rwx')")"
  PATH="$fb:$PATH" run "$INSTALL" --dest "$BATS_TEST_TMPDIR/la/vetdd"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  fb="$(fake_linux_acl "$(printf '# group: 99999\nuser::rwx\ngroup::r-x\nother::r-x\ndefault:user::rwx\ndefault:group::rwx\ndefault:other::r-x')")"
  PATH="$fb:$PATH" run "$INSTALL" --dest "$BATS_TEST_TMPDIR/la/vetdd"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "i48: Linux ACL: a getfacl that fails is not taken as no ACL" {
  mkdir -p "$BATS_TEST_TMPDIR/la"
  local fb; fb="$(fake_linux_acl fail)"
  PATH="$fb:$PATH" run "$INSTALL" --dest "$BATS_TEST_TMPDIR/la/vetdd"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "i48: macOS ACL: a GNU ls earlier in PATH (no -e) does not hide an ACL that lets others write" {
  [ "$(uname)" = Darwin ] || skip "macOS ACLs"
  mkdir -p "$BATS_TEST_TMPDIR/acl" "$BATS_TEST_TMPDIR/gnubin"
  chmod +a "everyone allow add_file,add_subdirectory" "$BATS_TEST_TMPDIR/acl"
  printf '#!/bin/sh\nfor a; do case "$a" in -*e*) echo "ls: invalid option -- e" >&2; exit 2 ;; esac; done\nexec /bin/ls "$@"\n' > "$BATS_TEST_TMPDIR/gnubin/ls"
  chmod +x "$BATS_TEST_TMPDIR/gnubin/ls"
  PATH="$BATS_TEST_TMPDIR/gnubin:$PATH" run "$INSTALL" --dest "$BATS_TEST_TMPDIR/acl/vetdd"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "i48: macOS ACL: an entry that lets others take ownership (chown) is refused" {
  [ "$(uname)" = Darwin ] || skip "macOS ACLs"
  mkdir -p "$BATS_TEST_TMPDIR/acl"
  chmod +a "everyone allow chown" "$BATS_TEST_TMPDIR/acl"
  run "$INSTALL" --dest "$BATS_TEST_TMPDIR/acl/vetdd"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "i48: .. after a link in --dest is taken physically: nothing is made where it was not checked" {
  mkdir -p "$BATS_TEST_TMPDIR/shared/sub" "$BATS_TEST_TMPDIR/b" && chmod 777 "$BATS_TEST_TMPDIR/shared"
  ln -s "$BATS_TEST_TMPDIR/shared/sub" "$BATS_TEST_TMPDIR/l"
  run "$INSTALL" --dest "$BATS_TEST_TMPDIR/l/../b/vetdd"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ ! -e "$BATS_TEST_TMPDIR/shared/b" ] && [ ! -e "$BATS_TEST_TMPDIR/b/vetdd" ]
}

@test "i48: a --dest that is a plain file is refused, untouched" {
  mkdir -p "$CLAUDE_CONFIG_DIR/skills" && printf 'notes\n' > "$DEST"
  run "$INSTALL"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ -f "$DEST" ] && grep -qx notes "$DEST"
  [ ! -e "$CLAUDE_CONFIG_DIR/skills-backup" ]
}

@test "i48: elsewhere than Linux and macOS a getfacl of another kind does not refuse every directory" {
  local fb="$BATS_TEST_TMPDIR/bsdbin"
  mkdir -p "$fb"
  printf '#!/bin/sh\necho FreeBSD\n' > "$fb/uname"
  printf '#!/bin/sh\necho "getfacl: illegal option -- p" >&2\nexit 1\n' > "$fb/getfacl"
  chmod +x "$fb/uname" "$fb/getfacl"
  PATH="$fb:$PATH" run "$INSTALL" --dest "$BATS_TEST_TMPDIR/bsd/vetdd"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "i48: a second Ctrl-C while the old install is put back does not cut the putting back short" {
  mkdir -p "$DEST" && old_skill "$DEST/SKILL.md"
  local fb="$BATS_TEST_TMPDIR/twicebin" realmv realperl; realmv="$(command -v mv)"; realperl="$(command -v perl)"
  mkdir -p "$fb"
  printf '#!/bin/sh\ncase "$*" in */.vetdd-backup.*) kill -INT $PPID ;; esac\nexec "%s" "$@"\n' "$realmv" > "$fb/mv"
  printf '#!/bin/sh\ncase "$3" in */skills-backup/vetdd-*) kill -INT $PPID ;; esac\nexec "%s" "$@"\n' "$realperl" > "$fb/perl"
  chmod +x "$fb/mv" "$fb/perl"
  PATH="$fb:$PATH" run "$INSTALL"
  [ "$status" -eq 130 ] || { echo "$output"; false; }
  grep -qx old "$DEST/SKILL.md"
  [[ "$output" == *"moved the old install back"* ]]
  [ -z "$(ls -A "$CLAUDE_CONFIG_DIR/skills" | grep -v '^vetdd$')" ]
}

@test "i48: a backup mv that fails part way does not report its partial copy as the old install" {
  mkdir -p "$DEST" && old_skill "$DEST/SKILL.md"
  local fb="$BATS_TEST_TMPDIR/partbin"
  mkdir -p "$fb"
  printf '#!/bin/sh\ncase "$*" in */.vetdd-backup.*) mkdir -p "$2" && : > "$2/partial"; exit 1 ;; esac\nexec "%s" "$@"\n' "$(command -v mv)" > "$fb/mv"
  chmod +x "$fb/mv"
  PATH="$fb:$PATH" run "$INSTALL"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  grep -qx old "$DEST/SKILL.md"
  [[ "$output" != *"the old install stays at"* ]]
  [[ "$output" == *"partial copy"* ]]
}

# fake_upg <members> <other primary user, or empty>: an id that reports a group named after the user
# (the gid of $BATS_TEST_TMPDIR/grp), and a getent that lists <members> in it and, if given, another
# user whose primary group it is.
fake_upg() {
  local fb="$BATS_TEST_TMPDIR/upgbin" g realid; realid="$(command -v id)"
  g="$(gid_of "$BATS_TEST_TMPDIR/grp")"
  mkdir -p "$fb"
  printf '#!/bin/sh\ncase "$1" in -un|-gn) echo me ;; -g) echo %s ;; *) exec "%s" "$@" ;; esac\n' "$g" "$realid" > "$fb/id"
  printf '#!/bin/sh\ncase "$1" in group) echo "me:x:%s:%s" ;; passwd) echo "me:x:1:%s::/:/bin/sh"; [ -z "%s" ] || echo "%s:x:2:%s::/:/bin/sh" ;; esac\n' \
    "$g" "$1" "$g" "$2" "$2" "$g" > "$fb/getent"
  chmod +x "$fb/id" "$fb/getent"
  printf '%s' "$fb"
}

@test "i48: a group-writable parent is accepted when the group is the user's own with no other member" {
  mkdir -p "$BATS_TEST_TMPDIR/grp" && chmod 775 "$BATS_TEST_TMPDIR/grp"
  local fb; fb="$(fake_upg "" "")"
  PATH="$fb:$PATH" run "$INSTALL" --dest "$BATS_TEST_TMPDIR/grp/vetdd"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "i48: a group-writable parent is refused when the user's own group has another member" {
  mkdir -p "$BATS_TEST_TMPDIR/grp" && chmod 775 "$BATS_TEST_TMPDIR/grp"
  local fb; fb="$(fake_upg "me,eve" "")"
  PATH="$fb:$PATH" run "$INSTALL" --dest "$BATS_TEST_TMPDIR/grp/vetdd"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ ! -e "$BATS_TEST_TMPDIR/grp/vetdd" ]
}

@test "i48: a group-writable parent is refused when another user has the user's own group as primary" {
  mkdir -p "$BATS_TEST_TMPDIR/grp" && chmod 775 "$BATS_TEST_TMPDIR/grp"
  local fb; fb="$(fake_upg "" eve)"
  PATH="$fb:$PATH" run "$INSTALL" --dest "$BATS_TEST_TMPDIR/grp/vetdd"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "i48: a group-writable parent is refused when the group's members cannot be checked (no getent)" {
  mkdir -p "$BATS_TEST_TMPDIR/grp" && chmod 775 "$BATS_TEST_TMPDIR/grp"
  local fb; fb="$(fake_upg "" "")"
  rm "$fb/getent"
  PATH="$fb:$(without getent)" run "$INSTALL" --dest "$BATS_TEST_TMPDIR/grp/vetdd"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}
