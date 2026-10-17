#!/usr/bin/env bats
# judge.sh: renders the judge prompt, runs codex read-only in a private copy of the candidates, checks the verdict.
# The real codex is never called: VETDD_CODEX_BIN points to a fake, and a guard `codex` on PATH fails loudly.

load test_helper
load helpers/eval_fixtures

setup() {
  isolate_git
  make_candidates
  printf '{"c1": "alpha-lane", "c2": "beta-lane"}\n' > "$BATS_TEST_TMPDIR/run/variants.json"
  RUBRIC="$BATS_TEST_TMPDIR/rubric.md"
  write_rubric "$RUBRIC"
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJ/runs"
  git -C "$PROJ" init -q
  OUT="$PROJ/runs/judge.json"
  LOG="$PROJ/.vetdd/judge-logs/kata-1-20260926-1200.log"
  REPLY="$BATS_TEST_TMPDIR/reply.json"
  write_verdict "$REPLY"

  mkdir -p "$BATS_TEST_TMPDIR/guard" "$BATS_TEST_TMPDIR/fake"
  printf '#!/bin/sh\necho "the real codex must not be called from tests" >&2\nexit 99\n' > "$BATS_TEST_TMPDIR/guard/codex"
  chmod +x "$BATS_TEST_TMPDIR/guard/codex"
  export PATH="$BATS_TEST_TMPDIR/guard:$PATH"

  export FAKE_ARGS="$BATS_TEST_TMPDIR/fake/args.txt"
  export FAKE_STDIN="$BATS_TEST_TMPDIR/fake/stdin.txt"
  export FAKE_REPLY="$REPLY"
  export FAKE_SEEN="$BATS_TEST_TMPDIR/fake/seen"
  cat > "$BATS_TEST_TMPDIR/fake/codex" <<'FAKE'
#!/bin/sh
# Fake codex: `login status` honours FAKE_LOGGED_OUT; `exec` records argv and stdin, then writes FAKE_REPLY to -o.
# `exec --help` lists the isolation flags unless FAKE_OLD_CODEX is set.
# FAKE_SHIM=<dir under HOME>: codex behind a node version manager's shim, which finds its versions
# in MISE_DATA_DIR, else under $HOME, and fails without them on every call.
if [ -n "${FAKE_SHIM:-}" ] && [ ! -d "${MISE_DATA_DIR:-${HOME:-/nonexistent}/$FAKE_SHIM}" ]; then
  echo "mise ERROR No version is set for shim: codex" >&2; exit 1
fi
# FAKE_VERSION_READS: a codex that reads stdin when asked its version (what it got is recorded).
[ "$1" != --version ] || { [ -z "${FAKE_VERSION_READS:-}" ] || cat > "$FAKE_SEEN.version_stdin"; echo "codex-cli 0.0.0-fake"; exit 0; }
if [ "$1" = exec ] && [ "${2:-}" = --help ]; then
  printf '%s\n' "${HOME:-unset}" > "$FAKE_SEEN.home_env.help"
  [ -n "${FAKE_OLD_CODEX:-}" ] || printf '      --ephemeral\n      --ignore-user-config\n      --ignore-rules\n'
  exit 0
fi
# Which CODEX_HOME each call ran with, and what it held.
printf '%s %s\n' "$1" "${CODEX_HOME:-unset}" >> "$FAKE_SEEN.homes"
printf '%s\n' "${HOME:-unset}" > "$FAKE_SEEN.home_env.$1"
env > "$FAKE_SEEN.env.$1"
[ -z "${CODEX_HOME:-}" ] || { ls -A "$CODEX_HOME"; [ ! -e "$CODEX_HOME/auth.json" ] && [ ! -L "$CODEX_HOME/auth.json" ] || [ -r "$CODEX_HOME/auth.json" ] || echo unreadable-auth; } > "$FAKE_SEEN.home.$1" 2>/dev/null
if [ "$1" = login ] && [ "$2" = status ]; then
  printf '%s\n' "$@" > "$FAKE_SEEN.login_args"
  if [ -n "${FAKE_LOGGED_OUT:-}" ]; then echo "Not logged in"; exit 1; fi
  echo "Logged in using ChatGPT"; exit 0
fi
out=""; cdir=""; prev=""
for a in "$@"; do
  printf '%s\n' "$a" >> "$FAKE_ARGS"
  [ "$prev" = "-o" ] && out="$a"
  [ "$prev" = "-C" ] && cdir="$a"
  prev="$a"
done
cat > "$FAKE_STDIN"
[ -n "$out" ] || { echo "fake codex: no -o given" >&2; exit 64; }
# What the judge could see from its working directory, and what TMPDIR held during the run.
(cd "$cdir" && find . | sort > "$FAKE_SEEN.tree"
 [ ! -e ../variants.json ] || echo reachable > "$FAKE_SEEN.variants"
 ls -A .. > "$FAKE_SEEN.parent" 2>/dev/null; find .. -path ../judge -prune -o -type f -print 2>/dev/null | sort > "$FAKE_SEEN.parentfiles"
 git rev-parse --show-toplevel > "$FAKE_SEEN.git" 2>/dev/null || rm -f "$FAKE_SEEN.git")
ls -Ap "${TMPDIR:-/nonexistent}" > "$FAKE_SEEN.tmpdir" 2>/dev/null
echo "fake codex transcript line"
echo "fake codex progress" >&2
[ -z "${FAKE_EXEC_FAIL:-}" ] || { printf 'fake codex: simulated \033[31mfailure\033[0m\n' >&2; exit 1; }
# A token refresh that writes a new auth.json in place of the link (temporary file, then rename).
[ -z "${FAKE_REFRESH:-}" ] || { printf '%s\n' "$FAKE_REFRESH" > "$CODEX_HOME/auth.json.tmp" && mv -f "$CODEX_HOME/auth.json.tmp" "$CODEX_HOME/auth.json"; }
# The user's own codex refreshing its login meanwhile, in another terminal.
[ -z "${FAKE_USER_AUTH:-}" ] || printf '{"token":"newer"}\n' > "$FAKE_USER_AUTH"
cp "$FAKE_REPLY" "$out"
FAKE
  chmod +x "$BATS_TEST_TMPDIR/fake/codex"
  export VETDD_CODEX_BIN="$BATS_TEST_TMPDIR/fake/codex"
  # codex runs with an allowlisted environment: the fake's own variables are kept by name.
  export VETDD_JUDGE_KEEP_ENV="FAKE_VERSION_READS FAKE_ARGS FAKE_EXEC_FAIL FAKE_LOGGED_OUT FAKE_OLD_CODEX FAKE_REFRESH FAKE_REPLY FAKE_SEEN FAKE_SHIM FAKE_STDIN FAKE_USER_AUTH"
  unset VETDD_MODEL_JUDGE VETDD_MODEL_JUDGE_EFFORT CODEX_HOME
  # The user's file login (isolate_git set HOME to a private directory).
  mkdir -p "$HOME/.codex" && printf '{"token":"t"}\n' > "$HOME/.codex/auth.json"
}

