#!/usr/bin/env bats
# #42: a slice abandoned in a swarm or an arena (a stall, a conflict, a lane that lost) keeps its evidence
# in the main repository. The parent marks it with `worktree.sh abandon <slice> --cause stall|conflict|lost
# [--replaced-by <id>]`, which writes .vetdd/evidence/<slice>/abandoned ({cause, replaced_by,
# recorded_at}; meta.json does not change). check-evidence.sh prints "<slice>: ABANDONED (...)" for it and
# does not count it as a failure (rules 1-10 skipped; rule 11 still applies to a stall), so the
# pre-commit hook does not block on it; judge-layout.sh, arena-layout.sh, and evidence.sh refuse it.
# `worktree.sh remove` never brings a worker's own mark back.

load test_helper

WT() { "$SCRIPTS/worktree.sh" "$@"; }
JL() { "$SCRIPTS/judge-layout.sh" "$@"; }
AL() { "$SCRIPTS/arena-layout.sh" "$@"; }
HO() { "$SCRIPTS/handover.sh" "$@"; }
hook() { "$SCRIPTS/hooks/pre-commit"; }

setup() {
  make_repo
  WTROOT="$BATS_TEST_TMPDIR/repo.vetdd-wt"
  MARK="$REPO/.vetdd/evidence/s1/abandoned"
}

# red_slice <slice>: a slice whose record fails check-evidence (a red and no green: rule 5).
red_slice() {
  printf '0\n' > value.txt
  ev "$1" before --seam unit --oracle-version v1 --oracle-file test.sh -- sh test.sh >/dev/null 2>&1
}

draft() {
  printf '## Unmet requirement\nx\n## Expected and actual\nx\n## Minimal reproduction\nx\n## Hypotheses tried\nx\n## Why it failed\nx\n## Reusable results\nx\n' > "$BATS_TEST_TMPDIR/draft.md"
  printf '%s' "$BATS_TEST_TMPDIR/draft.md"
}

# stalled_slice <slice>: a red and three failed attempts (a stall at the default K = 2).
stalled_slice() {
  red_slice "$1"
  local i; for i in 1 2 3; do ev "$1" after -- sh test.sh >/dev/null 2>&1 || true; done
}

# worker <slice> [<recorder>]: a swarm unit: worktree.sh add, the recorder (default red_slice) and a
# commit in its worktree, then check and remove --keep-branch, so its evidence is in the main repository.
worker() {
  WT add "$1" >/dev/null
  (cd "$WTROOT/$1" && "${2:-red_slice}" "$1" && git commit -qam "wip $1" --allow-empty) >/dev/null 2>&1
  WT check "$1" >/dev/null && WT remove "$1" --keep-branch >/dev/null
}

# --- worktree.sh abandon -----------------------------------------------------------------------

@test "abandon writes the mark (cause, replaced_by, recorded_at in UTC) and leaves meta.json as it was" {
  worker s1
  local before; before="$(sha256_of .vetdd/evidence/s1/meta.json)"
  run WT abandon s1 --cause conflict --replaced-by s1-2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"s1"*"abandoned"* ]]
  [ -f "$MARK" ] && [ ! -L "$MARK" ]
  [ "$(jq -r '.cause' "$MARK")" = conflict ]
  [ "$(jq -r '.replaced_by' "$MARK")" = s1-2 ]
  jq -e '.recorded_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "$MARK" >/dev/null
  [ "$(jq -r 'keys | join(",")' "$MARK")" = "cause,recorded_at,replaced_by" ]
  [ "$(sha256_of .vetdd/evidence/s1/meta.json)" = "$before" ]
}

@test "abandon without --replaced-by leaves the key out; each cause is taken" {
  local c
  for c in stall conflict lost; do
    worker "s-$c"
    run WT abandon "s-$c" --cause "$c"
    [ "$status" -eq 0 ] || { echo "$c: $output"; false; }
    [ "$(jq -r 'keys | join(",")' ".vetdd/evidence/s-$c/abandoned")" = "cause,recorded_at" ]
    [ "$(jq -r '.cause' ".vetdd/evidence/s-$c/abandoned")" = "$c" ]
  done
}

