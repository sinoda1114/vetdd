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
  lane ar-a1b2c3 42
  run WT review ar-a1b2c3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "$(cd -P "$BATS_TEST_TMPDIR" && pwd -P)/repo.vetdd-wt/ar-a1b2c3" ]
  [ "$(cat "$WTROOT/ar-a1b2c3/value.txt")" = 42 ]
  [ -f "$WTROOT/ar-a1b2c3/.vetdd/evidence/ar-a1b2c3/meta.json" ]
  [ -f "$WTROOT/ar-a1b2c3/.vetdd/notes/ar-a1b2c3-design.md" ]
  run WT remove ar-a1b2c3 --keep-branch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "arena-layout puts every green lane side by side as c1..cN, keeps the order in variants.json, and leaves a red lane out" {
  lane ar-a1b2c3 42
  lane ar-d4e5f6 42
  lane ar-0a1b2c 7
  run AL --out "$OUT" --base "$BASE" ar-a1b2c3 ar-d4e5f6 ar-0a1b2c
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -d "$OUT/candidates/c1" ] && [ -d "$OUT/candidates/c2" ] && [ ! -e "$OUT/candidates/c3" ]
  [ "$(jq -r '[.[]] | sort | join(",")' "$OUT/variants.json")" = "ar-a1b2c3,ar-d4e5f6" ]
  local l; for l in c1 c2; do
    s="$(jq -r --arg l "$l" '.[$l]' "$OUT/variants.json")"
    grep -q '^+42$' "$OUT/candidates/$l/artifact/diff.patch"
    [ -f "$OUT/candidates/$l/evidence/$s/meta.json" ]
    grep -q "lane $s sets value.txt" "$OUT/candidates/$l/artifact/reply.md"
  done
  grep -qx 'ar-0a1b2c: not green' "$OUT/gate.txt"
  [[ "$output" == *"arena-rubric.md"* ]]
  # The review worktrees are gone; the lanes' branches stay for the merge and the grafts.
  [ ! -e "$WTROOT/ar-a1b2c3" ] && [ ! -e "$WTROOT/ar-0a1b2c" ]
  git rev-parse -q --verify refs/heads/vetdd/ar-a1b2c3 >/dev/null
}

@test "arena-layout with no green lane is a stall (exit 5) and writes no candidates" {
  lane ar-a1b2c3 7
  lane ar-d4e5f6 8
  run AL --out "$OUT" --base "$BASE" ar-a1b2c3 ar-d4e5f6
  [ "$status" -eq 5 ]
  [[ "$output" == *"stall"* ]]
  [ ! -d "$OUT/candidates" ]
}

@test "arena-layout refuses a lane without its design note, a lane still in a runner's worktree, or an existing --out (usage, exit 2)" {
  lane ar-a1b2c3 42
  rm .vetdd/notes/ar-a1b2c3-design.md
  run AL --out "$OUT" --base "$BASE" ar-a1b2c3
  [ "$status" -eq 2 ] && [[ "$output" == *"design note"* ]]
  WT add ar-d4e5f6 -- sh test.sh >/dev/null
  run AL --out "$OUT" --base "$BASE" ar-d4e5f6
  [ "$status" -eq 2 ] && [[ "$output" == *"still in a worktree"* ]]
  mkdir -p "$OUT"
  run AL --out "$OUT" --base "$BASE" ar-a1b2c3
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
  WT add ar-a1b2c3 -- sh t.test.ts >/dev/null
  (
    cd "$WTROOT/ar-a1b2c3" || exit 1
    mkdir -p .vetdd/notes && printf '## Design\nlane ar-a1b2c3\n' > .vetdd/notes/ar-a1b2c3-design.md
    ev ar-a1b2c3 before --seam unit --oracle-version v1 --oracle-file t.test.ts -- sh t.test.ts >/dev/null 2>&1
    printf '42\n' > value.txt
    ev ar-a1b2c3 after -- sh t.test.ts >/dev/null 2>&1 || true
    git add value.txt && git commit -qm "lane ar-a1b2c3"
  )
  WT check ar-a1b2c3 >/dev/null && WT remove ar-a1b2c3 --keep-branch >/dev/null
  run AL --out "$OUT" --base "$BASE" ar-a1b2c3
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
  lane ar-9f3c2a 42
  run AL --out "$OUT.2" --base "$BASE" ar-9f3c2a
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # The evidence is sent as recorded: nothing in it is rewritten.
  cmp -s "$OUT.2/candidates/c1/evidence/ar-9f3c2a/meta.json" .vetdd/evidence/ar-9f3c2a/meta.json
  jq -e '[.runs[].kind] | index("before") != null' "$OUT.2/candidates/c1/evidence/ar-9f3c2a/meta.json" >/dev/null
}