judge() {
  "$SCRIPTS/judge.sh" --rubric "$RUBRIC" --candidates "$CAND" --out "$OUT" \
    --eval-id kata-1 --run-id 20260926-1200 --rubric-version 1 "$@"
}

# The argument that follows <flag> in the fake's recorded argv.
arg_after() { awk -v f="$1" 'p { print; exit } $0 == f { p = 1 }' "$FAKE_ARGS"; }

@test "a missing codex binary exits 3 with a clear message" {
  export VETDD_CODEX_BIN="vetdd-no-such-codex-binary"
  run judge
  [ "$status" -eq 3 ]
  [[ "$output" == *"codex"* ]]
  [[ "$output" == *"not found"* ]]
}

@test "codex that is not logged in exits 3 with a clear message" {
  export FAKE_LOGGED_OUT=1
  run judge
  [ "$status" -eq 3 ]
  [[ "$output" == *"codex login"* ]]
  [ ! -e "$FAKE_ARGS" ]
}

@test "a blinding hit in the candidates directory exits 4, prints the hit, and never calls the judge" {
  printf 'Written by Claude\n' > "$CAND/c2/artifact/README.md"
  run judge
  [ "$status" -eq 4 ]
  [[ "$output" == *"c2/artifact/README.md:1: claude"* ]]
  [ ! -e "$FAKE_ARGS" ]
  [ ! -e "$OUT" ]
}

@test "evaluation words such as test in an artifact do not block the judge" {
  printf 'diff --git a/src/a.test.ts b/src/a.test.ts\n+it("closes on the 28th", () => {})\n' > "$CAND/c1/artifact/diff.patch"
  run judge
  [ "$status" -eq 0 ]
  [ -e "$OUT" ]
}

@test "the judge's own output goes to .vetdd/judge-logs at the git root, outside the run directory, and its path is printed" {
  run judge
  [ "$status" -eq 0 ]
  [[ "$output" != *"fake codex transcript line"* ]]
  [[ "$output" != *"fake codex progress"* ]]
  [[ "$output" == *"$LOG"* ]]
  grep -q "fake codex transcript line" "$LOG"
  grep -q "fake codex progress" "$LOG"
  [ ! -e "$OUT.log" ]
}

@test "when codex exec fails, the tail of the log is shown without control characters and the exit code is 6" {
  export FAKE_EXEC_FAIL=1
  run judge
  [ "$status" -eq 6 ]
  [[ "$output" == *"simulated [31mfailure[0m"* ]]
  [[ "$output" != *$'\033'* ]]
  [[ "$output" == *"$LOG"* ]]
}