@test "abandon refuses a missing or unknown cause, a bad or same --replaced-by, and unknown options (usage, exit 2), writing nothing" {
  worker s1
  run WT abandon s1
  [ "$status" -eq 2 ]
  run WT abandon s1 --cause gave-up
  [ "$status" -eq 2 ]
  run WT abandon s1 --cause stall --replaced-by ../x
  [ "$status" -eq 2 ]
  run WT abandon s1 --cause stall --replaced-by s1
  [ "$status" -eq 2 ]
  run WT abandon s1 --cause stall --force
  [ "$status" -eq 2 ]
  run WT abandon ../s1 --cause stall
  [ "$status" -eq 2 ]
  [ ! -e "$MARK" ]
  # The same slice with good arguments is marked: the refusals were about the arguments.
  run WT abandon s1 --cause stall --replaced-by s1-r1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "abandon refuses a slice with no evidence in the main repository (exit 2) and one already marked (exit 1)" {
  run WT abandon s1 --cause lost
  [ "$status" -eq 2 ]
  [[ "$output" == *"no evidence"* ]]
  [ ! -e .vetdd/evidence/s1 ]
  worker s1
  WT abandon s1 --cause lost >/dev/null
  local first; first="$(cat "$MARK")"
  run WT abandon s1 --cause stall
  [ "$status" -eq 1 ]
  [[ "$output" == *"already"* ]]
  [ "$(cat "$MARK")" = "$first" ]
}

@test "abandon refuses while the slice's worker worktree is still there, and from a worker's worktree" {
  WT add sa >/dev/null
  (cd "$WTROOT/sa" && red_slice sa && git commit -qm wip --allow-empty)
  run WT abandon sa --cause stall
  [ "$status" -eq 1 ]
  [[ "$output" == *"worktree"* ]]
  [[ "$output" == *"remove"* ]]
  (cd "$WTROOT/sa" && run "$SCRIPTS/worktree.sh" abandon sa --cause stall && [ "$status" -eq 2 ])
  [ ! -e "$WTROOT/sa/.vetdd/evidence/sa/abandoned" ]
  WT remove sa --keep-branch >/dev/null
  run WT abandon sa --cause stall
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f .vetdd/evidence/sa/abandoned ]
}

@test "abandon refuses a slice directory or evidence directory that is a link" {
  worker s1
  mv .vetdd/evidence/s1 "$BATS_TEST_TMPDIR/outside"
  ln -s "$BATS_TEST_TMPDIR/outside" .vetdd/evidence/s1
  run WT abandon s1 --cause lost
  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/outside/abandoned" ]
  rm -f -- .vetdd/evidence/s1 && mv "$BATS_TEST_TMPDIR/outside" .vetdd/evidence/s1
  run WT abandon s1 --cause lost
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "remove never brings back a worker's own abandoned mark, and says so" {
  WT add sa >/dev/null
  (cd "$WTROOT/sa" && red_slice sa \
    && printf '{"cause":"lost","recorded_at":"2026-10-25T00:00:00Z"}\n' > .vetdd/evidence/sa/abandoned \
    && git commit -qm wip --allow-empty)
  run WT remove sa --keep-branch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f .vetdd/evidence/sa/meta.json ]
  [ ! -e .vetdd/evidence/sa/abandoned ]
  [[ "$output" == *"abandoned"* ]]
}

@test "remove does not count the parent's mark as a difference: a worker's copy of the same runs without it is the same evidence" {
  WT add sa >/dev/null
  (cd "$WTROOT/sa" && red_slice sa && git commit -qm wip --allow-empty)
  WT remove sa --keep-branch >/dev/null
  WT abandon sa --cause lost >/dev/null
  # A worker's copy without the mark (the same runs) is not "different evidence".
  WT add sb >/dev/null
  mkdir -p "$WTROOT/sb/.vetdd/evidence"
  cp -R .vetdd/evidence/sa "$WTROOT/sb/.vetdd/evidence/sa"
  rm -f -- "$WTROOT/sb/.vetdd/evidence/sa/abandoned"
  run WT remove sb --keep-branch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f .vetdd/evidence/sa/abandoned ]
}