@test "r1: the shuffle draws from /dev/urandom, not a clock-seeded rand()" {
  grep -q '/dev/urandom' "$SCRIPTS/arena-layout.sh"
  ! grep -q 'srand' "$SCRIPTS/arena-layout.sh" || false
}

@test "r1: --allow-binary goes through to each lane's layout" {
  WT add ar-a1b2c3 -- sh test.sh >/dev/null
  (cd "$WTROOT/ar-a1b2c3" && mkdir -p .vetdd/notes && printf '## Design\nx\n' > .vetdd/notes/ar-a1b2c3-design.md \
    && ev ar-a1b2c3 before --seam unit --oracle-version v1 --oracle-file test.sh -- sh test.sh >/dev/null 2>&1; \
    printf '42\n' > value.txt && printf 'a\0b' > blob.bin && ev ar-a1b2c3 after -- sh test.sh >/dev/null 2>&1; \
    git add value.txt blob.bin && git commit -qm lane)
  WT check ar-a1b2c3 >/dev/null && WT remove ar-a1b2c3 --keep-branch >/dev/null
  lane ar-d4e5f6 42
  run AL --out "$OUT" --base "$BASE" ar-a1b2c3 ar-d4e5f6
  [ "$status" -ne 0 ]
  run AL --out "$OUT.2" --base "$BASE" --allow-binary blob.bin ar-a1b2c3 ar-d4e5f6
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"next:"* ]]
}

@test "r1: --allow-secrets goes to each lane's layout and into the printed judge command" {
  lane ar-a1b2c3 42
  lane ar-d4e5f6 42
  run AL --out "$OUT" --base "$BASE" --allow-secrets 'c*/artifact/tests/*:email' ar-a1b2c3 ar-d4e5f6
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"--allow-secrets"*"email"* ]]
}

@test "r1: review refuses a branch that tracks files under .vetdd/" {
  WT add ar-a1b2c3 -- sh test.sh >/dev/null
  (cd "$WTROOT/ar-a1b2c3" && mkdir -p .vetdd/evidence/ar-a1b2c3 && printf '{}\n' > .vetdd/evidence/ar-a1b2c3/meta.json && git add -f .vetdd && git commit -qm sneak \
    && mkdir -p .vetdd/notes && printf 'x\n' > .vetdd/notes/ar-a1b2c3-design.md)
  WT remove ar-a1b2c3 --keep-branch >/dev/null 2>&1 || true
  mkdir -p .vetdd/evidence/ar-a1b2c3 .vetdd/notes && printf '{}\n' > .vetdd/evidence/ar-a1b2c3/meta.json && printf 'x\n' > .vetdd/notes/ar-a1b2c3-design.md
  run WT review ar-a1b2c3
  [ "$status" -ne 0 ]
  [[ "$output" == *".vetdd"* ]]
  [ ! -e "$WTROOT/ar-a1b2c3" ]
}

