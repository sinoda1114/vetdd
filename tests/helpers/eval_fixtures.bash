# Fixtures shared by the eval-mode tests (check-blind, sanitize-candidates, judge, check-verdict).

VERDICT_SCHEMA="$VETDD_ROOT/skills/vetdd/schemas/verdict.schema.json"

# A two-criterion rubric in the `## N. name` heading format.
write_rubric() {
  cat > "$1" <<'RUBRIC'
# Rubric (version 1)

## 1. correctness

- 2: the output file holds the literal value 42.
- 0: it does not.

## 2. clarity

- 2: the README explains how to run it.
- 0: it does not.
RUBRIC
}

# A valid two-label verdict matching write_rubric.
write_verdict() {
  cat > "$1" <<'JSON'
{
  "eval_id": "kata-1",
  "run_id": "20260926-1200",
  "rubric_version": 1,
  "labels": ["c1", "c2"],
  "criteria": [
    {"name": "correctness", "scores": [
      {"label": "c1", "score": 2, "evidence": "c1/artifact/value.txt:1 '42'"},
      {"label": "c2", "score": 1, "evidence": "c2/artifact/value.txt:1 '41'"}]},
    {"name": "clarity", "scores": [
      {"label": "c1", "score": 2, "evidence": "c1/artifact/README.md:3"},
      {"label": "c2", "score": 2, "evidence": "c2/artifact/README.md:2"}]}
  ],
  "verdicts": [{"label": "c1", "verdict": "pass"}, {"label": "c2", "verdict": "partial"}],
  "winner": "c1",
  "confidence": "mid",
  "conditions_check": {"applies": true, "note": "node v24 in both"},
  "disagreements": []
}
JSON
}

# Rewrite a JSON file with a jq filter.
jq_edit() {
  jq "$2" "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# A sanitized candidates directory with two labels, each with an artifact and evidence.
make_candidates() {
  CAND="$BATS_TEST_TMPDIR/run/candidates"
  local l
  for l in c1 c2; do
    mkdir -p "$CAND/$l/artifact" "$CAND/$l/evidence/s1"
    printf '42\n' > "$CAND/$l/artifact/value.txt"
    printf '# Kata\n\nRun it with sh run.sh\n' > "$CAND/$l/artifact/README.md"
    printf '{"slice_id":"s1","runs":[{"cmd":["npm","test"]}]}\n' > "$CAND/$l/evidence/s1/meta.json"
  done
}