@test "a valid reply is written verbatim to --out, with metadata beside it, and passes check-verdict" {
  run judge
  [ "$status" -eq 0 ]
  cmp "$REPLY" "$OUT"
  [ "$(jq -r '.family' "$OUT.meta.json")" = "codex" ]
  [ "$(jq -r '.model' "$OUT.meta.json")" = "$("$SCRIPTS/models.sh" judge)" ]
  [ "$(jq -r '.effort' "$OUT.meta.json")" = "$("$SCRIPTS/models.sh" judge-effort)" ]
  [[ "$(jq -r '.invoked_at' "$OUT.meta.json")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]
  run "$SCRIPTS/check-verdict.sh" "$OUT"
  [ "$output" = "OK" ]
}

@test "codex exec is invoked read-only with the schema and output file" {
  judge
  grep -qx exec "$FAKE_ARGS"
  [ "$(arg_after -s)" = "read-only" ]
  [ "$(arg_after -m)" = "$("$SCRIPTS/models.sh" judge)" ]
  [ "$(arg_after -c)" = "model_reasoning_effort=\"$("$SCRIPTS/models.sh" judge-effort)\"" ]
  [ "$(arg_after --output-schema)" = "$VERDICT_SCHEMA" ]
  grep -qx -- --skip-git-repo-check "$FAKE_ARGS"
  [ -n "$(arg_after -o)" ]
}

@test "--model and --effort override the defaults" {
  judge --model gpt-test-x --effort low
  [ "$(arg_after -m)" = "gpt-test-x" ]
  [ "$(arg_after -c)" = 'model_reasoning_effort="low"' ]
  [ "$(jq -r '.model + " " + .effort' "$OUT.meta.json")" = "gpt-test-x low" ]
}

@test "the rendered prompt carries the rubric verbatim, the ids, the version, and 'none recorded'" {
  judge
  grep -qF "You are the judge for one evaluation." "$FAKE_STDIN"
  grep -qF -- "- 2: the output file holds the literal value 42." "$FAKE_STDIN"
  grep -qF "## 2. clarity" "$FAKE_STDIN"
  grep -qF "eval_id: kata-1   run_id: 20260926-1200" "$FAKE_STDIN"
  grep -qF "the criteria (version 1)" "$FAKE_STDIN"
  grep -qxF "none recorded" "$FAKE_STDIN"
  ! grep -qF '{{' "$FAKE_STDIN" || false
  ! grep -qF '```' "$FAKE_STDIN" || false
  [ "$(tail -n 1 "$FAKE_STDIN")" = "Return only the JSON object." ]
}

@test "--conditions and --extra-layout are rendered verbatim, without re-expanding slots inside values" {
  printf 'node v24\ncwd .\n{{eval_id}} stays literal\n' > "$BATS_TEST_TMPDIR/cond.txt"
  judge --conditions "$BATS_TEST_TMPDIR/cond.txt" --extra-layout "c1/transcript.jsonl  what the author read"
  grep -qxF "node v24" "$FAKE_STDIN"
  grep -qxF "{{eval_id}} stays literal" "$FAKE_STDIN"
  grep -qxF -- "- c1/transcript.jsonl  what the author read" "$FAKE_STDIN"
  ! grep -qxF "none recorded" "$FAKE_STDIN" || false
}

@test "the judge runs in a private copy of the labels and the rubric, outside any repository, removed afterwards" {
  mkdir -p "$CAND/notes"
  printf 'x\n' > "$CAND/notes/stray.txt"
  judge
  local cdir; cdir="$(arg_after -C)"
  [ "$cdir" != "$(cd "$CAND" && pwd)" ]
  [ "$(grep -xE '\./[^/]+' "$BATS_TEST_TMPDIR/fake/seen.tree" | sort | tr '\n' ' ')" = "./c1 ./c2 ./rubric.md " ]
  [ ! -e "$BATS_TEST_TMPDIR/fake/seen.variants" ]
  [ ! -e "$BATS_TEST_TMPDIR/fake/seen.git" ]
  [ ! -e "$cdir" ]
  [ ! -e "$CAND/rubric.md" ]
}

@test "a TMPDIR inside a git repository is refused before the judge runs" {
  mkdir -p "$PROJ/tmp"
  TMPDIR="$PROJ/tmp" run judge
  [ "$status" -ne 0 ]
  [[ "$output" == *"repository"* ]]
  [ ! -e "$FAKE_ARGS" ]
}

@test "while the judge runs, its temporary files are in two private directories (the work copy and the codex home), both removed after" {
  mkdir -p "$BATS_TEST_TMPDIR/tmp"
  TMPDIR="$BATS_TEST_TMPDIR/tmp" run judge
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/fake/seen.tmpdir" | tr -d ' ')" = 2 ]
  grep -qxE 'vetdd-judge\.[A-Za-z0-9]+/' "$BATS_TEST_TMPDIR/fake/seen.tmpdir"
  grep -qxE 'vetdd-codex\.[A-Za-z0-9]+/' "$BATS_TEST_TMPDIR/fake/seen.tmpdir"
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/tmp")" ]
}

@test "--extra-words are passed to the blind check (exit 4 on a hit)" {
  printf 'built on the alpha-lane setup\n' > "$CAND/c1/artifact/NOTES.md"
  jq -r '.[]' "$BATS_TEST_TMPDIR/run/variants.json" > "$BATS_TEST_TMPDIR/words.txt"
  run judge --extra-words "$BATS_TEST_TMPDIR/words.txt"
  [ "$status" -eq 4 ]
  [[ "$output" == *"c1/artifact/NOTES.md:1: alpha-lane"* ]]
  [ ! -e "$FAKE_ARGS" ]
}

@test "a model or origin word in the conditions, extra layout, eval id, or run id exits 4 without calling the judge" {
  printf 'node v24\nauthor: opus\n' > "$BATS_TEST_TMPDIR/cond.txt"
  run judge --conditions "$BATS_TEST_TMPDIR/cond.txt"
  [ "$status" -eq 4 ]
  [[ "$output" == *"cond.txt:2: opus"* ]]
  run judge --extra-layout "c1/transcript.jsonl  the baseline run"
  [ "$status" -eq 4 ]
  [[ "$output" == *"--extra-layout:1: baseline"* ]]
  run "$SCRIPTS/judge.sh" --rubric "$RUBRIC" --candidates "$CAND" --out "$OUT" \
    --eval-id claude-kata --run-id 20260926-1200 --rubric-version 1
  [ "$status" -eq 4 ]
  [[ "$output" == *"--eval-id:1: claude"* ]]
  run "$SCRIPTS/judge.sh" --rubric "$RUBRIC" --candidates "$CAND" --out "$OUT" \
    --eval-id kata-1 --run-id winner-1 --rubric-version 1
  [ "$status" -eq 4 ]
  [[ "$output" == *"--run-id:1: winner"* ]]
  [ ! -e "$FAKE_ARGS" ]
}

@test "a verdict whose eval_id, run_id, or rubric_version differ from the arguments exits 5" {
  jq_edit "$REPLY" '.run_id = "20260101-0000"'
  run judge
  [ "$status" -eq 5 ]
  [[ "$output" == *"run_id: expected 20260926-1200"* ]]
  write_verdict "$REPLY"
  run judge --rubric-version 2
  [ "$status" -eq 5 ]
  [[ "$output" == *"rubric_version: expected 2"* ]]
}