@test "r1: a check-evidence that cannot run is a local failure (exit 1), not a stall" {
  lane ar-a1b2c3 42
  local fake="$BATS_TEST_TMPDIR/fakescripts"
  cp -R "$SCRIPTS" "$fake"
  printf '#!/bin/sh\nexit 127\n' > "$fake/check-evidence.sh"
  run "$fake/arena-layout.sh" --out "$OUT" --base "$BASE" ar-a1b2c3
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ ! -e "$WTROOT/ar-a1b2c3" ]
}

@test "r1: --out inside the repository (outside .vetdd) and a lane named twice are usage errors" {
  lane ar-a1b2c3 42
  run AL --out "$REPO/arena-out" --base "$BASE" ar-a1b2c3
  [ "$status" -eq 2 ]
  [ ! -e "$REPO/arena-out" ]
  run AL --out "$OUT" --base "$BASE" ar-a1b2c3 ar-a1b2c3
  [ "$status" -eq 2 ]
}

@test "r1: arena.md passes --test-report when merging the chosen lane" {
  grep -q 'integrated --rerun \[--test-report' "$SCRIPTS/../parallel/arena.md"
}

@test "r1: a layout built with --before-close says so on the first line of check-evidence.txt" {
  lane ar-a1b2c3 42
  run AL --out "$OUT" --base "$BASE" ar-a1b2c3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(head -1 "$OUT/candidates/c1/artifact/check-evidence.txt")" = "mode: before-close (the mutation audit is not due yet)" ]
}

@test "r2: review leaves nothing behind when it cannot finish (a link in the main repository's notes)" {
  lane ar-a1b2c3 42
  ln -s "$BATS_TEST_TMPDIR" .vetdd/notes/elsewhere
  run WT review ar-a1b2c3
  [ "$status" -ne 0 ]
  [ ! -e "$WTROOT/ar-a1b2c3" ]
  [ -z "$(git worktree list --porcelain | grep "$WTROOT/ar-a1b2c3")" ]
}

@test "r2: review and check refuse a branch name that a tag shares, and a .VETDD of any case" {
  lane ar-a1b2c3 42
  git tag vetdd/ar-a1b2c3 HEAD
  run WT review ar-a1b2c3
  [ "$status" -ne 0 ]
  [[ "$output" == *"tag"* ]]
  git tag -d vetdd/ar-a1b2c3 >/dev/null
  WT add ar-d4e5f6 >/dev/null
  (cd "$WTROOT/ar-d4e5f6" && mkdir -p .VETDD && printf 'x\n' > .VETDD/x && git add .VETDD && git commit -qm upper)
  run WT check ar-d4e5f6
  [ "$status" -eq 1 ]
}

@test "r2: a layout built in a linked worktree replaces the main repository's path too" {
  WT add ar-a1b2c3 -- sh test.sh >/dev/null
  (cd "$WTROOT/ar-a1b2c3" && ev ar-a1b2c3 before --seam unit --oracle-version v1 --oracle-file test.sh -- sh test.sh >/dev/null 2>&1; \
    printf 'linked %s/node_modules\n' "$REPO" >> .vetdd/evidence/ar-a1b2c3/runs/001-before.log; \
    printf '42\n' > value.txt; ev ar-a1b2c3 after -- sh test.sh >/dev/null 2>&1; \
    printf 'r\n' > "$BATS_TEST_TMPDIR/r.md"; \
    "$SCRIPTS/judge-layout.sh" --before-close --out "$BATS_TEST_TMPDIR/jl" --reply "$BATS_TEST_TMPDIR/r.md" --base HEAD ar-a1b2c3 >/dev/null 2>&1)
  grep -qF 'linked <repo>/node_modules' "$BATS_TEST_TMPDIR/jl/c1/evidence/ar-a1b2c3/runs/001-before.log"
}

# --- PR #41 review threads -------------------------------------------------------------------------

