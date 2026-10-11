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
  lane la-a1b2c3 42
  run WT review la-a1b2c3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "$(cd -P "$BATS_TEST_TMPDIR" && pwd -P)/repo.vetdd-wt/la-a1b2c3" ]
  [ "$(cat "$WTROOT/la-a1b2c3/value.txt")" = 42 ]
  [ -f "$WTROOT/la-a1b2c3/.vetdd/evidence/la-a1b2c3/meta.json" ]
  [ -f "$WTROOT/la-a1b2c3/.vetdd/notes/la-a1b2c3-design.md" ]
  run WT remove la-a1b2c3 --keep-branch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "arena-layout puts every green lane side by side as c1..cN, keeps the order in variants.json, and leaves a red lane out" {
  lane la-a1b2c3 42
  lane lb-d4e5f6 42
  lane lc-0a1b2c 7
  run AL --out "$OUT" --base "$BASE" la-a1b2c3 lb-d4e5f6 lc-0a1b2c
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -d "$OUT/candidates/c1" ] && [ -d "$OUT/candidates/c2" ] && [ ! -e "$OUT/candidates/c3" ]
  [ "$(jq -r '[.[]] | sort | join(",")' "$OUT/variants.json")" = "la-a1b2c3,lb-d4e5f6" ]
  local l; for l in c1 c2; do
    s="$(jq -r --arg l "$l" '.[$l]' "$OUT/variants.json")"
    grep -q '^+42$' "$OUT/candidates/$l/artifact/diff.patch"
    [ -f "$OUT/candidates/$l/evidence/$s/meta.json" ]
    grep -q "lane $s sets value.txt" "$OUT/candidates/$l/artifact/reply.md"
  done
  grep -qx 'lc-0a1b2c: not green' "$OUT/gate.txt"
  [[ "$output" == *"arena-rubric.md"* ]]
  # The review worktrees are gone; the lanes' branches stay for the merge and the grafts.
  [ ! -e "$WTROOT/la-a1b2c3" ] && [ ! -e "$WTROOT/lc-0a1b2c" ]
  git rev-parse -q --verify refs/heads/vetdd/la-a1b2c3 >/dev/null
}

@test "arena-layout with no green lane is a stall (exit 5) and writes no candidates" {
  lane la-a1b2c3 7
  lane lb-d4e5f6 8
  run AL --out "$OUT" --base "$BASE" la-a1b2c3 lb-d4e5f6
  [ "$status" -eq 5 ]
  [[ "$output" == *"stall"* ]]
  [ ! -d "$OUT/candidates" ]
}