@test "abandon takes the slice's lock (lib/meta.sh): it refuses while another vetdd script records the slice, and frees the lock" {
  worker s1
  local lock; lock="$(git rev-parse --absolute-git-dir)/vetdd-lock/s1"
  mkdir -p "${lock%/*}" && ln -s "pid:$$" "$lock"
  run WT abandon s1 --cause lost
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"pid $$"* ]]
  [ ! -e "$MARK" ]
  rm -f -- "$lock"
  run WT abandon s1 --cause lost
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -L "$lock" ]
}

@test "abandon refuses a slice that no worktree.sh add made (usage, exit 2), and one whose branch is merged (exit 1)" {
  red_slice s1
  run WT abandon s1 --cause lost
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"worktree.sh add"* ]]
  [ ! -e "$MARK" ]
  WT add sa >/dev/null
  (cd "$WTROOT/sa" && red_slice sa && printf '42\n' > value.txt && git commit -qam "fix sa") >/dev/null 2>&1
  WT check sa >/dev/null && WT remove sa --keep-branch >/dev/null
  git merge -q --no-ff --no-edit -m "Merge vetdd/sa" vetdd/sa
  run WT abandon sa --cause conflict
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"merged"* ]]
  [ ! -e .vetdd/evidence/sa/abandoned ]
  # Undone (git reset --hard ORIG_HEAD, as swarm.md says), it is no longer merged.
  git reset -q --hard ORIG_HEAD
  run WT abandon sa --cause conflict
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "remove leaves out only the mark at the top of a slice's evidence: another file named abandoned is still compared" {
  worker sa
  WT abandon sa --cause lost >/dev/null
  WT add sb >/dev/null
  mkdir -p "$WTROOT/sb/.vetdd/evidence"
  cp -R .vetdd/evidence/sa "$WTROOT/sb/.vetdd/evidence/sa"
  rm -f -- "$WTROOT/sb/.vetdd/evidence/sa/abandoned"
  printf 'x\n' > "$WTROOT/sb/.vetdd/evidence/sa/runs/abandoned"
  run WT remove sb --keep-branch
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"different evidence"* ]]
  [ ! -e .vetdd/evidence/sa/runs/abandoned ]
}

@test "abandon refuses a delivered slice whose branch was deleted after its merge (Merge vetdd/<slice> is in HEAD)" {
  WT add sa >/dev/null
  (cd "$WTROOT/sa" && red_slice sa && printf '42\n' > value.txt && git commit -qam "fix sa") >/dev/null 2>&1
  WT check sa >/dev/null && WT remove sa --keep-branch >/dev/null
  git -c core.hooksPath=/dev/null merge -q --no-ff --no-edit -m "Merge vetdd/sa" vetdd/sa
  git branch -q -d vetdd/sa
  run WT abandon sa --cause conflict
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"merged"* ]]
  [ ! -e .vetdd/evidence/sa/abandoned ]
  # A stalled branch deleted once noted (never merged) is still marked.
  worker sb
  git branch -q -D vetdd/sb
  run WT abandon sb --cause stall
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "remove does not take a file name holding a new line for the mark: such evidence is different" {
  worker sa
  WT abandon sa --cause lost >/dev/null
  WT add sb >/dev/null
  mkdir -p "$WTROOT/sb/.vetdd/evidence"
  cp -R .vetdd/evidence/sa "$WTROOT/sb/.vetdd/evidence/sa"
  rm -f -- "$WTROOT/sb/.vetdd/evidence/sa/abandoned"
  # (diff prints such a name over two lines; a guard, since a name cannot hold the / of a forged line)
  printf 'x\n' > "$WTROOT/sb/.vetdd/evidence/sa/abandoned
x"
  run WT remove sb --keep-branch
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"different evidence"* ]]
}

# --- check-evidence.sh -------------------------------------------------------------------------

@test "check-evidence prints ABANDONED for a marked slice, with the cause and the slice that replaced it, and does not count it" {
  worker s1
  run check s1
  [ "$status" -eq 1 ]
  WT abandon s1 --cause conflict --replaced-by s1-2 >/dev/null
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "s1: ABANDONED (conflict, replaced by s1-2)" ]
}

