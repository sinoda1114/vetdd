#!/usr/bin/env bats
# Phase 6, PR 2: arena. Runners build the same task in their own worktrees (lanes); arena-layout.sh
# gates each lane on its own green (check-evidence in a worktree the parent made, never the runner's),
# builds one judge layout per green lane with judge-layout.sh, and puts them side by side as c1..cN in
# a shuffled order kept in variants.json; references/arena-rubric.md is what the judge compares them by.

load test_helper

WT() { "$SCRIPTS/worktree.sh" "$@"; }
AL() { "$SCRIPTS/arena-layout.sh" "$@"; }

setup() {
  make_repo
  WTROOT="$BATS_TEST_TMPDIR/repo.vetdd-wt"
  BASE="$(git rev-parse HEAD)"
  OUT="$BATS_TEST_TMPDIR/arena"
}

# lane <slice> <value>: a runner's lane: design note, red, the change, a green when value is 42, a commit.
lane() {
  WT add "$1" -- sh test.sh >/dev/null
  (
    cd "$WTROOT/$1" || exit 1
    mkdir -p .vetdd/notes && printf '## Design\nlane %s sets value.txt\n' "$1" > ".vetdd/notes/$1-design.md"
    ev "$1" before --seam unit --oracle-version v1 --oracle-file test.sh -- sh test.sh >/dev/null 2>&1
    printf '%s\n' "$2" > value.txt
    ev "$1" after -- sh test.sh >/dev/null 2>&1 || true
    git add value.txt && git commit -qm "lane $1"
  )
  WT check "$1" >/dev/null && WT remove "$1" --keep-branch >/dev/null
}

@test "review makes a worktree of the parent's own from a lane's branch, with the lane's evidence and notes" {
  lane la 42
  run WT review la
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "$(cd -P "$BATS_TEST_TMPDIR" && pwd -P)/repo.vetdd-wt/la" ]
  [ "$(cat "$WTROOT/la/value.txt")" = 42 ]
  [ -f "$WTROOT/la/.vetdd/evidence/la/meta.json" ]
  [ -f "$WTROOT/la/.vetdd/notes/la-design.md" ]
  run WT remove la --keep-branch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "arena-layout puts every green lane side by side as c1..cN, keeps the order in variants.json, and leaves a red lane out" {
  lane la 42
  lane lb 42
  lane lc 7
  run AL --out "$OUT" --base "$BASE" la lb lc
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -d "$OUT/candidates/c1" ] && [ -d "$OUT/candidates/c2" ] && [ ! -e "$OUT/candidates/c3" ]
  [ "$(jq -r '[.[]] | sort | join(",")' "$OUT/variants.json")" = "la,lb" ]
  local l; for l in c1 c2; do
    grep -q '^+42$' "$OUT/candidates/$l/artifact/diff.patch"
    # The lane id is replaced with a neutral one inside the candidate.
    [ -f "$OUT/candidates/$l/evidence/cand${l#c}/meta.json" ]
    grep -q "lane cand${l#c} sets value.txt" "$OUT/candidates/$l/artifact/reply.md"
  done
  grep -qx 'lc: not green' "$OUT/gate.txt"
  [[ "$output" == *"arena-rubric.md"* ]]
  # The review worktrees are gone; the lanes' branches stay for the merge and the grafts.
  [ ! -e "$WTROOT/la" ] && [ ! -e "$WTROOT/lc" ]
  git rev-parse -q --verify refs/heads/vetdd/la >/dev/null
}

@test "arena-layout with no green lane is a stall (exit 5) and writes no candidates" {
  lane la 7
  lane lb 8
  run AL --out "$OUT" --base "$BASE" la lb
  [ "$status" -eq 5 ]
  [[ "$output" == *"stall"* ]]
  [ ! -d "$OUT/candidates" ]
}

@test "arena-layout refuses a lane without its design note, a lane still in a runner's worktree, or an existing --out (usage, exit 2)" {
  lane la 42
  rm .vetdd/notes/la-design.md
  run AL --out "$OUT" --base "$BASE" la
  [ "$status" -eq 2 ] && [[ "$output" == *"design note"* ]]
  WT add lb -- sh test.sh >/dev/null
  run AL --out "$OUT" --base "$BASE" lb
  [ "$status" -eq 2 ] && [[ "$output" == *"still in a worktree"* ]]
  mkdir -p "$OUT"
  run AL --out "$OUT" --base "$BASE" la
  [ "$status" -eq 2 ] && [[ "$output" == *"exists"* ]]
}

