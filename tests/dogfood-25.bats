#!/usr/bin/env bats
# #25: what the 2026-10-06 dogfood run of test mode found (a fresh agent, ts-kata's February bug).

load test_helper

TEST_MD="$BATS_TEST_DIRNAME/../skills/vetdd/modes/test.md"
SKILL_MD="$BATS_TEST_DIRNAME/../skills/vetdd/SKILL.md"
JUDGE_PROMPT="$BATS_TEST_DIRNAME/../skills/vetdd/references/judge-prompt.md"
V="$BATS_TEST_DIRNAME/../fixtures/ts-kata/.claude/skills/verify-ts-kata/scripts"

# section <heading regex>: the lines of test.md from that heading to the next "## " heading.
section() { awk -v h="$1" '$0 ~ "^## " { on = ($0 ~ h) } on' "$TEST_MD"; }

@test "the mutation audit runs in Close, after the integrated runs and before check-evidence, not in step 5 (rule 10c)" {
  ! section '^## Per slice' | grep -q -- '--audit mutation'
  section '^## Close' | grep -q -- '--audit mutation'
  # In Close, the audit step comes after the integrated step and before check-evidence.
  local close; close="$(section '^## Close')"
  local i a c
  i="$(printf '%s\n' "$close" | grep -n 'integrated' | head -1 | cut -d: -f1)"
  a="$(printf '%s\n' "$close" | grep -n -- '--audit mutation' | head -1 | cut -d: -f1)"
  c="$(printf '%s\n' "$close" | grep -n 'check-evidence.sh' | head -1 | cut -d: -f1)"
  [ "$i" -lt "$a" ] && [ "$a" -lt "$c" ] || { echo "integrated $i, mutation $a, check-evidence $c"; false; }
}

@test "the refactor is optional, with when to skip it and how to say so" {
  local r; r="$(section 'refactor')"
  [[ "$r" == *"Skip it"* ]]
  [[ "$r" == *"Attention"* ]]
  ! grep -q '^Refactoring is not part of the loop, and the author does not do it (both source projects observed that authors skip it or drift). Spawn a refactorer:$' "$TEST_MD"
}

@test "an acceptance criterion on another surface than the agreed unit seam gets its own slice" {
  section '^## Per slice' | grep -q 'another surface'
}

@test "SKILL.md runs setup-project.sh once in a project vetdd has not run in" {
  grep -q 'setup-project.sh' "$SKILL_MD"
}

@test "the known-good calibration says its name filter is a different command, and why that is fine" {
  section '^## Per slice' | grep -q 'known-good'
  section '^## Per slice' | grep -q 'rule 8 binds the oracle to its files and version, not to the command'
}

@test "test.md says which runs take --test-report" {
  section '^## Per slice' | grep -q 'every run of the slice.s own test command'
}

@test "a single-label final verdict can be high confidence" {
  grep -q 'with one label' "$JUDGE_PROMPT"
}

@test "no paragraph of test.md runs past 250 words" {
  local longest
  longest="$(awk 'BEGIN{RS=""} { n = split($0, w, /[ \n]+/); if (n > m) m = n } END { print m }' "$TEST_MD")"
  [ "$longest" -le 250 ] || { echo "longest paragraph: $longest words"; false; }
}

@test "verify-due.sh takes --date, so the verify script can drive the February case" {
  run "$V/verify-due.sh" --date
  [ "$status" -eq 2 ]
  grep -q -- '--date' "$V/verify-due.sh"
  grep -q 'drive "$d" due "$date"' "$V/verify-due.sh"
}

@test "verify-due.sh --date drives the February case: the buggy kata is observed and not met (exit 1)" {
  [ -x "$BATS_TEST_DIRNAME/../fixtures/ts-kata/node_modules/.bin/tsx" ] || skip "fixtures/ts-kata/node_modules is missing (npm ci there)"
  local A="$BATS_TEST_TMPDIR/artifacts"
  VETDD_ARTIFACTS="$A" run "$V/verify-due.sh" --date 2026-02-15 --expect 'closing: 2026-02-28' --expect-due 'due: 2026-03-30'
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"actual line 1:   closing: 2026-03-31"* ]]
  run "$V/verify-due.sh" --date 15-02-2026
  [ "$status" -eq 2 ]
}