@test "arena-layout refuses a lane without its design note, a lane still in a runner's worktree, or an existing --out (usage, exit 2)" {
  lane la-a1b2c3 42
  rm .vetdd/notes/la-a1b2c3-design.md
  run AL --out "$OUT" --base "$BASE" la-a1b2c3
  [ "$status" -eq 2 ] && [[ "$output" == *"design note"* ]]
  WT add lb-d4e5f6 -- sh test.sh >/dev/null
  run AL --out "$OUT" --base "$BASE" lb-d4e5f6
  [ "$status" -eq 2 ] && [[ "$output" == *"still in a worktree"* ]]
  mkdir -p "$OUT"
  run AL --out "$OUT" --base "$BASE" la-a1b2c3
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
  WT add la-a1b2c3 -- sh t.test.ts >/dev/null
  (
    cd "$WTROOT/la-a1b2c3" || exit 1
    mkdir -p .vetdd/notes && printf '## Design\nlane la-a1b2c3\n' > .vetdd/notes/la-a1b2c3-design.md
    ev la-a1b2c3 before --seam unit --oracle-version v1 --oracle-file t.test.ts -- sh t.test.ts >/dev/null 2>&1
    printf '42\n' > value.txt
    ev la-a1b2c3 after -- sh t.test.ts >/dev/null 2>&1 || true
    git add value.txt && git commit -qm "lane la-a1b2c3"
  )
  WT check la-a1b2c3 >/dev/null && WT remove la-a1b2c3 --keep-branch >/dev/null
  run AL --out "$OUT" --base "$BASE" la-a1b2c3
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

@test "r2: lane ids carry a random suffix, so the candidates hide nothing and change nothing" {
  lane la 42
  run AL --out "$OUT" --base "$BASE" la
  [ "$status" -eq 2 ]
  [[ "$output" == *"random"* ]]
  [ ! -e "$OUT" ]
  lane la-9f3c2a 42
  run AL --out "$OUT.2" --base "$BASE" la-9f3c2a
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # The evidence is sent as recorded: nothing in it is rewritten.
  cmp -s "$OUT.2/candidates/c1/evidence/la-9f3c2a/meta.json" .vetdd/evidence/la-9f3c2a/meta.json
  jq -e '[.runs[].kind] | index("before") != null' "$OUT.2/candidates/c1/evidence/la-9f3c2a/meta.json" >/dev/null
}

@test "r1: the shuffle draws from /dev/urandom, not a clock-seeded rand()" {
  grep -q '/dev/urandom' "$SCRIPTS/arena-layout.sh"
  ! grep -q 'srand' "$SCRIPTS/arena-layout.sh" || false
}

@test "r1: --allow-binary goes through to each lane's layout" {
  WT add la-a1b2c3 -- sh test.sh >/dev/null
  (cd "$WTROOT/la-a1b2c3" && mkdir -p .vetdd/notes && printf '## Design\nx\n' > .vetdd/notes/la-a1b2c3-design.md \
    && ev la-a1b2c3 before --seam unit --oracle-version v1 --oracle-file test.sh -- sh test.sh >/dev/null 2>&1; \
    printf '42\n' > value.txt && printf 'a\0b' > blob.bin && ev la-a1b2c3 after -- sh test.sh >/dev/null 2>&1; \
    git add value.txt blob.bin && git commit -qm lane)
  WT check la-a1b2c3 >/dev/null && WT remove la-a1b2c3 --keep-branch >/dev/null
  lane lb-d4e5f6 42
  run AL --out "$OUT" --base "$BASE" la-a1b2c3 lb-d4e5f6
  [ "$status" -ne 0 ]
  run AL --out "$OUT.2" --base "$BASE" --allow-binary blob.bin la-a1b2c3 lb-d4e5f6
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"next:"* ]]
}

@test "r1: --allow-secrets goes to each lane's layout and into the printed judge command" {
  lane la-a1b2c3 42
  lane lb-d4e5f6 42
  run AL --out "$OUT" --base "$BASE" --allow-secrets 'c*/artifact/tests/*:email' la-a1b2c3 lb-d4e5f6
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"--allow-secrets"*"email"* ]]
}

@test "r1: review refuses a branch that tracks files under .vetdd/" {
  WT add la-a1b2c3 -- sh test.sh >/dev/null
  (cd "$WTROOT/la-a1b2c3" && mkdir -p .vetdd/evidence/la-a1b2c3 && printf '{}\n' > .vetdd/evidence/la-a1b2c3/meta.json && git add -f .vetdd && git commit -qm sneak \
    && mkdir -p .vetdd/notes && printf 'x\n' > .vetdd/notes/la-a1b2c3-design.md)
  WT remove la-a1b2c3 --keep-branch >/dev/null 2>&1 || true
  mkdir -p .vetdd/evidence/la-a1b2c3 .vetdd/notes && printf '{}\n' > .vetdd/evidence/la-a1b2c3/meta.json && printf 'x\n' > .vetdd/notes/la-a1b2c3-design.md
  run WT review la-a1b2c3
  [ "$status" -ne 0 ]
  [[ "$output" == *".vetdd"* ]]
  [ ! -e "$WTROOT/la-a1b2c3" ]
}

@test "r1: a check-evidence that cannot run is a local failure (exit 1), not a stall" {
  lane la-a1b2c3 42
  local fake="$BATS_TEST_TMPDIR/fakescripts"
  cp -R "$SCRIPTS" "$fake"
  printf '#!/bin/sh\nexit 127\n' > "$fake/check-evidence.sh"
  run "$fake/arena-layout.sh" --out "$OUT" --base "$BASE" la-a1b2c3
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ ! -e "$WTROOT/la-a1b2c3" ]
}

@test "r1: --out inside the repository (outside .vetdd) and a lane named twice are usage errors" {
  lane la-a1b2c3 42
  run AL --out "$REPO/arena-out" --base "$BASE" la-a1b2c3
  [ "$status" -eq 2 ]
  [ ! -e "$REPO/arena-out" ]
  run AL --out "$OUT" --base "$BASE" la-a1b2c3 la-a1b2c3
  [ "$status" -eq 2 ]
}

@test "r1: arena.md passes --test-report when merging the chosen lane" {
  grep -q 'integrated --rerun \[--test-report' "$SCRIPTS/../parallel/arena.md"
}