@test "a single green lane is chosen without a comparison (the judge would name no winner)" {
  lane ar-a1b2c3 42
  lane ar-d4e5f6 7
  run AL --out "$OUT" --base "$BASE" ar-a1b2c3 ar-d4e5f6
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"only one lane is green: ar-a1b2c3"* ]]
  [[ "$output" != *"judge.sh"* ]]
  [ "$(cat "$OUT/chosen")" = "ar-a1b2c3" ]
  grep -q 'only one lane is green' "$SCRIPTS/../parallel/arena.md"
}

@test "a lane that worktree.sh check refuses stays out; the other lanes still reach the judge" {
  lane ar-a1b2c3 42
  lane ar-d4e5f6 42
  WT add ar-0a1b2c -- sh test.sh >/dev/null
  (cd "$WTROOT/ar-0a1b2c" && mkdir -p .vetdd/notes && printf 'x\n' > .vetdd/notes/ar-0a1b2c-design.md \
    && ev ar-0a1b2c before --seam unit --oracle-version v1 --oracle-file test.sh -- sh test.sh >/dev/null 2>&1; \
    printf '42\n' > value.txt; ev ar-0a1b2c after -- sh test.sh >/dev/null 2>&1; \
    printf '* filter=x\n' > .gitattributes && git add value.txt .gitattributes && git commit -qm lane)
  WT remove ar-0a1b2c --keep-branch >/dev/null
  run AL --out "$OUT" --base "$BASE" ar-a1b2c3 ar-d4e5f6 ar-0a1b2c
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx 'ar-0a1b2c: refused by worktree.sh check' "$OUT/gate.txt"
  [ "$(jq -r '[.[]] | sort | join(",")' "$OUT/variants.json")" = "ar-a1b2c3,ar-d4e5f6" ]
}

@test "triage: --base HEAD is resolved once in the main repository, so each lane's diff is against the oracle commit" {
  lane ar-a1b2c3 42
  lane ar-d4e5f6 42
  run AL --out "$OUT" --base HEAD ar-a1b2c3 ar-d4e5f6
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '^+42$' "$OUT/candidates/c1/artifact/diff.patch"
  grep -q '^+42$' "$OUT/candidates/c2/artifact/diff.patch"
}

@test "triage r1: an arena lane's layout keeps the origin words checked, as the comparison does; allowing one goes through" {
  WT add ar-a1b2c3 -- sh test.sh >/dev/null
  (cd "$WTROOT/ar-a1b2c3" && mkdir -p .vetdd/notes && printf '## Design\nx\n' > .vetdd/notes/ar-a1b2c3-design.md \
    && ev ar-a1b2c3 before --seam unit --oracle-version v1 --oracle-file test.sh -- sh test.sh >/dev/null 2>&1; \
    printf '42\n' > value.txt && printf '<B variant="x" />\n' > ui.tsx && ev ar-a1b2c3 after -- sh test.sh >/dev/null 2>&1; \
    git add value.txt ui.tsx && git commit -qm lane)
  WT check ar-a1b2c3 >/dev/null && WT remove ar-a1b2c3 --keep-branch >/dev/null
  lane ar-d4e5f6 42
  run AL --out "$OUT" --base "$BASE" ar-a1b2c3 ar-d4e5f6
  [ "$status" -eq 4 ]
  run AL --out "$OUT.2" --base "$BASE" --allow-words 'c*/artifact/diff.patch:variant' ar-a1b2c3 ar-d4e5f6
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"--allow-words"* ]]
}

@test "triage r2: a malformed --allow-words is a usage error before anything is written" {
  lane ar-a1b2c3 42
  run AL --out "$OUT" --base "$BASE" --allow-words 'foo' ar-a1b2c3
  [ "$status" -eq 2 ]
  [ ! -e "$OUT" ]
}