@test "check-evidence with no slice named lists an abandoned slice and counts only the others" {
  worker s1
  red_slice s2
  record_good_slice s3 >/dev/null 2>&1
  WT abandon s1 --cause lost >/dev/null
  run check
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"s1: ABANDONED (lost)"* ]]
  [[ "$output" == *"s2: FAIL"* ]]
  [[ "$output" != *"s1: FAIL"* ]]
}

@test "an abandoned stall still answers rule 11: a handover lacking a heading fails it, and a missing handover warns" {
  worker s1 stalled_slice
  WT abandon s1 --cause stall --replaced-by s1-r1 >/dev/null
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "${lines[0]}" = "s1: ABANDONED (stall, replaced by s1-r1)" ]
  [[ "${lines[1]}" == "s1: WARN (11: the record holds 1 stalls and 0 handover(s)"* ]]
  [ "${#lines[@]}" -eq 2 ]
  HO s1 --file "$(draft)" >/dev/null
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "s1: ABANDONED (stall, replaced by s1-r1)" ]
  printf 'no headings\n' > .vetdd/evidence/s1/handover-1.md
  run check s1
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "s1: ABANDONED (stall, replaced by s1-r1)" ]
  [[ "${lines[1]}" == "s1: FAIL (11: handover-1.md lacks the heading(s):"* ]]
}

@test "rule 11 is not asked of a slice abandoned for a conflict or a lost lane" {
  worker s1 stalled_slice
  WT abandon s1 --cause conflict >/dev/null
  run check s1
  [ "$status" -eq 0 ]
  [ "$output" = "s1: ABANDONED (conflict)" ]
}

@test "a mark that is not what worktree.sh abandon writes fails the slice" {
  red_slice s1
  local bad
  for bad in 'not json' '{"cause":"gave-up","recorded_at":"2026-10-25T00:00:00Z"}' \
      '{"cause":"lost"}' '{"cause":"lost","recorded_at":"yesterday"}' \
      '{"cause":"lost","recorded_at":"2026-10-25T00:00:00Z","replaced_by":"../x"}' \
      '{"cause":"lost","recorded_at":"2026-10-25T00:00:00Z","replaced_by":"s1"}' \
      '{"cause":"lost","recorded_at":"2026-10-25T00:00:00Z","note":"x"}' \
      '{"cause":"lost","recorded_at":"2026-10-25T00:00:00Z"}{"cause":"lost","recorded_at":"2026-10-25T00:00:00Z"}' \
      '["lost"]'; do
    printf '%s\n' "$bad" > "$MARK"
    run check s1
    [ "$status" -eq 1 ] || { echo "$bad: $output"; false; }
    [[ "$output" == "s1: FAIL (abandoned: "* ]] || { echo "$bad: $output"; false; }
    [[ "$output" != *"ABANDONED"* ]] || { echo "$bad: $output"; false; }
  done
  rm -f -- "$MARK"
  printf '{"cause":"lost","recorded_at":"2026-10-25T00:00:00Z"}\n' > "$BATS_TEST_TMPDIR/mark"
  ln -s "$BATS_TEST_TMPDIR/mark" "$MARK"
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == "s1: FAIL (abandoned: "* ]]
}

@test "a mark in a directory with no meta.json fails the slice, whatever the cause" {
  mkdir -p .vetdd/evidence/s9
  printf '{"cause":"lost","recorded_at":"2026-10-25T00:00:00Z"}\n' > .vetdd/evidence/s9/abandoned
  run check s9
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"s9: FAIL (schema: no meta.json"* ]]
}

@test "calibrate.sh refuses an abandoned slice before it parks anything (exit 2)" {
  worker s1
  WT abandon s1 --cause lost >/dev/null
  printf '42\n' > value.txt
  run "$SCRIPTS/calibrate.sh" unfix s1 --file value.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"abandoned"* ]]
  [ "$(cat value.txt)" = 42 ]
  [ ! -e "$(git rev-parse --absolute-git-dir)/vetdd-calib/s1" ]
}

@test "the check-evidence header documents the ABANDONED line" {
  sed -n '1,/^set -u/p' "$SCRIPTS/check-evidence.sh" | grep -q 'ABANDONED'
}