@test "r1: a layout built with --before-close says so on the first line of check-evidence.txt" {
  lane la-a1b2c3 42
  run AL --out "$OUT" --base "$BASE" la-a1b2c3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(head -1 "$OUT/candidates/c1/artifact/check-evidence.txt")" = "mode: before-close (the mutation audit is not due yet)" ]
}

@test "r2: review leaves nothing behind when it cannot finish (a link in the main repository's notes)" {
  lane la-a1b2c3 42
  ln -s "$BATS_TEST_TMPDIR" .vetdd/notes/elsewhere
  run WT review la-a1b2c3
  [ "$status" -ne 0 ]
  [ ! -e "$WTROOT/la-a1b2c3" ]
  [ -z "$(git worktree list --porcelain | grep "$WTROOT/la-a1b2c3")" ]
}

@test "r2: review and check refuse a branch name that a tag shares, and a .VETDD of any case" {
  lane la-a1b2c3 42
  git tag vetdd/la-a1b2c3 HEAD
  run WT review la-a1b2c3
  [ "$status" -ne 0 ]
  [[ "$output" == *"tag"* ]]
  git tag -d vetdd/la-a1b2c3 >/dev/null
  WT add lb-d4e5f6 >/dev/null
  (cd "$WTROOT/lb-d4e5f6" && mkdir -p .VETDD && printf 'x\n' > .VETDD/x && git add .VETDD && git commit -qm upper)
  run WT check lb-d4e5f6
  [ "$status" -eq 1 ]
}

@test "r2: a layout built in a linked worktree replaces the main repository's path too" {
  WT add la-a1b2c3 -- sh test.sh >/dev/null
  (cd "$WTROOT/la-a1b2c3" && ev la-a1b2c3 before --seam unit --oracle-version v1 --oracle-file test.sh -- sh test.sh >/dev/null 2>&1; \
    printf 'linked %s/node_modules\n' "$REPO" >> .vetdd/evidence/la-a1b2c3/runs/001-before.log; \
    printf '42\n' > value.txt; ev la-a1b2c3 after -- sh test.sh >/dev/null 2>&1; \
    printf 'r\n' > "$BATS_TEST_TMPDIR/r.md"; \
    "$SCRIPTS/judge-layout.sh" --before-close --out "$BATS_TEST_TMPDIR/jl" --reply "$BATS_TEST_TMPDIR/r.md" --base HEAD la-a1b2c3 >/dev/null 2>&1)
  grep -qF 'linked <repo>/node_modules' "$BATS_TEST_TMPDIR/jl/c1/evidence/la-a1b2c3/runs/001-before.log"
}

# --- PR #41 review threads -------------------------------------------------------------------------

@test "a single green lane is chosen without a comparison (the judge would name no winner)" {
  lane la-a1b2c3 42
  lane lb-d4e5f6 7
  run AL --out "$OUT" --base "$BASE" la-a1b2c3 lb-d4e5f6
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"only one lane is green: la-a1b2c3"* ]]
  [[ "$output" != *"judge.sh"* ]]
  [ "$(cat "$OUT/chosen")" = "la-a1b2c3" ]
  grep -q 'only one lane is green' "$SCRIPTS/../parallel/arena.md"
}

@test "a lane that worktree.sh check refuses stays out; the other lanes still reach the judge" {
  lane la-a1b2c3 42
  lane lb-d4e5f6 42
  WT add lc-0a1b2c -- sh test.sh >/dev/null
  (cd "$WTROOT/lc-0a1b2c" && mkdir -p .vetdd/notes && printf 'x\n' > .vetdd/notes/lc-0a1b2c-design.md \
    && ev lc-0a1b2c before --seam unit --oracle-version v1 --oracle-file test.sh -- sh test.sh >/dev/null 2>&1; \
    printf '42\n' > value.txt; ev lc-0a1b2c after -- sh test.sh >/dev/null 2>&1; \
    printf '* filter=x\n' > .gitattributes && git add value.txt .gitattributes && git commit -qm lane)
  WT remove lc-0a1b2c --keep-branch >/dev/null
  run AL --out "$OUT" --base "$BASE" la-a1b2c3 lb-d4e5f6 lc-0a1b2c
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx 'lc-0a1b2c: refused by worktree.sh check' "$OUT/gate.txt"
  [ "$(jq -r '[.[]] | sort | join(",")' "$OUT/variants.json")" = "la-a1b2c3,lb-d4e5f6" ]
}