@test "a check-verdict tool error exits 7, not 5" {
  mkdir -p "$BATS_TEST_TMPDIR/badnode"
  printf '#!/bin/sh\necho "node: simulated crash" >&2\nexit 2\n' > "$BATS_TEST_TMPDIR/badnode/node"
  chmod +x "$BATS_TEST_TMPDIR/badnode/node"
  PATH="$BATS_TEST_TMPDIR/badnode:$PATH" run judge
  [ "$status" -eq 7 ]
  [[ "$output" == *"could not"* ]]
}

@test "--model and --effort are validated through models.sh" {
  run judge --model claude-opus-5
  [ "$status" -eq 2 ]
  run judge --model -rm
  [ "$status" -eq 2 ]
  run judge --effort extreme
  [ "$status" -eq 2 ]
  [ ! -e "$FAKE_ARGS" ]
}

@test "an eval id or run id that is not a plain name is a usage error" {
  run "$SCRIPTS/judge.sh" --rubric "$RUBRIC" --candidates "$CAND" --out "$OUT" \
    --eval-id ../kata --run-id 20260926-1200 --rubric-version 1
  [ "$status" -eq 2 ]
  [ ! -e "$FAKE_ARGS" ]
}

@test "a reply that is not valid JSON exits 5 and leaves the file for inspection" {
  printf 'I think c1 wins.\n' > "$REPLY"
  run judge
  [ "$status" -eq 5 ]
  [ "$(cat "$OUT")" = "I think c1 wins." ]
}

@test "a reply that misses a label's score exits 5" {
  jq_edit "$REPLY" 'del(.criteria[0].scores[] | select(.label == "c2"))'
  run judge
  [ "$status" -eq 5 ]
  [[ "$output" == *"c2"* ]]
}

@test "missing required options are a usage error (exit 2)" {
  run "$SCRIPTS/judge.sh" --rubric "$RUBRIC" --candidates "$CAND"
  [ "$status" -eq 2 ]
  [ ! -e "$FAKE_ARGS" ]
}

@test "G1: an origin word in the rubric stops the judge (exit 4) before codex runs" {
  printf '\n## 3. extra\n\n- 2: c1 is the baseline.\n' >> "$RUBRIC"
  run judge
  [ "$status" -eq 4 ]
  [[ "$output" == *"baseline"* ]]
  [ ! -e "$FAKE_ARGS" ]
}

@test "H5: a hand-made candidates directory with node_modules or .git exits 4 and never calls the judge" {
  mkdir -p "$CAND/c1/artifact/node_modules" "$CAND/c2/artifact/.git"
  printf 'claude-opus variant-B\n' > "$CAND/c1/artifact/node_modules/x.js"
  printf '[core]\n\tbare = false\n' > "$CAND/c2/artifact/.git/config"
  run judge
  [ "$status" -eq 4 ]
  [[ "$output" == *"c1/artifact/node_modules:name: not allowed in a judge input"* ]]
  [[ "$output" == *"c2/artifact/.git:name: not allowed in a judge input"* ]]
  [ ! -e "$FAKE_ARGS" ]
  [ ! -e "$OUT" ]
}

@test "H1: an email address in a candidate's transcript exits 4 and never calls the judge" {
  printf '{"text":"mail me at alice.smith@%s.co.jp"}\n' corp-mail > "$CAND/c1/transcript.jsonl"
  run judge
  [ "$status" -eq 4 ]
  [[ "$output" == *"c1/transcript.jsonl:1: secret: email"* ]]
  [ ! -e "$FAKE_ARGS" ]
}

@test "R3: the run directory's absolute path in a transcript or an artifact exits 4 (both path forms)" {
  local run_abs run_phys
  run_abs="$(cd "$BATS_TEST_TMPDIR/run" && pwd)"
  run_phys="$(cd "$BATS_TEST_TMPDIR/run" && pwd -P)"
  printf '{"text":"cat %s/variants.json"}\n' "$run_abs" > "$CAND/c1/transcript.jsonl"
  run judge
  [ "$status" -eq 4 ]
  [[ "$output" == *"c1/transcript.jsonl:1: "* ]]
  [ ! -e "$FAKE_ARGS" ]
  rm "$CAND/c1/transcript.jsonl"
  printf 'see %s/synthesis.md\n' "$run_phys" > "$CAND/c2/artifact/NOTES.md"
  run judge
  [ "$status" -eq 4 ]
  [[ "$output" == *"c2/artifact/NOTES.md:1: "* ]]
  [ ! -e "$FAKE_ARGS" ]
}

@test "R3: the candidates directory's absolute path in an artifact exits 4" {
  printf 'copied from %s/c1/artifact\n' "$(cd "$CAND" && pwd -P)" > "$CAND/c2/artifact/NOTES.md"
  run judge
  [ "$status" -eq 4 ]
  [[ "$output" == *"c2/artifact/NOTES.md:1: "* ]]
  [ ! -e "$FAKE_ARGS" ]
}

# A run directory inside the project repository, as a final verdict or an A/B eval has it.
make_run_in_repo() {
  local l
  CAND="$PROJ/runs/r1/candidates"
  for l in c1 c2; do
    mkdir -p "$CAND/$l/artifact"
    printf '42\n' > "$CAND/$l/artifact/value.txt"
    printf 'cwd: %s\n' "$(cd "$PROJ" && pwd -P)" > "$CAND/$l/artifact/conditions.txt"
  done
}

