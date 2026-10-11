#!/usr/bin/env bats
# Phase 6, PR 3: a stall and its exits (references/stall.md). A slice stalls when K+1 failed attempts
# (after runs that ended target_failure, K = 2 by default) in a row do not lower the failure count
# (the runner's report, tests.failed, else 1 per attempt); infrastructure errors never count, and a
# green or a new oracle version starts over. Before each redesign the diagnosis goes in a handover
# file (handover.sh); check-evidence rule 11 asks for one per stall in the record, with every heading.

load test_helper

setup() { make_repo; }

ST() { "$SCRIPTS/stall.sh" "$@"; }
HO() { "$SCRIPTS/handover.sh" "$@"; }

# red, then <n> failed attempts (value stays wrong).
attempts() {
  printf '0\n' > value.txt
  ev s1 before --seam unit --oracle-version v1 --oracle-file test.sh -- sh test.sh >/dev/null 2>&1
  local i; for i in $(seq 1 "$1"); do ev s1 after -- sh test.sh >/dev/null 2>&1 || true; done
}

# set_failed <counts...>: the failed attempts get these tests.failed counts, in order.
set_failed() {
  local counts; counts="$(printf '%s\n' "$@" | jq -s -c .)"
  local f="$REPO/.vetdd/evidence/s1/meta.json"
  jq --argjson c "$counts" '[.runs[] | select(.kind == "after" and .outcome == "target_failure") | .seq] as $s
    | .runs |= map(. as $r | ($s | index($r.seq)) as $i
      | if $i == null then $r else $r + {tests: {format: "jest-json", status: "ok", passed: 0, failed: $c[$i], skipped: 0, todo: 0, other: 0, total: $c[$i], sha256: "x"}} end)' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

draft() {
  printf '## Unmet requirement\nweekend rollover\n## Expected and actual\n2026-06-01, got 2026-05-30\n## Minimal reproduction\npaymentDueDate("2026-04-30", 30, {rollover})\n## Hypotheses tried\nUTC day\n## Why it failed\nthe step table was never read\n## Reusable results\nthe test\n' > "$BATS_TEST_TMPDIR/draft.md"
  printf '%s' "$BATS_TEST_TMPDIR/draft.md"
}

@test "three failed attempts without a count report are a stall (exit 3); two are not" {
  attempts 2
  run ST s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"not stalled"* ]]
  ev s1 after -- sh test.sh >/dev/null 2>&1 || true
  run ST s1
  [ "$status" -eq 3 ]
  [[ "$output" == *"stalled"* ]]
}

@test "a falling failure count is progress, not a stall" {
  attempts 3
  set_failed 3 2 1
  run ST s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  set_failed 3 3 4
  run ST s1
  [ "$status" -eq 3 ]
  [[ "$output" == *"3 3 4"* ]]
}

@test "an infrastructure error never counts, and a green starts over" {
  attempts 2
  ev s1 after --outcome infrastructure_error -- sh test.sh >/dev/null 2>&1 || true
  run ST s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '42\n' > value.txt && ev s1 after -- sh test.sh >/dev/null 2>&1
  printf '0\n' > value.txt
  ev s1 after -- sh test.sh >/dev/null 2>&1 || true
  ev s1 after -- sh test.sh >/dev/null 2>&1 || true
  run ST s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "--k changes how many attempts make a stall" {
  attempts 2
  run ST s1 --k 1
  [ "$status" -eq 3 ]
}

@test "handover.sh records a draft with every heading as handover-1, then handover-2" {
  attempts 3
  run HO s1 --file "$(draft)"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f .vetdd/evidence/s1/handover-1.md ]
  run HO s1 --file "$(draft)"
  [ -f .vetdd/evidence/s1/handover-2.md ]
}

@test "handover.sh refuses a draft that lacks a heading, and a slice with no evidence (usage, exit 2)" {
  attempts 1
  grep -v '^## Hypotheses tried' "$(draft)" > "$BATS_TEST_TMPDIR/bad.md"
  run HO s1 --file "$BATS_TEST_TMPDIR/bad.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Hypotheses tried"* ]]
  [ ! -e .vetdd/evidence/s1/handover-1.md ]
  run HO nope --file "$(draft)"
  [ "$status" -eq 2 ]
}

