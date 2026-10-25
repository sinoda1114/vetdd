#!/usr/bin/env bats
# #60, #53, #56 item 1 (owner decision 2026-10-24): claims-match-evidence graded by the share of
# labeled lines, with one text in the final judge's rubric (v7) and the two eval rubrics
# (implement-business-days v5, rubric-calibration v2); the Result line exempt; a local log is a
# Measured path. Final v7 also counts an overridden-expectation calibration red, reads a planted red as
# a red for the planted defect, and lists artifact/verify-artifacts/ in its Layout. Docs only.

load test_helper

REF="$BATS_TEST_DIRNAME/../skills/vetdd/references"
FINAL="$REF/final-judge-rubric.md"
IBD="$BATS_TEST_DIRNAME/../evals/implement-business-days/rubric.md"
CAL="$BATS_TEST_DIRNAME/../evals/rubric-calibration/rubric.md"
REPLY="$REF/reply-format.md"
EVAL="$BATS_TEST_DIRNAME/../skills/vetdd/modes/eval.md"

# claims <rubric>: the shared body of its claims-match-evidence criterion, heading (and its number) left
# out, up to a rubric's own ### subsection (final v7 keeps its requirement condition there).
claims() { awk '/^## [0-9]+\. /{on = ($0 ~ /\. claims-match-evidence$/); next} /^### /{on = 0} on' "$1"; }

@test "the three rubrics carry their new versions" {
  head -1 "$FINAL" | grep -qx '# Final judge rubric (version 7)'
  head -1 "$IBD" | grep -qx '# Rubric (version 5)'
  head -1 "$CAL" | grep -qx '# Rubric (version 2)'
}

@test "claims-match-evidence is the same text in all three rubrics" {
  local f i c
  f="$(claims "$FINAL")"; i="$(claims "$IBD")"; c="$(claims "$CAL")"
  [ -n "$f" ]
  [ "$f" = "$i" ] || { diff <(printf '%s\n' "$f") <(printf '%s\n' "$i"); false; }
  [ "$f" = "$c" ] || { diff <(printf '%s\n' "$f") <(printf '%s\n' "$c"); false; }
}

@test "claims-match-evidence grades by share: at most 1 fault is 2, 80% labeled is 1" {
  local s two one zero
  s="$(claims "$FINAL")"
  two="$(printf '%s\n' "$s" | grep '^- 2:')"
  one="$(printf '%s\n' "$s" | grep '^- 1:')"
  zero="$(printf '%s\n' "$s" | grep '^- 0:')"
  [[ "$two" == *"at most 1"* ]]
  [[ "$two" == *"unlabeled"* && "$two" == *"without a path"* ]]
  [[ "$one" == *"80%"* ]]
  [[ "$zero" == *"contradicts the evidence"* ]]
  [[ "$zero" == *"check-evidence"* ]]
  [[ "$zero" == *"no factual line"* ]]
}

@test "claims-match-evidence says how lines are counted, exempts the Result line, and takes a local log as a path" {
  local s
  s="$(claims "$FINAL" | tr '\n' ' ')"
  [[ "$s" == *"one sentence, one bullet, or one table row"* ]]
  [[ "$s" == *'"Every row is Measured"'* && "$s" == *"right after the table"* ]]
  [[ "$s" == *"Result line"* ]]
  [[ "$s" == *"local log"* ]]
}

@test "final v7 criterion 1 counts an overridden-expectation calibration red and reads a planted red as the planted defect's" {
  local s
  s="$(sed -n '/^## 1\. /,/^## 2\. /p' "$FINAL" | tr '\n' ' ')"
  [[ "$s" == *"--expect"* && "$s" == *"calibrate.sh plant"* ]]
  [[ "$s" == *"red of that version"* ]]
  [[ "$s" == *'planted: {patch, sha256, files}'* ]]
  [[ "$s" == *"<seq>-planted.patch"* ]]
  [[ "$s" == *"not for the original one"* ]]
}

@test "final v7 Layout lists artifact/verify-artifacts/" {
  sed -n '/^```/,/^```/p' "$FINAL" | grep -q 'artifact/verify-artifacts/'
}

@test "the three rubrics pass the judge's blind check (judge.sh copies each into the judge's input)" {
  local r
  for r in "$FINAL" "$IBD" "$CAL"; do
    rm -rf "$BATS_TEST_TMPDIR/rb" && mkdir -p "$BATS_TEST_TMPDIR/rb" && cp "$r" "$BATS_TEST_TMPDIR/rb/rubric.md"
    run "$SCRIPTS/check-blind.sh" "$BATS_TEST_TMPDIR/rb" --profile judge
    [ "$status" -eq 0 ] || { echo "$r: $output"; false; }
  done
}

@test "reply-format keeps the Result line label without claiming the final rubric has no exception for it" {
  local labels
  labels="$(sed -n '/^## Labels/,/^## /p' "$REPLY" | tr '\n' ' ')"
  [[ "$labels" == *"The Result line carries a label too"* ]]
  [[ "$labels" != *"has no exception for it"* ]]
}

@test "reply-format's template cites artifact/check-evidence.txt unconditionally; the human reply adds the local log" {
  local tline labels
  tline="$(sed -n '/^```/,/^```/p' "$REPLY" | grep '^Every row is Measured')"
  [[ "$tline" == *"(Measured: artifact/check-evidence.txt;"* && "$tline" == *"local log"* ]]
  [[ "$tline" != *"judge-layout.sh built"* ]]
  labels="$(sed -n '/^## Labels/,/^## /p' "$REPLY" | tr '\n' ' ')"
  [[ "$labels" == *"artifact/check-evidence.txt"* && "$labels" == *"local log"* ]]
  [[ "$labels" == *"reply to the human"* ]]
}

@test "eval.md dates the index.tsv ts change by run, not by a time the file cannot show" {
  local note
  note="$(sed -n '/^evals\/$/,/^  <eval-id>\//p' "$EVAL" | tr '\n' ' ')"
  [[ "$note" != *"written before 2026-10-17 19:22"* ]]
  [[ "$note" == *"20261018-v4-cal"* ]]
}

@test "final v7 keeps v6's requirement-to-evidence condition as its own subsection of claims-match-evidence (owner decision 2026-10-25)" {
  local s sub
  s="$(sed -n '/^## 5\. claims-match-evidence/,/^## 6\. /p' "$FINAL")"
  sub="$(printf '%s\n' "$s" | sed -n '/^### /,$p' | tr '\n' ' ')"
  [[ "$sub" == *"every requirement in artifact/reply.md maps to an evidence path that exists in this layout (or is named as a local log) and shows the stated outcome"* ]]
  [[ "$sub" == *"at most 1"* ]]
  # The eval rubrics share the claims text but not this condition.
  ! grep -q 'every requirement in artifact/reply.md maps' "$IBD" || false
  ! grep -q 'every requirement in artifact/reply.md maps' "$CAL" || false
}