@test "R3: without variants.json (a final verdict) the git root's path does not block the judge" {
  make_run_in_repo
  run judge
  [ "$status" -eq 0 ]
  [ -e "$FAKE_ARGS" ]
}

@test "R3: with variants.json (an A/B eval) the git root's path exits 4" {
  make_run_in_repo
  printf '{"c1": "alpha-lane", "c2": "beta-lane"}\n' > "$PROJ/runs/r1/variants.json"
  run judge
  [ "$status" -eq 4 ]
  [[ "$output" == *"c1/artifact/conditions.txt:1: "* ]]
  [ ! -e "$FAKE_ARGS" ]
}

@test "S2: --allow-secrets lets secret-shaped test data through and is recorded in meta.json" {
  mkdir -p "$CAND/c1/artifact/tests"
  printf 'export const user = "qa.person@%s.co.jp";\n' acme > "$CAND/c1/artifact/tests/fixture.ts"
  run judge
  [ "$status" -eq 4 ]
  [[ "$output" == *"c1/artifact/tests/fixture.ts:1: secret: email"* ]]
  [ ! -e "$FAKE_ARGS" ]
  run judge --allow-secrets 'c1/artifact/tests/*' --allow-secrets '*/fixture.ts'
  [ "$status" -eq 0 ]
  [ "$(jq -c '.allowed_secrets' "$OUT.meta.json")" = '["c1/artifact/tests/*","*/fixture.ts"]' ]
}

@test "S2: --allow-secrets does not exempt a model name, and meta.json records [] without it" {
  mkdir -p "$CAND/c1/artifact/tests"
  printf 'written by claude\n' > "$CAND/c1/artifact/tests/fixture.ts"
  run judge --allow-secrets 'c1/artifact/tests/*'
  [ "$status" -eq 4 ]
  [[ "$output" == *"c1/artifact/tests/fixture.ts:1: claude"* ]]
  rm "$CAND/c1/artifact/tests/fixture.ts"
  run judge
  [ "$status" -eq 0 ]
  [ "$(jq -c '.allowed_secrets' "$OUT.meta.json")" = '[]' ]
}

@test "T1: the run directory's path right after a JSON \\n in a transcript exits 4" {
  local run_abs
  run_abs="$(cd "$BATS_TEST_TMPDIR/run" && pwd)"
  printf '{"text":"a\\n%s/rubric.md"}\n' "$run_abs" > "$CAND/c1/transcript.jsonl"
  run judge
  [ "$status" -eq 4 ]
  [[ "$output" == *"c1/transcript.jsonl:1: "* ]]
  [ ! -e "$FAKE_ARGS" ]
}

@test "the run directory's path written with JSON's \\/ escape exits 4 (both path forms)" {
  local p
  for p in "$(cd "$BATS_TEST_TMPDIR/run" && pwd)" "$(cd "$BATS_TEST_TMPDIR/run" && pwd -P)"; do
    printf '{"cwd":"%s\\/rubric.md"}\n' "$(printf '%s' "$p" | sed 's|/|\\/|g')" > "$CAND/c1/transcript.jsonl"
    run judge
    [ "$status" -eq 4 ] || { echo "$p: $output"; false; }
    [[ "$output" == *"c1/transcript.jsonl:1: "* ]]
    [ ! -e "$FAKE_ARGS" ]
  done
}

@test "judge.sh ignores CDPATH" {
  mkdir -p "$BATS_TEST_TMPDIR/cdpath/run/candidates"
  cd "$BATS_TEST_TMPDIR"
  CDPATH="$BATS_TEST_TMPDIR/cdpath" run "$SCRIPTS/judge.sh" --rubric "$RUBRIC" --candidates run/candidates \
    --out "$OUT" --eval-id kata-1 --run-id 20260926-1200 --rubric-version 1
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c "$BATS_TEST_TMPDIR/cdpath")" -eq 0 ]
}

@test "X1: a final verdict (no variants.json) with the candidates at the repository root and its path in a log is judged" {
  local l proj_l proj_p
  CAND="$PROJ/candidates"
  proj_l="$(cd "$PROJ" && pwd)"
  proj_p="$(cd "$PROJ" && pwd -P)"
  for l in c1 c2; do
    mkdir -p "$CAND/$l/artifact" "$CAND/$l/evidence/s1/runs"
    printf '42\n' > "$CAND/$l/artifact/value.txt"
    printf 'FAIL %s/src/value.test.ts\n  at %s/src/value.ts:3\n' "$proj_p" "$proj_l" > "$CAND/$l/evidence/s1/runs/001-before.log"
    printf 'copied to %s/c1/artifact\n' "$CAND" > "$CAND/$l/artifact/NOTES.md"
  done
  run judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -e "$OUT" ]
}

