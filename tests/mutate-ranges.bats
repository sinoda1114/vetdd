#!/usr/bin/env bats
# mutate-ranges.sh (#62 items 3 and 4): the value for Stryker's --mutate, the lines a slice added or
# changed in current line numbers, by git blame over throwaway commits of the slice's first before
# tree, its last passing after tree, and the working tree.

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  make_repo
  mkdir -p src
  printf '%s\n' a1 a2 a3 a4 a5 > src/a.js
  git add -A && git commit -q -m product
}

mr() { "$SCRIPTS/mutate-ranges.sh" "$@"; }
# A red run (exit 1 is target_failure) and a green run of the slice, test.sh its oracle file.
red() { ev "$1" before --seam unit --oracle-version v1 --oracle-file test.sh -- false >/dev/null 2>&1; }
green() { ev "$1" after -- true >/dev/null 2>&1; }

# --- 1. one slice -------------------------------------------------------------------------------

@test "one slice: prints file:a-b over the lines it added or changed, in current numbers" {
  red s1
  printf '%s\n' a1 a2 B3 B4 b4x a5 > src/a.js
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:3-5" ]
}

@test "the last accepted passing after counts: a later rejected after and later edits do not" {
  red s1
  printf '%s\n' a1 X2 a3 a4 a5 > src/a.js
  green s1
  printf '%s\n' a1 X2 a3 X4 a5 > src/a.js
  green s1
  printf '%s\n' a1 X2 a3 X4 X5 > src/a.js
  ev s1 after -- false >/dev/null 2>&1 || true
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:2-2,src/a.js:4-4" ]
}

# --- 2. a later slice moves the lines -----------------------------------------------------------

@test "a later slice adds lines above and inside: the first slice's ranges move and leave its lines out" {
  red s1
  printf '%s\n' a1 a2 s1x s1y a3 a4 a5 > src/a.js
  green s1
  red s2
  printf '%s\n' n1 n2 a1 a2 s1x n3 s1y a3 a4 a5 > src/a.js
  green s2
  # An edit no slice recorded belongs to neither.
  printf '%s\n' n1 n2 a1 a2 s1x n3 s1y a3 a4 a5 late > src/a.js
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:5-5,src/a.js:7-7" ]
  run --separate-stderr mr s2
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:1-2,src/a.js:6-6" ]
}

# --- 3. two slices in one file, nothing committed -----------------------------------------------

@test "two slices editing one file in single mode, uncommitted: each gets only its own lines" {
  red s1
  printf '%s\n' a1 X2 a3 a4 a5 > src/a.js
  green s1
  red s2
  printf '%s\n' a1 X2 a3 X4 a5 > src/a.js
  green s2
  # A diff from the base would give both lines to each slice.
  [ "$(git diff -U0 HEAD -- src/a.js | grep -c '^+[^+]')" = "2" ]
  run --separate-stderr mr s1
  [ "$output" = "src/a.js:2-2" ]
  run --separate-stderr mr s2
  [ "$output" = "src/a.js:4-4" ]
}

# --- 4. an untracked new file -------------------------------------------------------------------

@test "an untracked new product file of the slice: all of its lines" {
  red s1
  printf '%s\n' n1 n2 n3 > src/new.js
  printf '%s\n' a1 a2 a3 a4 a5 a6 > src/a.js
  green s1
  [ "$(git status --porcelain -- src/new.js)" = "?? src/new.js" ]
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:6-6,src/new.js:1-3" ]
}

# --- 5. which files -----------------------------------------------------------------------------

@test "without --file: every file the slice changed except its oracle files and .vetdd/" {
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  printf '%s\n' b1 b2 > src/b.js
  printf 'echo stronger\n' >> test.sh
  mkdir -p .vetdd/notes && printf 'n\n' > .vetdd/notes/x.js
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:1-1,src/b.js:1-2" ]
}

@test "an oracle file of an earlier oracle version is still left out" {
  printf 'echo t2\n' > t2.sh && git add t2.sh && git commit -q -m t2
  ev s1 before --seam unit --oracle-version v1 --oracle-file t2.sh -- false >/dev/null 2>&1
  printf 'echo t2 changed\n' > t2.sh
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  ev s1 calibration --oracle-version v2 --oracle-file test.sh -- false >/dev/null 2>&1
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:1-1" ]
}

@test "--file limits the output to the files named, in the order named, once each" {
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  printf '%s\n' b1 b2 > src/b.js
  green s1
  run --separate-stderr mr s1 --file src/b.js
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/b.js:1-2" ]
  run --separate-stderr mr s1 --file src/b.js --file src/a.js --file ./src/b.js
  [ "$output" = "src/b.js:1-2,src/a.js:1-1" ]
}