@test "rule 11: a stall in the record without a handover is a WARN, and a handover clears it" {
  attempts 3
  printf '42\n' > value.txt && ev s1 after -- sh test.sh >/dev/null 2>&1
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"s1: WARN (11: "*"handover"* ]]
  HO s1 --file "$(draft)" >/dev/null
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "s1: OK" ]
}

@test "rule 11: a handover missing a heading fails the slice" {
  attempts 3
  printf '42\n' > value.txt && ev s1 after -- sh test.sh >/dev/null 2>&1
  HO s1 --file "$(draft)" >/dev/null
  sed -i.bak '/^## Why it failed$/d' .vetdd/evidence/s1/handover-1.md && rm -f .vetdd/evidence/s1/handover-1.md.bak
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL (11: handover-1.md"*"Why it failed"* ]]
}

@test "r1: attempts of different commands are separate sequences; a pass of one does not reset another" {
  printf '0\n' > value.txt
  ev s1 before --seam unit --oracle-version v1 --oracle-file test.sh -- sh test.sh >/dev/null 2>&1
  local i; for i in 1 2; do
    ev s1 after -- sh test.sh >/dev/null 2>&1 || true
    ev s1 after -- sh -c 'true' >/dev/null 2>&1
  done
  ev s1 after -- sh test.sh >/dev/null 2>&1 || true
  # Checked right after the attempt, as test mode step 5 says.
  run ST s1
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  ev s1 after -- sh -c 'true' >/dev/null 2>&1
  run ST s1
  [[ "$output" == *"1 stalls so far"* ]]
}

@test "r1: an attempt whose count is unknown or zero (no usable report) is no progress" {
  attempts 3
  set_failed 3 0 3
  run ST s1
  [ "$status" -eq 3 ] || { echo "$output"; false; }
}

@test "r1: --k refuses a leading zero" {
  attempts 1
  run ST s1 --k 08
  [ "$status" -eq 2 ]
}

@test "r1: stall.sh says how many stalls the record holds (the redesign budget used)" {
  attempts 6
  run ST s1
  [[ "$output" == *"2 stalls so far"* ]]
}

@test "r1: handover.sh refuses a linked .vetdd or .vetdd/evidence, and takes a draft with CRLF line ends" {
  attempts 1
  tr -d '\r' < "$(draft)" | sed 's/$/\r/' > "$BATS_TEST_TMPDIR/crlf.md"
  run HO s1 --file "$BATS_TEST_TMPDIR/crlf.md"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  mkdir -p "$BATS_TEST_TMPDIR/outside"
  mv .vetdd/evidence "$BATS_TEST_TMPDIR/outside/evidence" && ln -s "$BATS_TEST_TMPDIR/outside/evidence" .vetdd/evidence
  run HO s1 --file "$(draft)"
  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/outside/evidence/s1/handover-2.md" ]
}

@test "r1: the briefs tell an author to stop and report a stall; SKILL.md names K in Q3" {
  grep -q 'stall.sh' "$SCRIPTS/../references/subagent-brief.md"
  grep -q 'stall K' "$SCRIPTS/../SKILL.md"
}

@test "a slice with no stall in its record is not asked for a handover" {
  record_good_slice s1
  run check s1
  [ "$status" -eq 0 ]
  [ "$output" = "s1: OK" ]
}

@test "docs: stall.md names the two exits and their limits; test mode and SKILL.md point to it" {
  local s="$SCRIPTS/../references/stall.md"
  [ -f "$s" ]
  grep -q 'stall.sh' "$s" && grep -q 'handover.sh' "$s"
  grep -qi 'redesign' "$s" && grep -q '1a' "$s"
  grep -q 'blocked' "$s"
  grep -q 'references/stall.md' "$SCRIPTS/../modes/test.md"
  grep -q 'references/stall.md' "$SCRIPTS/../SKILL.md"
  grep -q 'stall' "$SCRIPTS/../parallel/arena.md"
}

# --- review round 2 ----------------------------------------------------------------------------------

@test "r2: a new oracle version clears a stall of the old one, even when another command fails next" {
  attempts 3
  printf '# v2\n' >> test.sh && git add test.sh && git commit -qm v2
  "$SCRIPTS/oracle-version.sh" s1 --version v2 --change implementation --reason 'stronger test' >/dev/null
  ev s1 before --oracle-version v2 --oracle-file test.sh -- sh test.sh >/dev/null 2>&1
  ev s1 after -- sh -c 'exit 1' >/dev/null 2>&1 || true
  run ST s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "r2: after a stall every command starts over: one failure of another command is not a second stall" {
  printf '0\n' > value.txt
  ev s1 before --seam unit --oracle-version v1 --oracle-file test.sh -- sh test.sh >/dev/null 2>&1
  ev s1 after -- sh -c 'exit 1' >/dev/null 2>&1 || true
  ev s1 after -- sh -c 'exit 1' >/dev/null 2>&1 || true
  local i; for i in 1 2 3; do ev s1 after -- sh test.sh >/dev/null 2>&1 || true; done
  ev s1 after -- sh -c 'exit 1' >/dev/null 2>&1 || true
  run ST s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"1 stalls so far"* ]]
}