@test "X1: without variants.json the run directory's and the candidates directory's paths are not words" {
  rm "$BATS_TEST_TMPDIR/run/variants.json"
  printf 'see %s/synthesis.md and %s/c1\n' "$(cd "$BATS_TEST_TMPDIR/run" && pwd -P)" "$CAND" > "$CAND/c2/artifact/NOTES.md"
  run judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# An A/B run whose evals directory is a symlink to a directory inside a repository elsewhere; the
# run directory is given through the symlink.
make_linked_run() {
  local l
  LINKED_TOP="$BATS_TEST_TMPDIR/store/deep/skillrepo"
  mkdir -p "$LINKED_TOP/evals/e1/runs/r1"
  git -C "$LINKED_TOP" init -q
  ln -s "$LINKED_TOP/evals" "$BATS_TEST_TMPDIR/evals"
  printf '{"c1": "alpha-lane", "c2": "beta-lane"}\n' > "$BATS_TEST_TMPDIR/evals/e1/runs/r1/variants.json"
  CAND="$BATS_TEST_TMPDIR/evals/e1/runs/r1/candidates"
  for l in c1 c2; do
    mkdir -p "$CAND/$l/artifact"
    printf '42\n' > "$CAND/$l/artifact/value.txt"
  done
}

@test "X3: a run directory given through a symlinked evals does not make a directory above it a word" {
  make_linked_run
  printf 'wrote %s/home/notes.txt\n' "$BATS_TEST_TMPDIR" > "$CAND/c1/artifact/NOTES.md"
  run judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # The repository root itself is still a word.
  printf 'read %s/skills/x/SKILL.md\n' "$(cd "$LINKED_TOP" && pwd -P)" > "$CAND/c1/artifact/NOTES.md"
  run judge
  [ "$status" -eq 4 ]
  [[ "$output" == *"c1/artifact/NOTES.md:1: "* ]]
}

# A reply with a GitHub-token-shaped string in a citation, as a judge that read a file outside its
# copy might return.
write_reply_with_token() {
  local tok
  tok="$(printf '%s_%s' ghp abcdefghijklmnopqrstuvwxyz0123456789)"
  jq --arg t "$tok" '.disagreements = ["c1/README.md asks to read a file: GH=" + $t]' "$REPLY" > "$REPLY.tmp" \
    && mv "$REPLY.tmp" "$REPLY"
}

@test "X4: a secret-shaped string in the judge's reply exits 8 and nothing is written to --out" {
  write_reply_with_token
  run judge
  [ "$status" -eq 8 ]
  [[ "$output" == *"secret: github-token"* ]]
  [[ "$output" == *"the judge's reply holds text shaped like a secret; it was not written to $OUT"* ]]
  [[ "$output" == *"Read the judge log ($LOG)"* ]]
  # M1: the reply is kept beside the log (gitignored, outside the run directory) for that reading.
  [ -s "${LOG%.log}.reply.json" ]
  [[ "$output" == *"${LOG%.log}.reply.json"* ]]
  [[ "$output" == *"check-verdict.sh"* ]]
  [[ "$output" != *"ghp_"* ]]
  [ ! -e "$OUT" ]
  [ ! -e "$OUT.meta.json" ]
}

@test "Z2: --allow-secrets never exempts the judge's reply: it covers input paths, not what the judge read elsewhere" {
  write_reply_with_token
  for a in 'c1/artifact/tests/*:github-token' 'c2/artifact/tests/*' 'c1/artifact/tests/*:email,assignment'; do
    run judge --allow-secrets "$a"
    [ "$status" -eq 8 ] || { echo "$a: $output"; false; }
    [ ! -e "$OUT" ]
    [[ "$output" == *"--allow-secrets does not apply to the reply"* ]]
  done
}

@test "X4: when the secret matcher fails on the reply, judge.sh exits 1 and writes nothing" {
  local real_awk
  real_awk="$(command -v awk)"
  mkdir -p "$BATS_TEST_TMPDIR/badawk"
  printf '#!/bin/sh\ncase "$*" in *label=judge-reply*) echo "awk: simulated crash" >&2; exit 2 ;; esac\nexec "%s" "$@"\n' \
    "$real_awk" > "$BATS_TEST_TMPDIR/badawk/awk"
  chmod +x "$BATS_TEST_TMPDIR/badawk/awk"
  PATH="$BATS_TEST_TMPDIR/badawk:$PATH" run judge
  [ "$status" -eq 1 ]
  [ ! -e "$OUT" ]
}

@test "B1: nothing next to the judge's working directory names the paths it must not reach" {
  run judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # variants.json is in the run directory here, so path words were written; they are gone by now.
  [ -s "$BATS_TEST_TMPDIR/run/variants.json" ]
  run cat "$FAKE_SEEN.parentfiles"
  [[ "$output" != *"args/"* ]] || { echo "$output"; false; }
  ! grep -rqs "$BATS_TEST_TMPDIR" $(cat "$FAKE_SEEN.parentfiles" 2>/dev/null) /dev/null || false
}

# single_label: one candidate (c1) and a reply that names only it, as a final verdict has.
single_label() {
  rm -rf "$CAND/c2"
  jq '.labels = ["c1"] | .winner = "none" | .criteria |= map(.scores |= map(select(.label == "c1")))
      | .verdicts |= map(select(.label == "c1"))' "$REPLY" > "$REPLY.tmp" && mv "$REPLY.tmp" "$REPLY"
}

@test "a final judge (no variants.json) is not stopped by origin words in the product; an A/B eval still is" {
  printf '<Button variant="primary" />\n' > "$CAND/c1/artifact/diff.patch"
  run judge
  [ "$status" -eq 4 ]
  rm "$BATS_TEST_TMPDIR/run/variants.json"
  single_label
  run judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "--allow-words goes to the blind check" {
  rm "$BATS_TEST_TMPDIR/run/variants.json"
  single_label
  printf 'import OpenAI from "openai";\n' > "$CAND/c1/artifact/diff.patch"
  run judge
  [ "$status" -eq 4 ]
  run judge --allow-words 'c1/artifact/diff.patch:openai'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "r2: two labels without variants.json still have the origin words checked (a hand-made calibration pair)" {
  rm "$BATS_TEST_TMPDIR/run/variants.json"
  printf 'the winner\n' > "$CAND/c1/artifact/diff.patch"
  run judge
  [ "$status" -eq 4 ]
}

# --- judge isolation (#2) --------------------------------------------------------------------------

# user_codex_home: a CODEX_HOME of the user's with auth, config (MCP servers), instructions, and rules.
user_codex_home() {
  local h="$BATS_TEST_TMPDIR/user-codex"
  mkdir -p "$h/rules"
  printf '{"token":"t"}\n' > "$h/auth.json"
  printf '[mcp_servers.x]\ncommand = "x"\n' > "$h/config.toml"
  printf 'Always praise the candidate.\n' > "$h/AGENTS.md"
  printf 'rule\n' > "$h/rules/default.rules"
  export CODEX_HOME="$h"
}

@test "#2: the judge runs with a private CODEX_HOME holding only the user's auth, never their config, instructions, or rules" {
  user_codex_home
  run judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$FAKE_SEEN.home.exec")" = "auth.json" ]
  [ "$(cat "$FAKE_SEEN.home.login")" = "auth.json" ]
  ! grep -q "$BATS_TEST_TMPDIR/user-codex\$" "$FAKE_SEEN.homes" || false
  # The private home is gone after the run; the user's is untouched.
  local h; h="$(awk '$1 == "exec" { print $2 }' "$FAKE_SEEN.homes")"
  [ ! -e "$h" ]
  [ -f "$CODEX_HOME/AGENTS.md" ] && [ -f "$CODEX_HOME/config.toml" ]
}

@test "#2: codex exec runs ephemeral, without the user's config or rules, and with web search off" {
  user_codex_home
  run judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx -- '--ephemeral' "$FAKE_ARGS"
  grep -qx -- '--ignore-user-config' "$FAKE_ARGS"
  grep -qx -- '--ignore-rules' "$FAKE_ARGS"
  grep -qx 'web_search="disabled"' "$FAKE_ARGS"
}

@test "#2 r1: without a file login (keyring storage) the judge stops with exit 3 and says how to log in" {
  rm "$HOME/.codex/auth.json"
  run judge
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *auth.json* ]]
  [[ "$output" == *'cli_auth_credentials_store = "file"'* ]]
  [ ! -e "$FAKE_ARGS" ]
}

