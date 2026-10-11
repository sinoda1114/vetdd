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
    s="$(jq -r --arg l "$l" '.[$l]' "$OUT/variants.json")"
    grep -q '^+42$' "$OUT/candidates/$l/artifact/diff.patch"
    [ -f "$OUT/candidates/$l/evidence/$s/meta.json" ]
    grep -q "lane $s sets value.txt" "$OUT/candidates/$l/artifact/reply.md"
  done
  grep -q 'lc' "$OUT/gate.txt"
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
  [ "$status" -eq 2 ]
  WT add lb -- sh test.sh >/dev/null
  run AL --out "$OUT" --base "$BASE" lb
  [ "$status" -eq 2 ]
  mkdir -p "$OUT"
  run AL --out "$OUT" --base "$BASE" la
  [ "$status" -eq 2 ]
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
