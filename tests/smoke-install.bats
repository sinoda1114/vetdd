#!/usr/bin/env bats
# Clean install smoke (Phase 7): install.sh into an empty HOME, then one slice through the installed
# copy only: setup-project, red and green through evidence.sh, the pre-commit hook, check-evidence,
# judge-layout, and judge.sh with a fake codex. Nothing from the checkout runs after install.sh.

load test_helper

setup() {
  isolate_git
  unset CODEX_HOME
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  "$BATS_TEST_DIRNAME/../install.sh" > "$BATS_TEST_TMPDIR/install.log" 2>&1 || true
  V="$CLAUDE_CONFIG_DIR/skills/vetdd/scripts"
  # A fake codex with a file login: the isolation flags, login status, and a verdict for one label.
  mkdir -p "$BATS_TEST_TMPDIR/fake" "$HOME/.codex"
  printf '{"token":"t"}\n' > "$HOME/.codex/auth.json"
  cat > "$BATS_TEST_TMPDIR/fake/codex" <<'FAKE'
#!/bin/sh
if [ "$1" = exec ] && [ "${2:-}" = --help ]; then printf '  --ephemeral\n  --ignore-user-config\n  --ignore-rules\n'; exit 0; fi
if [ "$1" = login ]; then echo "Logged in using ChatGPT"; exit 0; fi
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
cat > /dev/null
jq -n '{eval_id: "smoke", run_id: "r1", rubric_version: 6, labels: ["c1"],
  criteria: (["red-before-green", "final-evidence-matches-delivery", "test-observes-behavior",
              "smallest-change", "claims-match-evidence", "conditions-apply"]
             | map({name: ., scores: [{label: "c1", score: 2, evidence: "c1/artifact/diff.patch:1"}]})),
  verdicts: [{label: "c1", verdict: "pass"}], winner: "none", confidence: "mid",
  conditions_check: {applies: true, note: "none recorded"}, disagreements: []}' > "$out"
FAKE
  chmod +x "$BATS_TEST_TMPDIR/fake/codex"
}

@test "a clean install runs one slice end to end through the installed copy" {
  [ -x "$V/evidence.sh" ] || { echo "install.sh did not install:"; cat "$BATS_TEST_TMPDIR/install.log"; false; }
  make_repo
  run "$V/setup-project.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qF "$V" .git/hooks/pre-commit

  # Red, then green, through the installed evidence.sh.
  run "$V/evidence.sh" s1 before --seam unit --oracle-version v1 --oracle-file test.sh -- sh test.sh
  [ "$(jq -r '.runs[-1].outcome' .vetdd/evidence/s1/meta.json)" = target_failure ] || { echo "$output"; false; }
  printf '42\n' > value.txt
  run "$V/evidence.sh" s1 after -- sh test.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }

  run "$V/check-evidence.sh" s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"s1: OK"* ]]

  # The pre-commit hook the installed setup-project.sh put in place lets the change in.
  git add value.txt
  run git commit -q -m "fix: value is 42"
  [ "$status" -eq 0 ] || { echo "$output"; false; }

  printf '## Oracle\nvalue.txt holds 42\n' > "$BATS_TEST_TMPDIR/reply.md"
  run "$V/judge-layout.sh" --out "$BATS_TEST_TMPDIR/judge/candidates" --reply "$BATS_TEST_TMPDIR/reply.md" --base HEAD~1 s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"$V/judge.sh"* ]]

  # Only judge.sh gets the fake: evidence.sh records the names of VETDD_* variables it runs under.
  VETDD_CODEX_BIN="$BATS_TEST_TMPDIR/fake/codex" run "$V/judge.sh" --rubric "$CLAUDE_CONFIG_DIR/skills/vetdd/references/final-judge-rubric.md" \
    --candidates "$BATS_TEST_TMPDIR/judge/candidates" --out "$BATS_TEST_TMPDIR/judge/judge.json" \
    --eval-id smoke --run-id r1 --rubric-version 6
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -r '.verdicts[0].verdict' "$BATS_TEST_TMPDIR/judge/judge.json")" = pass ]
}