@test "r2: stall.sh prints nothing a record could inject: a count that is not a number is ignored" {
  attempts 3
  local f="$REPO/.vetdd/evidence/s1/meta.json"
  jq '(.runs[] | select(.kind == "after")) += {tests: {format: "jest-json", status: "ok", passed: 0, failed: "\u001b[31mx", skipped: 0, todo: 0, other: 0, total: 1, sha256: "x"}}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  run ST s1
  [ "$status" -eq 3 ]
  if printf '%s' "$output" | LC_ALL=C grep -q "$(printf '\033')"; then false; fi
}

@test "r2: when not stalled, the counts shown are those of the command that ran last" {
  printf '0\n' > value.txt
  ev s1 before --seam unit --oracle-version v1 --oracle-file test.sh -- sh test.sh >/dev/null 2>&1
  ev s1 after -- sh -c 'exit 1' >/dev/null 2>&1 || true
  ev s1 after -- sh -c 'exit 1' >/dev/null 2>&1 || true
  ev s1 after -- sh test.sh >/dev/null 2>&1 || true
  run ST s1
  [[ "$output" == *"since the last green: 1;"* ]]
}

@test "r2: a handover link that points nowhere fails rule 11; handover files are readable (0644)" {
  attempts 3
  HO s1 --file "$(draft)" >/dev/null
  [ "$(ls -l .vetdd/evidence/s1/handover-1.md | cut -c1-10)" = "-rw-r--r--" ]
  ln -s "$BATS_TEST_TMPDIR/nowhere" .vetdd/evidence/s1/handover-2.md
  printf '42\n' > value.txt && ev s1 after -- sh test.sh >/dev/null 2>&1
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"handover-2.md is a link"* ]]
}

@test "r2: a stalled worker commits its work in progress and stops; the redesign is a new slice id" {
  grep -q 'commit your work in progress' "$SCRIPTS/../references/subagent-brief.md"
  grep -q -- '-r<n>' "$SCRIPTS/../references/stall.md"
}

@test "PR #43: a stalled worker's WIP commit skips the evidence hook (VETDD_BYPASS=1), since its latest after is red" {
  grep -q 'VETDD_BYPASS=1 git commit -m "wip: stalled"' "$SCRIPTS/../references/subagent-brief.md"
  grep -q 'VETDD_BYPASS=1' "$SCRIPTS/../references/stall.md"
}

@test "triage: test mode and the brief pass the agreed K to stall.sh" {
  grep -q 'stall.sh" <slice> --k <the agreed K>' "$SCRIPTS/../modes/test.md"
  grep -q 'stall.sh <slice-id> --k <the agreed K>' "$SCRIPTS/../references/subagent-brief.md"
}
