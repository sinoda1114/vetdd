#!/usr/bin/env bats
# sanitize-candidates.sh: copies one workspace into <dest>/<label>/{artifact,evidence} and redacts origin words.

load test_helper
load helpers/eval_fixtures

setup() {
  isolate_git
  SRC="$BATS_TEST_TMPDIR/kata-app-1"
  DEST="$BATS_TEST_TMPDIR/run/candidates"
  mkdir -p "$SRC/src" "$SRC/node_modules/dep" "$SRC/src/node_modules/x" "$SRC/.vetdd/evidence/s1/runs" "$SRC/.vetdd/cache"
  printf 'export const v = 42;\n' > "$SRC/src/value.js"
  printf 'dep\n' > "$SRC/node_modules/dep/index.js"
  printf 'x\n' > "$SRC/src/node_modules/x/index.js"
  printf '{"slice_id":"s1"}\n' > "$SRC/.vetdd/evidence/s1/meta.json"
  printf 'ok 1 value\n' > "$SRC/.vetdd/evidence/s1/runs/001-after.log"
  printf 'cache\n' > "$SRC/.vetdd/cache/c.txt"
}

san() { "$SCRIPTS/sanitize-candidates.sh" "$@"; }

@test "copies the workspace to artifact/ and .vetdd/evidence to evidence/, and prints the destination" {
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 0 ]
  [ "$output" = "$DEST/c1" ]
  [ "$(cat "$DEST/c1/artifact/src/value.js")" = "export const v = 42;" ]
  [ "$(cat "$DEST/c1/evidence/s1/meta.json")" = '{"slice_id":"s1"}' ]
  [ -f "$DEST/c1/evidence/s1/runs/001-after.log" ]
}

@test ".git, node_modules (at any depth), and .vetdd are not copied into artifact/" {
  printf 'dist/\n' > "$SRC/.gitignore"
  (cd "$SRC" && git init -q && git add -A && git commit -q -m init)
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 0 ]
  [ -f "$DEST/c1/artifact/.gitignore" ]
  [ ! -e "$DEST/c1/artifact/.git" ]
  [ ! -e "$DEST/c1/artifact/node_modules" ]
  [ ! -e "$DEST/c1/artifact/src/node_modules" ]
  [ ! -e "$DEST/c1/artifact/.vetdd" ]
  [ ! -e "$DEST/c1/evidence/cache" ]
}

@test "no evidence directory is created when the workspace has none" {
  rm -rf "$SRC/.vetdd"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 0 ]
  [ -d "$DEST/c1/artifact" ]
  [ ! -e "$DEST/c1/evidence" ]
}

@test "model names are redacted case-insensitively in artifact and evidence text" {
  printf 'Written by Claude Opus 5 and GPT-6-sol via codex.\n' > "$SRC/NOTES.md"
  printf 'judge model gpt-6-sol\n' > "$SRC/.vetdd/evidence/s1/runs/001-after.log"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/c1/artifact/NOTES.md")" = "Written by [redacted] [redacted] 5 and [redacted] via [redacted]." ]
  [ "$(cat "$DEST/c1/evidence/s1/runs/001-after.log")" = "judge model [redacted]" ]
}

@test "the workspace basename and its git branch name are redacted by default" {
  (cd "$SRC" && git init -q && git checkout -q -b feat/fast-path && git add -A && git commit -q -m init)
  printf 'cd /work/kata-app-1 && git switch feat/fast-path\n' > "$SRC/HOWTO.md"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/c1/artifact/HOWTO.md")" = "cd /work/[redacted] && git switch [redacted]" ]
}

@test "--strip adds words to the default list" {
  printf 'variant alpha-lane, by Claude\n' > "$SRC/NOTES.md"
  run san --src "$SRC" --label c1 --dest "$DEST" --strip alpha-lane
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/c1/artifact/NOTES.md")" = "variant [redacted], by [redacted]" ]
}

@test "file and directory names containing a stripped word are renamed" {
  mkdir -p "$SRC/.claude/skills/kata"
  printf 'see .claude/skills/kata\n' > "$SRC/.claude/skills/kata/SKILL.md"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 0 ]
  [ ! -e "$DEST/c1/artifact/.claude" ]
  [ "$(cat "$DEST/c1/artifact/.[redacted]/skills/kata/SKILL.md")" = "see .[redacted]/skills/kata" ]
}

@test "binary files are copied byte for byte" {
  printf 'claude\000bin' > "$SRC/blob.bin"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 0 ]
  cmp "$SRC/blob.bin" "$DEST/c1/artifact/blob.bin"
}

@test "rerunning replaces the label directory" {
  printf 'old\n' > "$SRC/old.txt"
  san --src "$SRC" --label c1 --dest "$DEST"
  rm "$SRC/old.txt"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 0 ]
  [ ! -e "$DEST/c1/artifact/old.txt" ]
  [ -f "$DEST/c1/artifact/src/value.js" ]
}

@test "the sanitized output passes check-blind for model names" {
  printf 'Claude and gpt-6-sol\n' > "$SRC/NOTES.md"
  san --src "$SRC" --label c1 --dest "$DEST"
  run "$SCRIPTS/check-blind.sh" "$DEST" --profile judge
  [ "$status" -eq 0 ]
}

@test "an invalid label or a missing source is a usage error (exit 2)" {
  run san --src "$SRC" --label ../x --dest "$DEST"
  [ "$status" -eq 2 ]
  run san --src "$BATS_TEST_TMPDIR/nope" --label c1 --dest "$DEST"
  [ "$status" -eq 2 ]
}