@test "--file of an oracle file, a missing file, or a file outside the repository: exit 2" {
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  green s1
  run --separate-stderr mr s1 --file test.sh
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"test.sh"*"oracle file"* ]] || { echo "$stderr"; false; }
  run --separate-stderr mr s1 --file src/none.js
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"src/none.js"* ]]
  printf 'x\n' > "$BATS_TEST_TMPDIR/out.js"
  run --separate-stderr mr s1 --file "$BATS_TEST_TMPDIR/out.js"
  [ "$status" -eq 2 ]
  run --separate-stderr mr s1 --file
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "--file of a gitignored file: exit 2, it is in no tree" {
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  green s1
  mkdir -p ignored && printf 'x\n' > ignored/i.js
  run --separate-stderr mr s1 --file ignored/i.js
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"ignored/i.js"* ]]
}

@test "--file of a file the slice did not change: nothing printed, a note naming it, exit 3" {
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  green s1
  run --separate-stderr mr s1 --file sub/keep.txt
  [ "$status" -eq 3 ]
  [ -z "$output" ]
  [[ "$stderr" == *"sub/keep.txt"* ]]
}

@test "from a subdirectory: paths are relative to it, and a changed file outside it is left out with a note" {
  mkdir -p lib && printf 'z1\n' > lib/z.js && git add lib && git commit -q -m lib
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  printf '%s\n' z1 z2 > lib/z.js
  green s1
  cd src
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "a.js:1-1" ]
  [[ "$stderr" == *"lib/z.js"* ]]
  run --separate-stderr mr s1 --file a.js
  [ "$output" = "a.js:1-1" ]
}

# --- 6. deletions -------------------------------------------------------------------------------

@test "a deletion-only change: no range for that file, and a note on stderr naming it" {
  printf '%s\n' c1 c2 > src/c.js && git add -A && git commit -q -m c
  red s1
  printf '%s\n' a1 a2 a4 a5 > src/a.js
  rm "$REPO/src/c.js"
  printf '%s\n' b1 > src/b.js
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/b.js:1-1" ]
  [[ "$stderr" == *"src/a.js"* ]] || { echo "$stderr"; false; }
  [[ "$stderr" == *"src/c.js"* ]] || { echo "$stderr"; false; }
}

@test "only deletions: nothing printed, exit 3, the file named" {
  red s1
  printf '%s\n' a1 a2 a4 a5 > src/a.js
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 3 ]
  [ -z "$output" ]
  [[ "$stderr" == *"src/a.js"* ]]
}

@test "a file the slice changed and a later edit moved away: a note that says to name its new path" {
  red s1
  printf '%s\n' a1 X2 a3 a4 a5 > src/a.js
  printf '%s\n' b1 b2 > src/b.js
  green s1
  git mv -f src/a.js src/moved.js 2>/dev/null || mv "$REPO/src/a.js" "$REPO/src/moved.js"
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/b.js:1-2" ]
  [[ "$stderr" == *"src/a.js"*"--file"* ]] || { echo "$stderr"; false; }
  run --separate-stderr mr s1 --file src/moved.js
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/moved.js:2-2" ]
}

# --- 7. a test-only slice -----------------------------------------------------------------------

@test "a slice with no product change: prints nothing, exit 3, points to the mutation note" {
  red s1
  printf 'echo stronger\n' >> test.sh
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 3 ]
  [ -z "$output" ]
  [[ "$stderr" == *"audit-note.sh s1 --kind mutation --not-applicable"* ]] || { echo "$stderr"; false; }
  [[ "$stderr" == *"modes/test.md"* ]]
}

# --- 8. errors ----------------------------------------------------------------------------------

@test "a slice without evidence, without a before, or without a passing after: exit 2" {
  run --separate-stderr mr s1
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"s1"* ]]
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"before"* ]] || { echo "$stderr"; false; }
  red s2
  ev s2 after -- false >/dev/null 2>&1 || true
  run --separate-stderr mr s2
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"after"* ]] || { echo "$stderr"; false; }
  [ -z "$output" ]
}

@test "a tree object that is gone (git gc) or a malformed tree hash: exit 2" {
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  green s1
  tamper s1 '.runs[0].tree.tree_hash = "1234567890abcdef1234567890abcdef12345678"'
  run --separate-stderr mr s1
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"1234567890abcdef1234567890abcdef12345678"* ]] || { echo "$stderr"; false; }
  [[ "$stderr" == *"gc"* ]]
  tamper s1 '.runs[0].tree.tree_hash = "HEAD"'
  run --separate-stderr mr s1
  [ "$status" -eq 2 ]
  tamper s1 '.runs[0].tree.tree_hash = null'
  run --separate-stderr mr s1
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "usage errors: no slice, a bad slice id, an unknown argument, outside a repository: exit 2" {
  run --separate-stderr mr
  [ "$status" -eq 2 ]
  run --separate-stderr mr ../x
  [ "$status" -eq 2 ]
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  green s1
  run --separate-stderr mr s1 --bogus
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--bogus"* ]]
  cd "$BATS_TEST_TMPDIR"
  run --separate-stderr mr s1
  [ "$status" -eq 2 ]
}