@test "#44: an --allow-words or --allow-secrets glob written for one label (c1/...) is a usage error; c*/... is the form" {
  lane ar-a1b2c3 42
  local f
  for f in --allow-words --allow-secrets; do
    local v='c1/artifact/diff.patch:variant'
    [ "$f" = --allow-words ] || v='c12/artifact/tests/*:email'
    run AL --out "$OUT" --base "$BASE" "$f" "$v" ar-a1b2c3
    [ "$status" -eq 2 ] || { echo "$f $v: $output"; false; }
    [[ "$output" == *"c*/"* ]] || { echo "$f $v: $output"; false; }
    [ ! -e "$OUT" ]
  done
}

@test "PR80: an --allow-words error is printed without control characters" {
  lane ar-a1b2c3 42
  run AL --out "$OUT" --base "$BASE" --allow-words $'c*/x:\033[31mred' ar-a1b2c3
  [ "$status" -eq 2 ]
  [[ "$output" != *$'\033'* ]] || { printf '%s' "$output" | od -c | head; false; }
}

@test "PR80: die filters what it prints (a C1 control that the C locale's [[:cntrl:]] lets through)" {
  lane ar-a1b2c3 42
  LC_ALL=C run AL --out "$OUT" --base "$BASE" --allow-words $'c*/x:\xc2\x9b31mred' ar-a1b2c3
  [ "$status" -eq 2 ]
  [[ "$output" == *"is not a word"* ]] || { echo "$output"; false; }
  [[ "$output" != *$'\xc2\x9b'* ]] || { printf '%s' "$output" | od -c | head; false; }
}

# --- #40 follow-ups --------------------------------------------------------------------------------

# sneak <lane> <name>: a commit on vetdd/<lane> that tracks <name> as a symbolic link to $BATS_TEST_TMPDIR/outside.
sneak() {
  local idx="$BATS_TEST_TMPDIR/sneak.idx" blob tree c
  blob="$(printf '%s' "$BATS_TEST_TMPDIR/outside" | git hash-object -w --stdin)"
  GIT_INDEX_FILE="$idx" git read-tree "vetdd/$1"
  GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo "120000,$blob,$2"
  tree="$(GIT_INDEX_FILE="$idx" git write-tree)"
  c="$(git commit-tree "$tree" -p "vetdd/$1" -m sneak)"
  git update-ref "refs/heads/vetdd/$1" "$c"
  rm -f "$idx"
}

@test "#40: review refuses a branch that tracks .vetdd itself (a link out of the worktree), in any case" {
  mkdir -p "$BATS_TEST_TMPDIR/outside"
  lane ar-a1b2c3 42
  sneak ar-a1b2c3 .vetdd
  run WT review ar-a1b2c3
  [ "$status" -ne 0 ]
  [[ "$output" == *".vetdd"* ]]
  [ ! -e "$WTROOT/ar-a1b2c3" ]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/outside")" ]
  lane ar-d4e5f6 42
  sneak ar-d4e5f6 .VeTdD
  run WT review ar-d4e5f6
  [ "$status" -ne 0 ]
  [ ! -e "$WTROOT/ar-d4e5f6" ]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/outside")" ]
}

@test "#40: every lane carries the same first half (<slice>-<random>), so a lane's name says nothing about its runner" {
  lane ar-a1b2c3 42
  lane br-d4e5f6 42
  run AL --out "$OUT" --base "$BASE" ar-a1b2c3 br-d4e5f6
  [ "$status" -eq 2 ]
  [[ "$output" == *"same"* ]]
  [ ! -e "$OUT" ]
}

@test "#40: gate.txt names the commit each green lane was checked at" {
  lane ar-a1b2c3 42
  lane ar-d4e5f6 42
  run AL --out "$OUT" --base "$BASE" ar-a1b2c3 ar-d4e5f6
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx "ar-a1b2c3: green at $(git rev-parse vetdd/ar-a1b2c3)" "$OUT/gate.txt"
  grep -qx "ar-d4e5f6: green at $(git rev-parse vetdd/ar-d4e5f6)" "$OUT/gate.txt"
}