# --- the pre-commit hook ----------------------------------------------------------------------

@test "the pre-commit hook does not block on an abandoned slice whose oracle file is staged" {
  worker s1
  printf '# edited for the redesign\n' >> test.sh
  git add test.sh
  run hook
  [ "$status" -ne 0 ]
  [[ "$output" == *"s1: FAIL"* ]]
  WT abandon s1 --cause stall --replaced-by s1-r1 >/dev/null
  run hook
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"s1: ABANDONED (stall, replaced by s1-r1)"* ]]
}

# --- the scripts that refuse an abandoned slice ------------------------------------------------

@test "evidence.sh refuses an abandoned slice (usage, exit 2), runs nothing, and records nothing" {
  worker s1
  WT abandon s1 --cause lost >/dev/null
  local before; before="$(sha256_of .vetdd/evidence/s1/meta.json)"
  run ev s1 after -- sh -c 'touch ran.txt'
  [ "$status" -eq 2 ]
  [[ "$output" == *"abandoned"* ]]
  [ ! -e ran.txt ]
  [ "$(sha256_of .vetdd/evidence/s1/meta.json)" = "$before" ]
}

@test "judge-layout.sh refuses an abandoned slice (usage, exit 2) and writes nothing" {
  record_good_slice s1 >/dev/null 2>&1
  worker s2
  WT abandon s2 --cause conflict >/dev/null
  printf '## Oracle\nx\n' > "$BATS_TEST_TMPDIR/reply.md"
  run JL --out "$BATS_TEST_TMPDIR/judge" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD s1 s2
  [ "$status" -eq 2 ]
  [[ "$output" == *"s2"*"abandoned"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/judge" ]
}

@test "arena-layout.sh refuses an abandoned lane (usage, exit 2) and writes nothing" {
  WT add ar-a1b2c3 -- sh test.sh >/dev/null
  (cd "$WTROOT/ar-a1b2c3" && mkdir -p .vetdd/notes && printf '## Design\nx\n' > .vetdd/notes/ar-a1b2c3-design.md \
    && red_slice ar-a1b2c3 && git commit -qm lane --allow-empty)
  WT check ar-a1b2c3 >/dev/null && WT remove ar-a1b2c3 --keep-branch >/dev/null
  WT abandon ar-a1b2c3 --cause lost >/dev/null
  run AL --out "$BATS_TEST_TMPDIR/arena" --base HEAD ar-a1b2c3
  [ "$status" -eq 2 ]
  [[ "$output" == *"ar-a1b2c3"*"abandoned"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/arena" ]
}

# --- docs --------------------------------------------------------------------------------------

@test "docs: swarm.md, arena.md, and stall.md say when the parent runs worktree.sh abandon, and with which cause" {
  local P="$SCRIPTS/../parallel" R="$SCRIPTS/../references"
  grep -qF 'worktree.sh" abandon <slice> --cause conflict --replaced-by <slice>-2' "$P/swarm.md"
  grep -qF 'worktree.sh" abandon <lane> --cause lost --replaced-by <the chosen lane>' "$P/arena.md"
  # A lane removed with --no-evidence has nothing to mark.
  grep -q 'whose evidence was brought back' "$P/arena.md"
  grep -qF 'worktree.sh" abandon <lane> --cause stall' "$P/arena.md"
  grep -qF 'worktree.sh" abandon <slice> --cause stall --replaced-by <slice>-r<n>' "$R/stall.md"
  # The losing lanes are marked before the grafts, whose commits stage the shared oracle file.
  sed -n '/^7\. \*\*Graft/p' "$P/arena.md" | awk '{ a = index($0, "--cause lost"); g = index($0, "Then graft"); exit !(a && g && a < g) }'
  # A slice of another language that ran a mutation audit needs it again before the --before-close check.
  grep -q 'of another language that ran a mutation audit needs it again' "$P/swarm.md"
  grep -q 'of another language that ran a mutation audit needs it again' "$P/arena.md"
  # The usage line names the subcommand.
  sed -n '1,/^set -u/p' "$SCRIPTS/worktree.sh" | grep -q 'worktree.sh abandon <slice> --cause stall|conflict|lost \[--replaced-by <id>\]'
}
