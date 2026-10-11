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

@test "swarm.md integrates each unit with evidence.sh integrated --rerun" {
  grep -q 'integrated --rerun' "$SCRIPTS/../parallel/swarm.md"
}

# --- review round 1 ----------------------------------------------------------------------------------

@test "r1: remove --keep-branch keeps a merged branch, so a unit that goes red after its merge can be found again" {
  WT add sa >/dev/null
  (cd "$WTROOT/sa" && unit sa test.sh value.txt 42)
  git merge -q --no-edit vetdd/sa
  run WT remove sa --keep-branch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  git rev-parse -q --verify refs/heads/vetdd/sa >/dev/null
  [ -f .vetdd/evidence/sa/meta.json ]
  grep -q 'remove <slice> --keep-branch' "$SCRIPTS/../parallel/swarm.md"
  grep -q 'git branch -d vetdd/<slice>' "$SCRIPTS/../parallel/swarm.md"
}

@test "r1: --link takes a trailing slash, and the link is never shown as untracked even with a directory-only ignore rule" {
  mkdir -p ignored/dep
  run WT add sa --link ignored/
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -L "$WTROOT/sa/ignored" ]
  [ -z "$(git -C "$WTROOT/sa" status --porcelain)" ]
}

@test "r1: a worker cannot hide uncommitted work by writing the list of links" {
  mkdir -p ignored
  WT add sa --link ignored >/dev/null
  # The list lives in the worktree's git directory; an entry that is not a link add made counts as work.
  printf 'value.txt\n' >> "$(git -C "$WTROOT/sa" rev-parse --absolute-git-dir)/vetdd-links"
  printf 'wip\n' > "$WTROOT/sa/value.txt"
  run WT remove sa
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted"* ]]
}

# --- review round 2 ----------------------------------------------------------------------------------

@test "r2: --rerun runs the command the parent gave worktree.sh add, never the one the worker recorded" {
  WT add sa -- sh test.sh >/dev/null
  (cd "$WTROOT/sa" && unit sa test.sh value.txt 42)
  git merge -q --no-edit vetdd/sa && WT remove sa --keep-branch >/dev/null
  tamper sa '(.runs[]).cmd = ["sh", "-c", "touch pwned"]'
  run ev sa integrated --rerun
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"sh test.sh"* ]]
  [ ! -e pwned ]
  [ "$(mq sa '[.runs[] | select(.kind == "integrated")] | last | .cmd | join(" ")')" = "sh test.sh" ]
}

@test "r2: --rerun without a command recorded by worktree.sh add is a usage error" {
  unit sa test.sh value.txt 42
  run ev sa integrated --rerun
  [ "$status" -eq 2 ]
  [[ "$output" == *"worktree.sh add"* ]]
  run ev sa integrated --rerun -- sh test.sh
  [ "$status" -eq 2 ]
  run ev sa before --rerun
  [ "$status" -eq 2 ]
}

@test "r2: --rerun of a unit whose green run recorded a test report needs --test-report (rule 9b keeps working)" {
  WT add sa -- sh test.sh >/dev/null
  (cd "$WTROOT/sa" && unit sa test.sh value.txt 42)
  git merge -q --no-edit vetdd/sa && WT remove sa --keep-branch >/dev/null
  tamper sa '(.runs[] | select(.kind == "after")) += {tests: {format: "jest-json", status: "ok", passed: 1, failed: 0, skipped: 0, todo: 0, other: 0, total: 1, sha256: "x"}}'
  run ev sa integrated --rerun
  [ "$status" -eq 2 ]
  [[ "$output" == *"--test-report"* ]]
  mkdir -p .vetdd/reports
  run ev sa integrated --rerun --test-report jest-json:.vetdd/reports/sa.json
  [ "$(mq sa '[.runs[] | select(.kind == "integrated")] | last | .cmd | join(" ")')" = "sh test.sh" ]
}

@test "r2: --link refuses the same path twice, or one inside another" {
  mkdir -p ignored/inner
  run WT add sa --link ignored --link ignored
  [ "$status" -eq 2 ]
  run WT add sa --link ignored --link ignored/inner
  [ "$status" -eq 2 ]
  [ ! -e ignored/inner/inner ] && [ ! -L ignored/inner ]
  [ ! -e "$WTROOT/sa" ]
}