@test "#40: a lane whose branch moves after check (a runner still at work) stops the build, and no review worktree is left" {
  lane ar-a1b2c3 42
  local fake="$BATS_TEST_TMPDIR/fakescripts"
  cp -R "$SCRIPTS" "$fake"
  mv "$fake/check-evidence.sh" "$fake/check-evidence.real.sh"
  # The same tree on a new commit: nothing else would notice the move.
  printf '#!/bin/sh\nc="$(git -C %s commit-tree "vetdd/ar-a1b2c3^{tree}" -p vetdd/ar-a1b2c3 -m moved)"\ngit -C %s update-ref refs/heads/vetdd/ar-a1b2c3 "$c"\nexec "$(dirname "$0")/check-evidence.real.sh" "$@"\n' "$REPO" "$REPO" > "$fake/check-evidence.sh"
  chmod +x "$fake/check-evidence.sh"
  run "$fake/arena-layout.sh" --out "$OUT" --base "$BASE" ar-a1b2c3
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"moved"* ]]
  [ ! -e "$WTROOT/ar-a1b2c3" ]
  [ ! -e "$OUT/candidates" ]
}

@test "#40: --out with a trailing slash is the directory it names" {
  lane ar-a1b2c3 42
  run AL --out "$OUT/" --base "$BASE" ar-a1b2c3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -d "$OUT/candidates/c1" ]
}

@test "#40: arena.md says the allowances cover every lane, and merges the commit gate.txt names" {
  local ar="$SCRIPTS/../parallel/arena.md"
  grep -q 'cover every lane' "$ar"
  grep -q 'merge --no-ff --no-overwrite-ignore -m "Merge vetdd/<lane>" <the commit gate.txt names>' "$ar"
}

# --- PR review round 1 (#40) -----------------------------------------------------------------------

@test "#40 r1: review --at <commit> checks out that commit, not the branch's tip, and remove takes it away after the branch moves" {
  lane ar-a1b2c3 42
  local at; at="$(git rev-parse vetdd/ar-a1b2c3)"
  run WT review ar-a1b2c3 --at "$at"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(git -C "$WTROOT/ar-a1b2c3" rev-parse HEAD)" = "$at" ]
  # The branch moves to another tree after the checkout: the review worktree still holds the commit.
  local idx="$BATS_TEST_TMPDIR/m.idx" blob tree c
  blob="$(printf '7\n' | git hash-object -w --stdin)"
  GIT_INDEX_FILE="$idx" git read-tree vetdd/ar-a1b2c3
  GIT_INDEX_FILE="$idx" git update-index --cacheinfo "100644,$blob,value.txt"
  tree="$(GIT_INDEX_FILE="$idx" git write-tree)"; c="$(git commit-tree "$tree" -p vetdd/ar-a1b2c3 -m moved)"
  git update-ref refs/heads/vetdd/ar-a1b2c3 "$c"
  [ "$(cat "$WTROOT/ar-a1b2c3/value.txt")" = 42 ]
  [ "$(git -C "$WTROOT/ar-a1b2c3" rev-parse HEAD)" = "$at" ]
  run WT remove ar-a1b2c3 --keep-branch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$WTROOT/ar-a1b2c3" ]
  # A commit the branch is no longer at is refused: it moved since check.
  run WT review ar-a1b2c3 --at "$at"
  [ "$status" -eq 1 ]
  [[ "$output" == *"moved"* ]]
  [ ! -e "$WTROOT/ar-a1b2c3" ]
}

@test "#40 r1: arena-layout reviews each lane at the commit check passed" {
  grep -q 'review "$l" --at "$sha"' "$SCRIPTS/arena-layout.sh"
  grep -q 'remove <lane> --keep-branch --at <the commit check printed>' "$SCRIPTS/../parallel/arena.md"
  grep -q 'remove <slice> --keep-branch --at <the commit check printed>' "$SCRIPTS/../parallel/swarm.md"
}