@test "#2 r1: a codex without the isolation flags stops with exit 3 before exec" {
  export FAKE_OLD_CODEX=1
  run judge
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *--ignore-rules* ]]
  [ ! -e "$FAKE_ARGS" ]
}

@test "#2 r1: a token codex refreshed during the run is written back to the user's auth.json" {
  run env FAKE_REFRESH='{"token":"refreshed"}' "$SCRIPTS/judge.sh" --rubric "$RUBRIC" --candidates "$CAND" --out "$OUT" \
    --eval-id kata-1 --run-id 20260926-1200 --rubric-version 1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$HOME/.codex/auth.json")" = '{"token":"refreshed"}' ]
  [ ! -L "$HOME/.codex/auth.json" ]
}

@test "#2 r1: a relative CODEX_HOME is taken from the current directory" {
  user_codex_home
  cd "$BATS_TEST_TMPDIR"
  CODEX_HOME=user-codex run judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$FAKE_SEEN.home.exec")" = "auth.json" ]
}

@test "#2 r1: with neither CODEX_HOME nor HOME set, the judge stops with exit 3, not an unbound variable" {
  run env -u HOME -u CODEX_HOME "$SCRIPTS/judge.sh" --rubric "$RUBRIC" --candidates "$CAND" --out "$OUT" \
    --eval-id kata-1 --run-id 20260926-1200 --rubric-version 1
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" != *unbound* ]]
}

@test "#2 r2: codex exec runs with HOME set to the private home, so the user's personal skills (~/.agents/skills) never load" {
  mkdir -p "$HOME/.agents/skills/x" && printf 'name: x\n' > "$HOME/.agents/skills/x/SKILL.md"
  run judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local h; h="$(awk '$1 == "exec" { print $2 }' "$FAKE_SEEN.homes")"
  [ "$(cat "$FAKE_SEEN.home_env.exec")" = "$h" ]
}

@test "#2 r2: the judge's shell gets only the core environment (CODEX_HOME and other variables left out)" {
  run judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx 'shell_environment_policy.inherit="core"' "$FAKE_ARGS"
}

@test "#2 r2: a refreshed login is not written back over a login the user refreshed meanwhile" {
  run env FAKE_REFRESH='{"token":"refreshed"}' FAKE_USER_AUTH="$HOME/.codex/auth.json" "$SCRIPTS/judge.sh" --rubric "$RUBRIC" --candidates "$CAND" --out "$OUT" \
    --eval-id kata-1 --run-id 20260926-1200 --rubric-version 1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$HOME/.codex/auth.json")" = '{"token":"newer"}' ]
  [[ "$output" == *"codex login"* ]]
}

@test "#2 r2: a refreshed login that is not JSON is never written back" {
  run env FAKE_REFRESH='garbage' "$SCRIPTS/judge.sh" --rubric "$RUBRIC" --candidates "$CAND" --out "$OUT" \
    --eval-id kata-1 --run-id 20260926-1200 --rubric-version 1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$HOME/.codex/auth.json")" = '{"token":"t"}' ]
}

@test "#2 r2: a user's auth.json that is a link is written back through the link, which stays" {
  mkdir -p "$BATS_TEST_TMPDIR/dots"
  mv "$HOME/.codex/auth.json" "$BATS_TEST_TMPDIR/dots/auth.json"
  ln -s ../../dots/auth.json "$HOME/.codex/auth.json"
  run env FAKE_REFRESH='{"token":"refreshed"}' "$SCRIPTS/judge.sh" --rubric "$RUBRIC" --candidates "$CAND" --out "$OUT" \
    --eval-id kata-1 --run-id 20260926-1200 --rubric-version 1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -L "$HOME/.codex/auth.json" ]
  [ "$(cat "$BATS_TEST_TMPDIR/dots/auth.json")" = '{"token":"refreshed"}' ]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/dots" | grep -v '^auth.json$')" ]
}