@test "the arena rubric's criteria are what check-verdict reads, and a verdict naming a winner passes it" {
  local r="$SCRIPTS/../references/arena-rubric.md"
  head -1 "$r" | grep -q '^# Arena rubric (version 1)$'
  names="$(grep -E '^## [0-9]+\. ' "$r" | sed 's/^## [0-9]*\. //' | jq -R . | jq -s -c .)"
  jq -n --argjson n "$names" '{eval_id: "a", run_id: "r", rubric_version: 1, labels: ["c1","c2"], winner: "c2", confidence: "mid",
    conditions_check: {applies: false, note: ""}, disagreements: [],
    verdicts: [{label: "c1", verdict: "partial"}, {label: "c2", verdict: "pass"}],
    criteria: [$n[] | {name: ., scores: [{label: "c1", score: 1, evidence: "c1/artifact/diff.patch:1"}, {label: "c2", score: 2, evidence: "c2/artifact/diff.patch:1"}]}]}' > "$BATS_TEST_TMPDIR/v.json"
  run "$SCRIPTS/check-verdict.sh" "$BATS_TEST_TMPDIR/v.json" --labels c1,c2 --rubric "$r" --eval-id a --run-id r --rubric-version 1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "docs: arena.md exists and is the shape select.md offers; the runner role is in the brief" {
  local a="$SCRIPTS/../parallel/arena.md"
  [ -f "$a" ]
  grep -q 'arena-layout.sh' "$a"
  grep -q 'graft' "$a"
  grep -q 'models.sh arena-runner' "$a"
  ! grep -q 'arena not yet available' "$SCRIPTS/../parallel/select.md" || false
  grep -q 'arena runner' "$SCRIPTS/../references/subagent-brief.md"
}

@test "the arena rubric passes the judge's blind check (judge.sh copies it into the judge's input)" {
  mkdir -p "$BATS_TEST_TMPDIR/rb" && cp "$SCRIPTS/../references/arena-rubric.md" "$BATS_TEST_TMPDIR/rb/rubric.md"
  run "$SCRIPTS/check-blind.sh" "$BATS_TEST_TMPDIR/rb" --profile judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a lane with a JS/TS oracle reaches the judge with check-evidence OK: the layout's check runs --before-close, as the gate does" {
  cp test.sh t.test.ts && git add t.test.ts && git commit -qm ts-oracle && BASE="$(git rev-parse HEAD)"
  WT add la -- sh t.test.ts >/dev/null
  (
    cd "$WTROOT/la" || exit 1
    mkdir -p .vetdd/notes && printf '## Design\nlane la\n' > .vetdd/notes/la-design.md
    ev la before --seam unit --oracle-version v1 --oracle-file t.test.ts -- sh t.test.ts >/dev/null 2>&1
    printf '42\n' > value.txt
    ev la after -- sh t.test.ts >/dev/null 2>&1 || true
    git add value.txt && git commit -qm "lane la"
  )
  WT check la >/dev/null && WT remove la --keep-branch >/dev/null
  run AL --out "$OUT" --base "$BASE" la
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(tail -1 "$OUT/candidates/c1/artifact/check-evidence.txt")" = "exit 0" ]
  ! grep -q 'FAIL' "$OUT/candidates/c1/artifact/check-evidence.txt" || false
}

@test "the arena runner records the whole suite and the type check through evidence.sh, so its note can cite them" {
  grep -A3 'arena runner' "$SCRIPTS/../references/subagent-brief.md" | grep -q 'whole suite'
}

@test "dogfood: the runner adds no behavior the agreement does not name, and the synthesis note is cited as local and inferred" {
  grep -A3 'arena runner' "$SCRIPTS/../references/subagent-brief.md" | grep -q 'add no behavior the agreement does not name'
  grep -q 'cites it as a local file, labeled inferred' "$SCRIPTS/../parallel/arena.md"
}

# --- review round 1 ----------------------------------------------------------------------------------

