#!/usr/bin/env bats
# check-verdict.sh: schema plus the cross-field rules of a judge verdict. Exit code = number of problems.

load test_helper
load helpers/eval_fixtures

setup() {
  V="$BATS_TEST_TMPDIR/judge.json"
  write_verdict "$V"
  RUBRIC="$BATS_TEST_TMPDIR/rubric.md"
  write_rubric "$RUBRIC"
}

cv() { "$SCRIPTS/check-verdict.sh" "$@"; }

@test "a valid verdict prints OK and exits 0" {
  run cv "$V"
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "a schema violation is reported as FAIL (schema ...)" {
  jq_edit "$V" '.criteria[0].scores[0].score = 3'
  run cv "$V"
  [ "$status" -ge 1 ]
  [[ "$output" == "FAIL (schema"* ]]
  [[ "$output" == *"/criteria/0/scores/0/score"* ]]
}

@test "an unknown top-level field is a schema violation" {
  jq_edit "$V" '._judge = {"model": "x"}'
  run cv "$V"
  [ "$status" -ge 1 ]
  [[ "$output" == *"FAIL (schema"*"_judge"* ]]
}

@test "a file that is not JSON fails without crashing" {
  printf 'not json\n' > "$V"
  run cv "$V"
  [ "$status" -eq 1 ]
  [[ "$output" == "FAIL ("*"JSON"* ]]
}

@test "a label without a score on a criterion fails, naming the criterion and the label" {
  jq_edit "$V" 'del(.criteria[1].scores[] | select(.label == "c2"))'
  run cv "$V"
  [ "$status" -eq 1 ]
  [[ "$output" == "FAIL ("*"clarity"*"c2"* ]]
}

@test "a score without an evidence citation fails" {
  jq_edit "$V" '(.criteria[0].scores[] | select(.label == "c1") | .evidence) = ""'
  run cv "$V"
  [ "$status" -eq 1 ]
  [[ "$output" == "FAIL ("*"correctness"*"c1"* ]]
}

@test "a duplicated label, score, or verdict entry fails" {
  jq_edit "$V" '.labels = ["c1", "c1", "c2"]'
  run cv "$V"
  [ "$status" -ge 1 ]
  [[ "$output" == *"FAIL (labels: duplicate c1)"* ]]
  write_verdict "$V"
  jq_edit "$V" '.criteria[0].scores += [.criteria[0].scores[0]]'
  run cv "$V"
  [ "$status" -eq 1 ]
  [[ "$output" == "FAIL ("*"correctness"*"more than one score for c1"* ]]
  write_verdict "$V"
  jq_edit "$V" '.verdicts += [.verdicts[0]]'
  run cv "$V"
  [ "$status" -eq 1 ]
  [[ "$output" == "FAIL ("*"verdicts"*"more than one entry for c1"* ]]
}

@test "a score for a label outside labels fails" {
  jq_edit "$V" '.criteria[0].scores += [{label: "c9", score: 1, evidence: "x"}]'
  run cv "$V"
  [ "$status" -eq 1 ]
  [[ "$output" == "FAIL ("*"unknown label c9"* ]]
}

@test "a label missing from verdicts fails" {
  jq_edit "$V" 'del(.verdicts[] | select(.label == "c2"))'
  run cv "$V"
  [ "$status" -eq 1 ]
  [[ "$output" == "FAIL ("*"verdicts"*"c2"* ]]
}

@test "the exit code is the number of problems" {
  jq_edit "$V" '(.criteria[0].scores[] | select(.label == "c1") | .evidence) = "" | del(.verdicts[] | select(.label == "c2"))'
  run cv "$V"
  [ "$status" -eq 2 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "with one label the winner must be none" {
  jq_edit "$V" '.labels = ["c1"] | .criteria |= map(.scores |= map(select(.label == "c1"))) | .verdicts = [{label: "c1", verdict: "pass"}] | .winner = "c1"'
  run cv "$V"
  [ "$status" -eq 1 ]
  [[ "$output" == "FAIL ("*"winner"*"none"* ]]
  jq_edit "$V" '.winner = "none"'
  run cv "$V"
  [ "$output" = "OK" ]
}

@test "with two labels the winner is a label or tie, never none or an unknown label" {
  jq_edit "$V" '.winner = "none"'
  run cv "$V"
  [ "$status" -eq 1 ]
  [[ "$output" == "FAIL ("*"winner"* ]]
  jq_edit "$V" '.winner = "c3"'
  run cv "$V"
  [ "$status" -eq 1 ]
  jq_edit "$V" '(.criteria[0].scores[] | select(.label == "c2") | .score) = 2 | (.verdicts[] | select(.label == "c2") | .verdict) = "pass" | .winner = "tie"'
  run cv "$V"
  [ "$output" = "OK" ]
}

@test "--labels must match the verdict's labels exactly" {
  run cv "$V" --labels c1,c2
  [ "$output" = "OK" ]
  run cv "$V" --labels c1,c2,c3
  [ "$status" -eq 1 ]
  [[ "$output" == "FAIL ("*"labels"* ]]
  run cv "$V" --labels c1
  [ "$status" -eq 1 ]
}

@test "--rubric requires criterion names to match the ## N. headings in order" {
  run cv "$V" --rubric "$RUBRIC"
  [ "$output" = "OK" ]
  jq_edit "$V" '.criteria |= reverse'
  run cv "$V" --rubric "$RUBRIC"
  [ "$status" -ge 1 ]
  [[ "$output" == "FAIL ("*"criteria"* ]]
}

@test "--rubric accepts a criterion name that repeats the heading number" {
  jq_edit "$V" '.criteria[0].name = "1. correctness"'
  run cv "$V" --rubric "$RUBRIC"
  [ "$output" = "OK" ]
}

@test "--rubric fails when the verdict has fewer criteria than the rubric" {
  jq_edit "$V" '.criteria |= .[:1]'
  run cv "$V" --rubric "$RUBRIC"
  [ "$status" -ge 1 ]
  [[ "$output" == *"clarity"* ]]
}

@test "the shipped validator agrees with ajv on valid and invalid verdicts" {
  local lib="$SCRIPTS/lib/validate-json.mjs" ajv="$BATS_TEST_DIRNAME/helpers/validate-schema.mjs"
  node "$lib" "$VERDICT_SCHEMA" "$V"
  node "$ajv" "$VERDICT_SCHEMA" "$V"
  local f
  for f in '.criteria[0].scores[0].score = 3' '.extra = 1' 'del(.winner)' '.labels = ["x1"]' \
           '.confidence = "certain"' '.labels = []' '.rubric_version = 0' '.verdicts[0].verdict = "ok"' \
           '.conditions_check.applies = "yes"' 'del(.criteria[0].scores[0].evidence)' '.disagreements = [1]'; do
    jq "$f" "$V" > "$BATS_TEST_TMPDIR/bad.json"
    run node "$lib" "$VERDICT_SCHEMA" "$BATS_TEST_TMPDIR/bad.json"
    [ "$status" -eq 1 ] || { echo "shipped validator accepted: $f"; false; }
    run node "$ajv" "$VERDICT_SCHEMA" "$BATS_TEST_TMPDIR/bad.json"
    [ "$status" -eq 1 ] || { echo "ajv accepted: $f"; false; }
  done
}

@test "a label's verdict must follow from its scores: pass iff all 2, fail iff any 0, else partial" {
  jq_edit "$V" '(.verdicts[] | select(.label == "c2") | .verdict) = "pass"'
  run cv "$V"
  [ "$status" -eq 1 ]
  [[ "$output" == "FAIL (verdicts: c2 is pass, but its scores make it partial)" ]]
  write_verdict "$V"
  jq_edit "$V" '(.criteria[0].scores[] | select(.label == "c2") | .score) = 0 | .confidence = "high"'
  run cv "$V"
  [ "$status" -eq 1 ]
  [[ "$output" == *"c2 is partial, but its scores make it fail"* ]]
  jq_edit "$V" '(.verdicts[] | select(.label == "c2") | .verdict) = "fail"'
  run cv "$V"
  [ "$output" = "OK" ]
}

@test "the winner must be the label with the strictly highest total, tie when the top totals are equal" {
  jq_edit "$V" '.winner = "c2"'
  run cv "$V"
  [ "$status" -eq 1 ]
  [[ "$output" == *"winner: expected c1"*"got c2"* ]]
  jq_edit "$V" '.winner = "tie"'
  run cv "$V"
  [ "$status" -eq 1 ]
  [[ "$output" == *"winner: expected c1"*"got tie"* ]]
  jq_edit "$V" '(.criteria[0].scores[] | select(.label == "c2") | .score) = 2 | (.verdicts[] | select(.label == "c2") | .verdict) = "pass" | .winner = "c1"'
  run cv "$V"
  [ "$status" -eq 1 ]
  [[ "$output" == *"winner: expected tie"*"got c1"* ]]
}

@test "inconclusive is allowed for any label, but an inconclusive label is never the winner" {
  jq_edit "$V" '(.verdicts[] | select(.label == "c2") | .verdict) = "inconclusive"'
  run cv "$V"
  [ "$output" = "OK" ]
  write_verdict "$V"
  jq_edit "$V" '(.verdicts[] | select(.label == "c1") | .verdict) = "inconclusive"'
  run cv "$V"
  [ "$status" -eq 1 ]
  [[ "$output" == *"winner"*"c1"*"inconclusive"* ]]
}

@test "--eval-id, --run-id, and --rubric-version must equal the verdict's fields" {
  run cv "$V" --eval-id kata-1 --run-id 20260926-1200 --rubric-version 1
  [ "$output" = "OK" ]
  run cv "$V" --eval-id kata-2 --run-id 20260926-1300 --rubric-version 2
  [ "$status" -eq 3 ]
  [[ "$output" == *"FAIL (eval_id: expected kata-2, got kata-1)"* ]]
  [[ "$output" == *"FAIL (run_id: expected 20260926-1300, got 20260926-1200)"* ]]
  [[ "$output" == *"FAIL (rubric_version: expected 2, got 1)"* ]]
}

@test "usage and tool errors exit 126, never a problem count" {
  run cv
  [ "$status" -eq 126 ]
  run cv "$V" --bogus
  [ "$status" -eq 126 ]
  run cv "$BATS_TEST_TMPDIR/nope.json"
  [ "$status" -eq 126 ]
  run cv "$V" --rubric-version x
  [ "$status" -eq 126 ]
}

@test "G10: values from the verdict are printed without control characters" {
  jq_edit "$V" '.eval_id = "x\u001b]52;c;Zm9v\u0007y"'
  run cv "$V" --eval-id kata-1
  [ "$status" -ge 1 ]
  [[ "$output" != *$'\033'* ]]
  [[ "$output" != *$'\007'* ]]
}
