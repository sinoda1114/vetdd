#!/usr/bin/env bats
# worktree.sh (Phase 6, swarm): one worker per unit in its own worktree outside the repository
# (../<repo>.vetdd-wt/<slice>, branch vetdd/<slice>). remove brings the worker's evidence, verify
# artifacts, and notes back into the main repository (never overwriting a different file) before the
# worktree goes, so check-evidence on the integrated tree sees every slice.

load test_helper

WT() { "$SCRIPTS/worktree.sh" "$@"; }

setup() {
  make_repo
  printf '#!/bin/sh\necho "b is $(cat b.txt)"\n[ "$(cat b.txt)" = "7" ]\n' > tb.sh
  printf '0\n' > b.txt
  git add -A && git commit -qm unit-b
  WTROOT="$BATS_TEST_TMPDIR/repo.vetdd-wt"
}

# unit <slice> <oracle> <file> <good>: in the current directory, record red, fix, green, commit.
unit() {
  ev "$1" before --seam unit --oracle-version v1 --oracle-file "$2" -- sh "$2" >/dev/null 2>&1
  printf '%s\n' "$4" > "$3"
  ev "$1" after -- sh "$2" >/dev/null 2>&1
  git add "$3" && git commit -qm "fix $1"
}

@test "add makes a worktree beside the repository on branch vetdd/<slice> and prints its path" {
  run WT add sa
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "$(cd -P "$BATS_TEST_TMPDIR" && pwd -P)/repo.vetdd-wt/sa" ]
  [ "$(git -C "$WTROOT/sa" rev-parse --abbrev-ref HEAD)" = "vetdd/sa" ]
  [ "$(git -C "$WTROOT/sa" rev-parse HEAD)" = "$(git rev-parse HEAD)" ]
}

@test "add refuses an existing worktree or branch, and a bad slice id (usage, exit 2)" {
  WT add sa >/dev/null
  run WT add sa
  [ "$status" -eq 2 ]
  run WT add ../x
  [ "$status" -eq 2 ]
  run WT add
  [ "$status" -eq 2 ]
}

@test "add --link links an ignored directory of the main repository (node_modules)" {
  mkdir -p ignored/dep && printf 'x\n' > ignored/dep/f
  run WT add sa --link ignored
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -L "$WTROOT/sa/ignored" ]
  [ -f "$WTROOT/sa/ignored/dep/f" ]
  # A tracked path cannot be linked over.
  run WT add sb --link test.sh
  [ "$status" -eq 2 ]
}

@test "remove refuses a worktree with uncommitted work and keeps it" {
  WT add sa >/dev/null
  printf 'wip\n' > "$WTROOT/sa/value.txt"
  run WT remove sa
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted"* ]]
  [ -d "$WTROOT/sa" ]
}

@test "remove brings the worker's evidence, artifacts, and notes back, then removes the worktree and its merged branch" {
  WT add sa >/dev/null
  (cd "$WTROOT/sa" && unit sa test.sh value.txt 42 \
    && mkdir -p .vetdd/artifacts/feat/t1 .vetdd/notes && printf 'shot\n' > .vetdd/artifacts/feat/t1/out.txt \
    && printf 'why\n' > .vetdd/notes/sa-why.txt)
  git merge -q --no-edit vetdd/sa
  run WT remove sa
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f .vetdd/evidence/sa/meta.json ]
  [ -f .vetdd/evidence/sa/runs/001-before.log ]
  [ "$(cat .vetdd/artifacts/feat/t1/out.txt)" = shot ]
  [ "$(cat .vetdd/notes/sa-why.txt)" = why ]
  [ ! -e "$WTROOT/sa" ]
  ! git rev-parse -q --verify refs/heads/vetdd/sa >/dev/null || false
}

@test "remove keeps a branch that is not merged yet, and says so" {
  WT add sa >/dev/null
  (cd "$WTROOT/sa" && unit sa test.sh value.txt 42)
  run WT remove sa
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"not merged"* ]]
  git rev-parse -q --verify refs/heads/vetdd/sa >/dev/null
}

@test "remove never overwrites different evidence or a different file of the same name, and keeps the worktree" {
  WT add sa >/dev/null
  (cd "$WTROOT/sa" && unit sa test.sh value.txt 42)
  mkdir -p .vetdd/evidence/sa && printf '{}\n' > .vetdd/evidence/sa/meta.json
  run WT remove sa
  [ "$status" -eq 1 ]
  [[ "$output" == *"evidence"* ]]
  [ -d "$WTROOT/sa" ]
  rm -rf .vetdd/evidence/sa
  mkdir -p .vetdd/notes && printf 'mine\n' > .vetdd/notes/n.txt
  mkdir -p "$WTROOT/sa/.vetdd/notes" && printf 'theirs\n' > "$WTROOT/sa/.vetdd/notes/n.txt"
  run WT remove sa
  [ "$status" -eq 1 ]
  [ "$(cat .vetdd/notes/n.txt)" = mine ]
  [ -d "$WTROOT/sa" ]
}

@test "a swarm of two units: each worker's red and green, merged in series, integrated, and check-evidence OK" {
  WT add sa >/dev/null
  WT add sb >/dev/null
  (cd "$WTROOT/sa" && unit sa test.sh value.txt 42)
  (cd "$WTROOT/sb" && unit sb tb.sh b.txt 7)
  git merge -q --no-edit vetdd/sa
  WT remove sa >/dev/null
  git merge -q --no-edit vetdd/sb
  WT remove sb >/dev/null
  ev sa integrated -- sh test.sh >/dev/null 2>&1
  ev sb integrated -- sh tb.sh >/dev/null 2>&1
  run check sa sb
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "$(printf 'sa: OK\nsb: OK')" ]
}

@test "list names each worker worktree and its branch" {
  WT add sa >/dev/null
  WT add sb >/dev/null
  run WT list
  [ "$status" -eq 0 ]
  [[ "$output" == *"sa"*"vetdd/sa"* ]]
  [[ "$output" == *"sb"*"vetdd/sb"* ]]
}

@test "docs: swarm.md exists and is linked; select.md no longer blocks swarm; the agreement covers the parallel shape" {
  [ -f "$SCRIPTS/../parallel/swarm.md" ]
  grep -q 'worktree.sh add' "$SCRIPTS/../parallel/swarm.md"
  grep -q 'worktree.sh remove' "$SCRIPTS/../parallel/swarm.md"
  ! grep -q 'swarm.md` exist (Phase 6), any shape other than single' "$SCRIPTS/../parallel/select.md" || false
  grep -q 'arena' "$SCRIPTS/../parallel/select.md"
  grep -q 'parallel shape' "$SCRIPTS/../SKILL.md"
}