@test "r2: the exclude rule for a link is added once and with its special characters escaped" {
  mkdir -p 'ignored'
  WT add sa --link ignored >/dev/null
  WT add sb --link ignored >/dev/null
  [ "$(grep -cx '/ignored' .git/info/exclude)" -le 1 ]
}

@test "r2: remove refuses a worktree whose HEAD left vetdd/<slice>, so commits off the branch are not lost" {
  WT add sa >/dev/null
  (cd "$WTROOT/sa" && git checkout -q --detach && printf 'x\n' > value.txt && git commit -qam off-branch)
  run WT remove sa
  [ "$status" -eq 1 ]
  [[ "$output" == *"vetdd/sa"* ]]
  [ -d "$WTROOT/sa" ]
}

@test "r2: remove refuses evidence, artifacts, or notes in the worktree that are links" {
  WT add sa >/dev/null
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere" "$WTROOT/sa/.vetdd/evidence"
  ln -s "$BATS_TEST_TMPDIR/elsewhere" "$WTROOT/sa/.vetdd/evidence/sa"
  run WT remove sa
  [ "$status" -eq 1 ]
  [ ! -L .vetdd/evidence/sa ]
}

@test "r2: docs: add takes the unit's command, Close passes --test-report, the link is shared, and select.md runs before step 2" {
  local sw="$SCRIPTS/../parallel/swarm.md"
  grep -q 'worktree.sh" add <slice> \[--link node_modules\] -- <' "$sw"
  grep -q -- '--rerun \[--test-report' "$sw"
  grep -qi 'cache' "$sw"
  grep -q 'artifacts' "$sw"
  ! grep -q 'Answer two questions after the oracle is agreed' "$SCRIPTS/../parallel/select.md" || false
}

@test "r2 security: remove refuses a worktree whose .git no longer points at its own git directory, and runs no git there" {
  WT add sa >/dev/null
  mkdir -p "$BATS_TEST_TMPDIR/fakegit"
  printf 'gitdir: %s\n' "$BATS_TEST_TMPDIR/fakegit" > "$WTROOT/sa/.git"
  run WT remove sa
  [ "$status" -eq 1 ]
  [[ "$output" == *".git"* ]]
  [ -d "$WTROOT/sa" ]
}

@test "r2 security: the parent never runs git or check-evidence inside a worker's worktree (swarm.md)" {
  ! grep -q 'cd <worktree> && "\$VETDD/scripts/check-evidence.sh"' "$SCRIPTS/../parallel/swarm.md" || false
}

@test "r2 security: any link under the worktree's .vetdd stops remove; evidence.sh refuses a linked runs directory" {
  WT add sa >/dev/null
  (cd "$WTROOT/sa" && unit sa test.sh value.txt 42)
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere"
  rm -rf "$WTROOT/sa/.vetdd/evidence/sa/runs" && ln -s "$BATS_TEST_TMPDIR/elsewhere" "$WTROOT/sa/.vetdd/evidence/sa/runs"
  run WT remove sa
  [ "$status" -eq 1 ]
  [ ! -e .vetdd/evidence/sa ]
  mkdir -p .vetdd/evidence/sb && ln -s "$BATS_TEST_TMPDIR/elsewhere" .vetdd/evidence/sb/runs
  run ev sb before -- sh test.sh
  [ "$status" -eq 2 ]
  [ -z "$(ls "$BATS_TEST_TMPDIR/elsewhere")" ]
}

@test "r2 security: add refuses a <repo>.vetdd-wt that is a link or that others can write, and makes it private" {
  mkdir -p "$BATS_TEST_TMPDIR/other"
  ln -s "$BATS_TEST_TMPDIR/other" "$WTROOT"
  run WT add sa
  [ "$status" -eq 1 ]
  rm "$WTROOT" && mkdir -m 777 "$WTROOT" && chmod 777 "$WTROOT"
  run WT add sa
  [ "$status" -eq 1 ]
  rmdir "$WTROOT"
  run WT add sa
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ls -ld "$WTROOT" | cut -c1-10)" = "drwx------" ]
}