@test "a meta.json that is not the slice's evidence: exit 2" {
  mkdir -p .vetdd/evidence/s1
  printf 'not json\n' > .vetdd/evidence/s1/meta.json
  run --separate-stderr mr s1
  [ "$status" -eq 2 ]
}

# --- 9. nothing changes -------------------------------------------------------------------------

@test "the throwaway commits leave no ref and change neither HEAD, the index, nor the working tree" {
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  printf '%s\n' n1 > src/new.js
  green s1
  printf 'staged\n' > staged.js && git add staged.js
  local st1 st2 idx1 idx2 refs1 refs2 head1 head2 log1 log2
  st1="$(git status --porcelain=v1 --untracked-files=all)"
  idx1="$(cksum < .git/index)"
  refs1="$(git for-each-ref --format='%(refname) %(objectname)')"
  head1="$(git rev-parse HEAD; git symbolic-ref HEAD)"
  log1="$(git reflog --all | wc -l)"
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  idx2="$(cksum < .git/index)"
  st2="$(git status --porcelain=v1 --untracked-files=all)"
  refs2="$(git for-each-ref --format='%(refname) %(objectname)')"
  head2="$(git rev-parse HEAD; git symbolic-ref HEAD)"
  log2="$(git reflog --all | wc -l)"
  [ "$idx1" = "$idx2" ]
  [ "$st1" = "$st2" ]
  [ "$refs1" = "$refs2" ]
  [ "$head1" = "$head2" ]
  [ "$log1" = "$log2" ]
  [ -z "$(git stash list)" ]
}

@test "works without a git identity, with an ignore-revs file configured, and with commit signing on" {
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  green s1
  git config --global --unset user.name
  git config --global --unset user.email
  git config --global commit.gpgsign true
  git config --global gpg.program false
  git config --global blame.ignoreRevsFile .no-such-file
  run --separate-stderr env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL \
    EMAIL= "$SCRIPTS/mutate-ranges.sh" s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:1-1" ]
}

# --- 10. paths ----------------------------------------------------------------------------------

@test "a path with spaces is printed as is" {
  red s1
  printf '%s\n' m1 m2 > "src/my file.js"
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/my file.js:1-2" ]
  run --separate-stderr mr s1 --file "src/my file.js"
  [ "$output" = "src/my file.js:1-2" ]
}

@test "a path Stryker would split or read as a pattern is refused with a message: exit 2" {
  local p
  for p in 'src/a,b.js' 'src/[x].js' 'src/x*.js' 'src/x:1-2.js' 'src/{x}.js' '!x.js'; do
    rm -rf "$REPO/.vetdd"
    red s1
    printf '%s\n' q1 > "$p"
    green s1
    run --separate-stderr mr s1
    [ "$status" -eq 2 ] || { echo "$p: $status $output $stderr"; false; }
    [ -z "$output" ]
    [[ "$stderr" == *"$p"* ]] || { echo "$stderr"; false; }
    rm -f -- "$REPO/$p"
  done
  rm -rf "$REPO/.vetdd"
  red s1
  printf '%s\n' q1 > 'src/a,b.js'
  green s1
  run --separate-stderr mr s1
  [[ "$stderr" == *"comma"* ]] || { echo "$stderr"; false; }
}

@test "a symbolic link the slice added is not a file to mutate" {
  red s1
  printf '%s\n' X1 a2 a3 a4 a5 > src/a.js
  ln -s a.js src/link.js
  green s1
  run --separate-stderr mr s1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$output" = "src/a.js:1-1" ]
}

# --- docs ---------------------------------------------------------------------------------------

@test "the script's header names its usage and exit codes" {
  sed -n 2,30p "$SCRIPTS/mutate-ranges.sh" | grep -q 'Usage: mutate-ranges.sh <slice-id> \[--file <path>\]'
  sed -n 2,30p "$SCRIPTS/mutate-ranges.sh" | grep -q 'Exit 0'
  sed -n 2,30p "$SCRIPTS/mutate-ranges.sh" | grep -q ' 3 '
}

@test "test mode takes the ranges from mutate-ranges.sh, keeps the widening rule, and drops git diff -U0" {
  local doc="$SCRIPTS/../modes/test.md"
  sed -n '/^### Mutation/,/^## /p' "$doc" | grep -q 'mutate-ranges.sh <slice>'
  ! grep -q 'git diff -U0' "$doc" || false
  sed -n '/^### Mutation/,/^## /p' "$doc" | grep -q 'widen'
  sed -n '/^### Mutation/,/^## /p' "$doc" | grep -q "Attention"
  sed -n '/^## Close/,/^## Traps/p' "$doc" | grep -q 'mutate-ranges.sh'
}

@test "swarm and arena Close run each slice's mutation audit on mutate-ranges.sh over the integrated tree" {
  grep -q 'mutate-ranges.sh <slice>' "$SCRIPTS/../parallel/swarm.md"
  grep -q 'mutate-ranges.sh' "$SCRIPTS/../parallel/arena.md"
}
