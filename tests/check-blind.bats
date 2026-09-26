#!/usr/bin/env bats
# check-blind.sh: flags forbidden words and model names in names and text contents below a directory.

load test_helper
load helpers/eval_fixtures

setup() {
  W="$BATS_TEST_TMPDIR/ws"
  mkdir -p "$W"
}

blind() { "$SCRIPTS/check-blind.sh" "$@"; }

@test "a clean directory exits 0 with no output; latest and attest are not whole-word hits" {
  mkdir -p "$W/src"
  printf 'the latest invoice\nwe attest to it\n' > "$W/src/notes.md"
  run blind "$W" --placed .
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "--profile judge ignores evaluation words but still flags model names and origin words" {
  mkdir -p "$W/c1/artifact"
  printf 'npm test\nit("closes on the 28th", ...)\n' > "$W/c1/artifact/diff.patch"
  run blind "$W" --profile judge
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  printf 'written by claude\n' > "$W/c1/artifact/notes.md"
  printf 'this is the baseline variant\n' > "$W/c1/artifact/origin.md"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [[ "$output" == *"c1/artifact/notes.md:1: claude"* ]]
  [[ "$output" == *"c1/artifact/origin.md:1: baseline"* ]]
  [[ "$output" == *"c1/artifact/origin.md:1: variant"* ]]
}

@test "a whole-word hit in contents prints path:line: word and exits 1" {
  printf 'first line\nimport x from "./test.ts"\n' > "$W/notes.md"
  run blind "$W" --placed .
  [ "$status" -eq 1 ]
  [ "$output" = "notes.md:2: test" ]
}

@test "matching is case-insensitive and accepts a plural s (Tests)" {
  printf 'Tests pass.\n' > "$W/a.md"
  run blind "$W" --placed .
  [ "$status" -eq 1 ]
  [ "$output" = "a.md:1: test" ]
}

@test "file and directory names are checked (foo.test.ts, tests/)" {
  mkdir -p "$W/tests"
  printf 'x\n' > "$W/tests/keep.txt"
  printf 'x\n' > "$W/foo.test.ts"
  run blind "$W" --placed .
  [ "$status" -eq 1 ]
  [[ "$output" == *"foo.test.ts:name: test"* ]]
  [[ "$output" == *"tests:name: test"* ]]
  [ "${#lines[@]}" -eq 2 ]
}

@test "every forbidden word from eval mode rule 1 is flagged" {
  printf 'eval judge experiment rubric score compare benchmark candidate arena variant baseline\n' > "$W/a.md"
  run blind "$W" --placed .
  [ "$status" -eq 1 ]
  for w in eval judge experiment rubric score compare benchmark candidate arena variant baseline; do
    [[ "$output" == *"a.md:1: $w"* ]]
  done
}

@test "model names are flagged, including the gpt- prefix" {
  printf 'written by Claude Opus 5\n' > "$W/a.md"
  printf 'model = "gpt-6-sol"\n' > "$W/b.toml"
  printf 'sonnet haiku fable codex grok anthropic openai\n' > "$W/c.txt"
  run blind "$W" --placed .
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.md:1: claude"* ]]
  [[ "$output" == *"a.md:1: opus"* ]]
  [[ "$output" == *"b.toml:1: gpt-"* ]]
  for w in sonnet haiku fable codex grok anthropic openai; do
    [[ "$output" == *"c.txt:1: $w"* ]]
  done
}

@test "--allow exempts matching relative paths and nothing else" {
  write_rubric "$W/rubric.md"
  mkdir -p "$W/c1/evidence/s1" "$W/c1/artifact"
  printf '{"cmd":["npm","test"]}\n' > "$W/c1/evidence/s1/meta.json"
  printf 'npm test\n' > "$W/c1/artifact/notes.md"
  run blind "$W" --placed . --allow 'rubric.md' --allow '*/evidence/*'
  [ "$status" -eq 1 ]
  [ "$output" = "c1/artifact/notes.md:1: test" ]
}

@test "--allow exemptions make an otherwise clean run directory pass" {
  write_rubric "$W/rubric.md"
  mkdir -p "$W/c1/evidence/s1" "$W/c1/artifact"
  printf '{"cmd":["npm","test"]}\n' > "$W/c1/evidence/s1/meta.json"
  printf '42\n' > "$W/c1/artifact/value.txt"
  run blind "$W" --placed . --allow 'rubric.md' --allow '*/evidence/*'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "node_modules, .git, and binary files are skipped" {
  mkdir -p "$W/node_modules/test" "$W/.git"
  printf 'test\n' > "$W/node_modules/test/index.js"
  printf 'ref: refs/heads/test\n' > "$W/.git/HEAD"
  printf 'test\000binary\n' > "$W/blob.bin"
  run blind "$W" --placed .
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "--extra-words adds words from a file (worktree or branch names)" {
  printf 'on branch fast-path in kata-app-1\n' > "$W/a.md"
  printf '# one per line\nkata-app-1\n\nfast-path\n' > "$BATS_TEST_TMPDIR/extra.txt"
  run blind "$W" --placed . --extra-words "$BATS_TEST_TMPDIR/extra.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.md:1: kata-app-1"* ]]
  [[ "$output" == *"a.md:1: fast-path"* ]]
}

@test "a missing directory is a usage error (exit 2)" {
  run blind "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 2 ]
}

# A copy of fixtures/ts-kata as a candidate would get it, under a neutral project name.
copy_kata() {
  K="$BATS_TEST_TMPDIR/work/${1:-invoice-app}"
  mkdir -p "${K%/*}"
  cp -R "$VETDD_ROOT/fixtures/ts-kata" "$K"
  rm -rf "$K/node_modules"
  TASK="$BATS_TEST_TMPDIR/work/request.md"
  printf 'Invoices closing on the 31st get the wrong due date in February. Please fix it.\n' > "$TASK"
}

@test "the candidate check passes an ordinary project with tests (fixtures/ts-kata under a neutral name)" {
  copy_kata
  run blind "$K"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run blind "$K" --file "$TASK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the candidate check fails on an evaluation word in the request file or in the workspace name" {
  copy_kata
  printf 'This is an eval of the closing rule.\n' >> "$TASK"
  run blind "$K" --file "$TASK"
  [ "$status" -eq 1 ]
  [ "$output" = "$TASK:2: eval" ]
  copy_kata eval-kata-1
  run blind "$K" --file "$TASK"
  [ "$status" -eq 1 ]
  [ "$output" = "eval-kata-1:name: eval" ]
}

@test "the candidate check covers the placed files, not the rest of the project" {
  copy_kata
  mkdir -p "$K/.claude/skills/closing-helper/notes"
  printf 'Keep the closing day rule.\n' > "$K/.claude/skills/closing-helper/SKILL.md"
  run blind "$K" --placed .claude/skills/closing-helper
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  printf 'The rubric rewards short answers.\n' > "$K/.claude/skills/closing-helper/notes/hint.md"
  printf 'x\n' > "$K/.claude/skills/closing-helper/notes/baseline.md"
  run blind "$K" --placed .claude/skills/closing-helper
  [ "$status" -eq 1 ]
  [[ "$output" == *".claude/skills/closing-helper/notes/hint.md:1: rubric"* ]]
  [[ "$output" == *".claude/skills/closing-helper/notes/baseline.md:name: baseline"* ]]
  [ "${#lines[@]}" -eq 2 ]
}

@test "a placed item's own name is checked; a placed path outside the directory is a usage error" {
  copy_kata
  mkdir -p "$K/.claude/skills/judge-helper"
  printf 'x\n' > "$K/.claude/skills/judge-helper/SKILL.md"
  run blind "$K" --placed .claude/skills/judge-helper
  [ "$status" -eq 1 ]
  [ "$output" = ".claude/skills/judge-helper:name: judge" ]
  run blind "$K" --placed ../request.md
  [ "$status" -eq 2 ]
  run blind "$K" --placed no/such/path
  [ "$status" -eq 2 ]
}

@test "the root directory's own name is checked for the candidate profile only" {
  mkdir -p "$BATS_TEST_TMPDIR/claude-kata/src"
  printf 'x\n' > "$BATS_TEST_TMPDIR/claude-kata/src/a.md"
  run blind "$BATS_TEST_TMPDIR/claude-kata"
  [ "$status" -eq 1 ]
  [ "$output" = "claude-kata:name: claude" ]
  mkdir -p "$BATS_TEST_TMPDIR/candidates/c1"
  run blind "$BATS_TEST_TMPDIR/candidates" --profile judge
  [ "$status" -eq 0 ]
}

@test "any symlink below the directory fails the check, in either profile" {
  mkdir -p "$W/c1/artifact"
  printf 'x\n' > "$W/c1/artifact/a.md"
  ln -s ../../../variants.json "$W/c1/artifact/link.json"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [ "$output" = "c1/artifact/link.json:symlink: not allowed" ]
  run blind "$W"
  [ "$status" -eq 1 ]
  [[ "$output" == *"c1/artifact/link.json:symlink: not allowed"* ]]
}

@test "G10: hits are reported without control characters from file names" {
  printf 'x\n' > "$W/$(printf 'claude\033[31mred')"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [[ "$output" != *$'\033'* ]]
}