@test "r1: no lane id is left inside the candidates (directory names, slice_id, check-evidence output, logs)" {
  lane zq-one 42
  lane zq-two 42
  run AL --out "$OUT" --base "$BASE" zq-one zq-two
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  if grep -rq 'zq-' "$OUT/candidates"; then grep -rn 'zq-' "$OUT/candidates" | head; false; fi
  [ -z "$(find "$OUT/candidates" -name '*zq-*')" ]
  # Each candidate's evidence sits under one neutral slice name, and check-evidence says OK for it.
  for l in c1 c2; do
    [ "$(ls "$OUT/candidates/$l/evidence" | wc -l | tr -d ' ')" = 1 ]
    grep -q ': OK$' "$OUT/candidates/$l/artifact/check-evidence.txt"
  done
}

@test "r1: the shuffle draws from /dev/urandom, not a clock-seeded rand()" {
  grep -q '/dev/urandom' "$SCRIPTS/arena-layout.sh"
  ! grep -q 'srand' "$SCRIPTS/arena-layout.sh" || false
}

@test "r1: --allow-binary goes through to each lane's layout" {
  WT add la -- sh test.sh >/dev/null
  (cd "$WTROOT/la" && mkdir -p .vetdd/notes && printf '## Design\nx\n' > .vetdd/notes/la-design.md \
    && ev la before --seam unit --oracle-version v1 --oracle-file test.sh -- sh test.sh >/dev/null 2>&1; \
    printf '42\n' > value.txt && printf 'a\0b' > blob.bin && ev la after -- sh test.sh >/dev/null 2>&1; \
    git add value.txt blob.bin && git commit -qm lane)
  WT check la >/dev/null && WT remove la --keep-branch >/dev/null
  run AL --out "$OUT" --base "$BASE" la
  [ "$status" -ne 0 ]
  run AL --out "$OUT.2" --base "$BASE" --allow-binary blob.bin la
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"next:"* ]]
}

@test "r1: --allow-secrets goes to each lane's layout and into the printed judge command" {
  lane la 42
  run AL --out "$OUT" --base "$BASE" --allow-secrets 'c*/artifact/tests/*:email' la
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"--allow-secrets"*"email"* ]]
}

@test "r1: review refuses a branch that tracks files under .vetdd/" {
  WT add la -- sh test.sh >/dev/null
  (cd "$WTROOT/la" && mkdir -p .vetdd/evidence/la && printf '{}\n' > .vetdd/evidence/la/meta.json && git add -f .vetdd && git commit -qm sneak \
    && mkdir -p .vetdd/notes && printf 'x\n' > .vetdd/notes/la-design.md)
  WT remove la --keep-branch >/dev/null 2>&1 || true
  mkdir -p .vetdd/evidence/la .vetdd/notes && printf '{}\n' > .vetdd/evidence/la/meta.json && printf 'x\n' > .vetdd/notes/la-design.md
  run WT review la
  [ "$status" -ne 0 ]
  [[ "$output" == *".vetdd"* ]]
  [ ! -e "$WTROOT/la" ]
}

@test "r1: a check-evidence that cannot run is a local failure (exit 1), not a stall" {
  lane la 42
  local fake="$BATS_TEST_TMPDIR/fakescripts"
  cp -R "$SCRIPTS" "$fake"
  printf '#!/bin/sh\nexit 127\n' > "$fake/check-evidence.sh"
  run "$fake/arena-layout.sh" --out "$OUT" --base "$BASE" la
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ ! -e "$WTROOT/la" ]
}

@test "r1: --out inside the repository (outside .vetdd) and a lane named twice are usage errors" {
  lane la 42
  run AL --out "$REPO/arena-out" --base "$BASE" la
  [ "$status" -eq 2 ]
  [ ! -e "$REPO/arena-out" ]
  run AL --out "$OUT" --base "$BASE" la la
  [ "$status" -eq 2 ]
}

@test "r1: arena.md passes --test-report when merging the chosen lane" {
  grep -q 'integrated --rerun \[--test-report' "$SCRIPTS/../parallel/arena.md"
}

@test "r1: a layout built with --before-close says so on the first line of check-evidence.txt" {
  lane la 42
  run AL --out "$OUT" --base "$BASE" la
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(head -1 "$OUT/candidates/c1/artifact/check-evidence.txt")" = "mode: before-close (the mutation audit is not due yet)" ]
}