@test "a symlink in the source is refused with a clear message and nothing is copied" {
  ln -s ../../outside.txt "$SRC/src/link.txt"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -ne 0 ]
  [[ "$output" == *"symlink"*"src/link.txt"* ]]
  [ ! -e "$DEST/c1" ]
}

@test "a symlink inside node_modules or .git is not copied and does not block" {
  ln -s ../dep "$SRC/node_modules/dep-link"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 0 ]
}

@test "--transcript copies the file to <label>/transcript.jsonl through the same redaction" {
  printf '{"role":"assistant","model":"claude-opus-5","cwd":"/work/kata-app-1"}\n' > "$BATS_TEST_TMPDIR/session.jsonl"
  run san --src "$SRC" --label c1 --dest "$DEST" --transcript "$BATS_TEST_TMPDIR/session.jsonl"
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/c1/transcript.jsonl")" = '{"role":"assistant","model":"[redacted]-[redacted]-5","cwd":"/work/[redacted]"}' ]
  run san --src "$SRC" --label c1 --dest "$DEST" --transcript "$BATS_TEST_TMPDIR/nope.jsonl"
  [ "$status" -eq 2 ]
}

@test "redaction uses the same whole-word boundaries as detection" {
  printf 'breakfast, fast lane, fastest; Claudette met Claude and two claudes\n' > "$SRC/NOTES.md"
  run san --src "$SRC" --label c1 --dest "$DEST" --strip fast
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/c1/artifact/NOTES.md")" = "breakfast, [redacted] lane, fastest; Claudette met [redacted] and two [redacted]" ]
}

@test "main, master, HEAD, and init.defaultBranch are never strip words" {
  (cd "$SRC" && git init -q && git checkout -q -b main && git add -A && git commit -q -m init)
  printf 'merge into main, not master; HEAD moved\n' > "$SRC/HOWTO.md"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/c1/artifact/HOWTO.md")" = "merge into main, not master; HEAD moved" ]
  git config --global init.defaultBranch trunk
  (cd "$SRC" && git checkout -q -b trunk)
  printf 'push trunk\n' > "$SRC/HOWTO.md"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/c1/artifact/HOWTO.md")" = "push trunk" ]
  run san --src "$SRC" --label c1 --dest "$DEST" --strip master
  [ "$status" -eq 2 ]
  [[ "$output" == *"master"* ]]
}

@test "a strip word shorter than 4 characters is refused" {
  run san --src "$SRC" --label c1 --dest "$DEST" --strip abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"abc"*"4"* ]]
  [ ! -e "$DEST/c1" ]
}

@test "text already inside [redacted] is never redacted again" {
  printf 'by Anthropic; already [redacted] here\n' > "$SRC/NOTES.md"
  run san --src "$SRC" --label c1 --dest "$DEST" --strip redacted
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/c1/artifact/NOTES.md")" = "by [redacted]; already [redacted] here" ]
}

@test "--variants makes every variant name in variants.json a strip word" {
  printf '{"c1": "alpha-lane", "c2": "beta lane v2"}\n' > "$BATS_TEST_TMPDIR/variants.json"
  printf 'from alpha-lane, not beta lane v2\n' > "$SRC/NOTES.md"
  run san --src "$SRC" --label c1 --dest "$DEST" --variants "$BATS_TEST_TMPDIR/variants.json"
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/c1/artifact/NOTES.md")" = "from [redacted], not [redacted]" ]
  printf '["alpha-lane"]\n' > "$BATS_TEST_TMPDIR/variants.json"
  run san --src "$SRC" --label c1 --dest "$DEST" --variants "$BATS_TEST_TMPDIR/variants.json"
  [ "$status" -eq 2 ]
}

@test "a workspace named like a protected branch still sanitizes (no strip words beyond the defaults)" {
  mkdir -p "$BATS_TEST_TMPDIR/ws/master"
  printf 'by Claude on master\n' > "$BATS_TEST_TMPDIR/ws/master/NOTES.md"
  run san --src "$BATS_TEST_TMPDIR/ws/master" --label c1 --dest "$DEST"
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/c1/artifact/NOTES.md")" = "by [redacted] on master" ]
}

@test "G2: a .vetdd that is itself a symlink is refused" {
  mkdir -p "$BATS_TEST_TMPDIR/outside/evidence/s1" && printf '{}\n' > "$BATS_TEST_TMPDIR/outside/evidence/s1/meta.json"
  rm -rf "$SRC/.vetdd" && ln -s "$BATS_TEST_TMPDIR/outside" "$SRC/.vetdd"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -ne 0 ]
  [[ "$output" == *".vetdd"* ]]
  [ ! -e "$DEST/c1/evidence" ]
}

@test "G7: a label must be c followed by digits only, as the verdict schema requires" {
  run san --src "$SRC" --label c1a --dest "$DEST"
  [ "$status" -ne 0 ]
  [ ! -e "$DEST/c1a" ]
}

@test "G8: a file the archiver cannot read makes the copy fail instead of passing short" {
  [ "$(id -u)" -ne 0 ] || skip "root reads unreadable files"
  printf 'secret\n' > "$SRC/unreadable.txt" && chmod 000 "$SRC/unreadable.txt"
  run san --src "$SRC" --label c1 --dest "$DEST"
  chmod 644 "$SRC/unreadable.txt"
  [ "$status" -ne 0 ]
}

@test "G10: file names are printed without control characters" {
  ln -s /nonexistent "$SRC/$(printf 'bad\033]0;title\007name')"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -ne 0 ]
  [[ "$output" != *$'\033'* ]]
  [[ "$output" != *$'\007'* ]]
}