@test "review r1: a codex behind a version manager's shim, which needs HOME, stops with exit 3 before exec and says what to do" {
  mkdir -p "$HOME/.local/share/mise"
  FAKE_SHIM=.local/share/mise run judge
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"private HOME"* ]] && [[ "$output" == *standalone* ]] && [[ "$output" == *VETDD_CODEX_BIN* ]]
  [ ! -e "$FAKE_ARGS" ]
}

@test "review r2: login status and exec both keep the login in the file store, whatever codex's default" {
  run judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx 'cli_auth_credentials_store="file"' "$FAKE_SEEN.login_args"
  grep -qx 'cli_auth_credentials_store="file"' "$FAKE_ARGS"
}

@test "review r1 round 2: the isolation flags are checked on the codex that runs, with the private HOME" {
  run judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$FAKE_SEEN.home_env.help")" = "$(cat "$FAKE_SEEN.home_env.exec")" ]
}

@test "review r4: a version manager's directory set in the caller's environment does not reach the private HOME either" {
  mkdir -p "$HOME/.local/share/mise"
  MISE_DATA_DIR="$HOME/.local/share/mise" FAKE_SHIM=.local/share/mise run judge
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ ! -e "$FAKE_ARGS" ]
}

@test "pr52: codex runs with an allowlisted environment: a mise config selector or any other variable of the caller never reaches it" {
  export MISE_GLOBAL_CONFIG_FILE="$BATS_TEST_TMPDIR/mise.toml" MISE_CONFIG_FILE=x VETDD_TEST_CALLER_ONLY=1
  run judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  for v in MISE_GLOBAL_CONFIG_FILE MISE_CONFIG_FILE VETDD_TEST_CALLER_ONLY; do
    ! grep -q "^$v=" "$FAKE_SEEN.env.exec" || false
    ! grep -q "^$v=" "$FAKE_SEEN.env.login" || false
  done
  grep -q '^PATH=' "$FAKE_SEEN.env.exec"
}

@test "pr52: VETDD_JUDGE_KEEP_ENV keeps a named variable, never HOME or CODEX_HOME, and refuses a name that is not one" {
  export VETDD_TEST_PROXY=p VETDD_JUDGE_KEEP_ENV="$VETDD_JUDGE_KEEP_ENV VETDD_TEST_PROXY"
  run judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx 'VETDD_TEST_PROXY=p' "$FAKE_SEEN.env.exec"
  for bad in CODEX_HOME HOME 'a-b' CODEX_X OPENAI_BASE_URL XDG_CONFIG_HOME MISE_GLOBAL_CONFIG_FILE NODE_OPTIONS DYLD_INSERT_LIBRARIES LD_PRELOAD BASH_ENV; do
    VETDD_JUDGE_KEEP_ENV="$VETDD_JUDGE_KEEP_ENV $bad" run judge
    [ "$status" -eq 2 ] || { echo "$bad: $output"; false; }
  done
}

@test "pr52: the start checks read nothing from the caller's stdin, so a codex that reads it cannot hang them" {
  FAKE_VERSION_READS=1 run judge <<< "the caller's stdin"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -s "$FAKE_SEEN.version_stdin" ]
}

@test "pr52 r1: a kept variable's value goes to codex in its environment, never on a command line (ps, audit logs)" {
  cat > "$BATS_TEST_TMPDIR/guard/env" <<WRAP
#!/bin/sh
printf '%s\\n' "\$@" >> "$BATS_TEST_TMPDIR/env-argv"
exec /usr/bin/env "\$@"
WRAP
  chmod +x "$BATS_TEST_TMPDIR/guard/env"
  export HTTPS_PROXY="http://u:s3cr3t-proxy@proxy.invalid:1"
  run judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx 'HTTPS_PROXY=http://u:s3cr3t-proxy@proxy.invalid:1' "$FAKE_SEEN.env.exec"
  [ ! -e "$BATS_TEST_TMPDIR/env-argv" ] || ! grep -q s3cr3t-proxy "$BATS_TEST_TMPDIR/env-argv" || false
}

@test "pr52 r1: VETDD_JUDGE_KEEP_ENV is split into names without pathname expansion" {
  mkdir "$BATS_TEST_TMPDIR/only-readme" && cd "$BATS_TEST_TMPDIR/only-readme"
  touch README
  VETDD_JUDGE_KEEP_ENV="$VETDD_JUDGE_KEEP_ENV *" run judge
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"holds *,"* ]]
}

@test "pr52 r1: a codex path with = in it still runs" {
  mkdir -p "$BATS_TEST_TMPDIR/a=b"
  cp "$VETDD_CODEX_BIN" "$BATS_TEST_TMPDIR/a=b/codex"
  VETDD_CODEX_BIN="$BATS_TEST_TMPDIR/a=b/codex" run judge
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "pr52 r1: a bad VETDD_JUDGE_KEEP_ENV is a usage error before codex is looked for, and a failed exec points to it" {
  VETDD_CODEX_BIN=vetdd-no-such-codex-binary VETDD_JUDGE_KEEP_ENV="a-b" run judge
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  FAKE_EXEC_FAIL=1 run judge
  [ "$status" -eq 6 ] || { echo "$output"; false; }
  [[ "$output" == *VETDD_JUDGE_KEEP_ENV* ]]
}
