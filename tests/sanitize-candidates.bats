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
  printf 'from alpha-lane, by Claude\n' > "$SRC/NOTES.md"
  run san --src "$SRC" --label c1 --dest "$DEST" --strip alpha-lane
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/c1/artifact/NOTES.md")" = "from [redacted], by [redacted]" ]
}

@test "file and directory names containing a stripped word are renamed" {
  mkdir -p "$SRC/.claude/skills/kata"
  printf 'see .claude/skills/kata\n' > "$SRC/.claude/skills/kata/SKILL.md"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 0 ]
  [ ! -e "$DEST/c1/artifact/.claude" ]
  [ "$(cat "$DEST/c1/artifact/.[redacted]/skills/kata/SKILL.md")" = "see .[redacted]/skills/kata" ]
}

@test "a binary file is refused, not published: its contents cannot be redacted or checked" {
  printf 'claude\000bin' > "$SRC/blob.bin"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact/blob.bin:binary: not scanned"* ]]
  [ ! -e "$DEST/c1" ]
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

@test "H8: a failed rerun keeps the previous copy and leaves no temporary directory" {
  printf 'first\n' > "$SRC/NOTES.md"
  san --src "$SRC" --label c1 --dest "$DEST"
  # Both names redact to "[redacted].txt": the rerun fails on the rename.
  printf 'a\n' > "$SRC/claude.txt"
  printf 'b\n' > "$SRC/[redacted].txt"
  printf 'second\n' > "$SRC/NOTES.md"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 1 ]
  [ "$(cat "$DEST/c1/artifact/NOTES.md")" = "first" ]
  [ ! -e "$DEST/c1/artifact/claude.txt" ]
  [ "$(ls -A "$DEST")" = "c1" ]
}

@test "H8: a successful run leaves only the label directory in the destination" {
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 0 ]
  [ "$(ls -A "$DEST")" = "c1" ]
}

@test "H8: a copy that still reveals an origin word fails the self-check and is not published" {
  printf 'the winner is this one\n' > "$SRC/NOTES.md"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact/NOTES.md:1: winner"* ]]
  [[ "$output" != *".sanitize-"* ]]
  [ ! -e "$DEST/c1" ]
  [ -z "$(ls -A "$DEST")" ]
}

@test "H1: .env and .env.* are not copied, at any depth" {
  printf 'TOKEN=x\n' > "$SRC/.env"
  printf 'TOKEN=y\n' > "$SRC/.env.local"
  printf 'TOKEN=z\n' > "$SRC/src/.env"
  printf 'keep\n' > "$SRC/src/env.js"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 0 ]
  [ ! -e "$DEST/c1/artifact/.env" ]
  [ ! -e "$DEST/c1/artifact/.env.local" ]
  [ ! -e "$DEST/c1/artifact/src/.env" ]
  [ -f "$DEST/c1/artifact/src/env.js" ]
}

@test "H4: a --src inside --dest is refused and the source is left intact" {
  san --src "$SRC" --label c1 --dest "$DEST"
  run san --src "$DEST/c1/artifact" --label c1 --dest "$DEST"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--src must be outside --dest"* ]]
  [ -f "$DEST/c1/artifact/src/value.js" ]
  run san --src "$DEST" --label c2 --dest "$DEST"
  [ "$status" -eq 2 ]
}

@test "--words-out appends the strip words, without the model names, one per line" {
  (cd "$SRC" && git init -q && git checkout -q -b feat/fast-path && git add -A && git commit -q -m init)
  printf '{"c1": "alpha-lane", "c2": "beta lane v2"}\n' > "$BATS_TEST_TMPDIR/variants.json"
  printf 'earlier\n' > "$BATS_TEST_TMPDIR/blind-words.txt"
  run san --src "$SRC" --label c1 --dest "$DEST" --variants "$BATS_TEST_TMPDIR/variants.json" \
    --strip extra-word --words-out "$BATS_TEST_TMPDIR/blind-words.txt"
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$BATS_TEST_TMPDIR/blind-words.txt")" = "earlier" ]
  [ "$(sed 1d "$BATS_TEST_TMPDIR/blind-words.txt" | sort | tr '\n' ,)" = "alpha-lane,beta lane v2,extra-word,feat/fast-path,kata-app-1," ]
  run "$SCRIPTS/check-blind.sh" "$DEST" --profile judge --extra-words "$BATS_TEST_TMPDIR/blind-words.txt"
  [ "$status" -eq 0 ]
}

@test "--words-out is not written when the run fails" {
  printf 'the winner is this one\n' > "$SRC/NOTES.md"
  run san --src "$SRC" --label c1 --dest "$DEST" --words-out "$BATS_TEST_TMPDIR/blind-words.txt"
  [ "$status" -eq 1 ]
  [ ! -s "$BATS_TEST_TMPDIR/blind-words.txt" ]
}

@test "H3: errors from bash and the tools are printed without control characters" {
  [ "$(id -u)" -ne 0 ] || skip "root writes read-only files"
  local name
  name="$(printf 'bad\nline\033]0;title\007.txt')"
  printf 'by Claude\n' > "$SRC/$name" && chmod 444 "$SRC/$name"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bad"* ]]
  [[ "$output" != *$'\033'* ]]
  [[ "$output" != *$'\007'* ]]
}

@test "works under macOS /bin/bash 3.2" {
  [ -x /bin/bash ] || skip "/bin/bash missing"
  printf 'by Claude\n' > "$SRC/NOTES.md"
  run /bin/bash "$SCRIPTS/sanitize-candidates.sh" --src "$SRC" --label c1 --dest "$DEST" --words-out "$BATS_TEST_TMPDIR/w.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "$DEST/c1" ]
  [ "$(cat "$DEST/c1/artifact/NOTES.md")" = "by [redacted]" ]
  [ "$(cat "$BATS_TEST_TMPDIR/w.txt")" = "kata-app-1" ]
  printf 'the winner\n' > "$SRC/NOTES.md"
  run /bin/bash "$SCRIPTS/sanitize-candidates.sh" --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 1 ]
  [ "$(cat "$DEST/c1/artifact/NOTES.md")" = "by [redacted]" ]
  [ "$(ls -A "$DEST")" = "c1" ]
}

# fake_bin <name> <body>: a script on a private PATH directory, for faking one tool.
fake_bin() {
  mkdir -p "$BATS_TEST_TMPDIR/fakebin"
  printf '#!/bin/sh\n%s\n' "$2" > "$BATS_TEST_TMPDIR/fakebin/$1"
  chmod +x "$BATS_TEST_TMPDIR/fakebin/$1"
}

@test "R4: a text file with an invalid UTF-8 byte is redacted under a UTF-8 locale" {
  [ "$(LC_ALL=ja_JP.UTF-8 locale charmap 2>/dev/null)" = UTF-8 ] || skip "ja_JP.UTF-8 locale missing"
  # GNU grep -I in a UTF-8 locale calls such a file binary (macOS grep does not); fake that
  # behavior so the choice of text files is shown not to depend on grep or the locale.
  fake_bin grep 'case "$1" in -I*) case "${LC_ALL:-}" in *UTF-8*) for a; do :; done
  LC_ALL=C tr -d "\377" < "$a" | cmp -s - "$a" || exit 1 ;; esac ;; esac
exec /usr/bin/grep "$@"'
  printf 'by Claude \377 here\n' > "$SRC/NOTES.md"
  LC_ALL=ja_JP.UTF-8 PATH="$BATS_TEST_TMPDIR/fakebin:$PATH" run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/c1/artifact/NOTES.md")" = "$(printf 'by [redacted] \377 here')" ]
}

@test "R5: when the new copy cannot be moved into place, the previous copy stays and no temporary directory is left" {
  printf 'first\n' > "$SRC/NOTES.md"
  san --src "$SRC" --label c1 --dest "$DEST"
  printf 'second\n' > "$SRC/NOTES.md"
  # Only the move of the staged copy fails; every other mv works.
  fake_bin mv 'case "${1##*/}" in .sanitize-*) echo "mv: refused" >&2; exit 1 ;; esac
exec /bin/mv "$@"'
  PATH="$BATS_TEST_TMPDIR/fakebin:$PATH" run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 1 ]
  [ "$(cat "$DEST/c1/artifact/NOTES.md")" = "first" ]
  [ "$(ls -A "$DEST")" = "c1" ]
}

@test "R5: an interruption after the previous copy is set aside puts it back" {
  printf 'first\n' > "$SRC/NOTES.md"
  san --src "$SRC" --label c1 --dest "$DEST"
  printf 'second\n' > "$SRC/NOTES.md"
  # The staged copy's move is where the script is terminated.
  fake_bin mv 'case "${1##*/}" in .sanitize-*) kill -TERM "$PPID"; sleep 1; exit 1 ;; esac
exec /bin/mv "$@"'
  PATH="$BATS_TEST_TMPDIR/fakebin:$PATH" run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 143 ]
  [ "$(cat "$DEST/c1/artifact/NOTES.md")" = "first" ]
  [ "$(ls -A "$DEST")" = "c1" ]
}

@test "R3: the run directory's absolute path, in both forms, is redacted but not written to --words-out" {
  local run_l run_p
  run_l="$BATS_TEST_TMPDIR/run"
  mkdir -p "$DEST"
  printf '{"c1": "alpha-lane"}\n' > "$run_l/variants.json"
  run_p="$(cd "$run_l" && pwd -P)"
  printf '{"cwd":"%s/rubric.md","real":"%s/rubric.md"}\n' "$run_l" "$run_p" > "$BATS_TEST_TMPDIR/session.jsonl"
  run san --src "$SRC" --label c1 --dest "$DEST" --transcript "$BATS_TEST_TMPDIR/session.jsonl" \
    --words-out "$BATS_TEST_TMPDIR/w.txt"
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/c1/transcript.jsonl")" = '{"cwd":"[redacted]/rubric.md","real":"[redacted]/rubric.md"}' ]
  [ "$(cat "$BATS_TEST_TMPDIR/w.txt")" = "kata-app-1" ]
}

@test "R3: when the run directory has variants.json (as judge.sh checks), its git toplevel is redacted too" {
  local top_l top_p run_dir
  top_l="$BATS_TEST_TMPDIR/skillrepo"
  run_dir="$top_l/evals/e1/runs/r1"
  mkdir -p "$run_dir/candidates"
  (cd "$top_l" && git init -q)
  top_p="$(cd "$top_l" && pwd -P)"
  printf '{"c1": "alpha-lane"}\n' > "$run_dir/variants.json"
  printf 'read %s/skills/x/SKILL.md and %s/skills/x/SKILL.md, wrote %s/rubric.md\n' \
    "$top_l" "$top_p" "$run_dir" > "$BATS_TEST_TMPDIR/session.jsonl"
  run san --src "$SRC" --label c1 --dest "$run_dir/candidates" --variants "$run_dir/variants.json" \
    --transcript "$BATS_TEST_TMPDIR/session.jsonl"
  [ "$status" -eq 0 ]
  [ "$(cat "$run_dir/candidates/c1/transcript.jsonl")" = "read [redacted]/skills/x/SKILL.md and [redacted]/skills/x/SKILL.md, wrote [redacted]/rubric.md" ]
  # Without --variants but with variants.json in the run directory: judge.sh refuses the toplevel, so redact it.
  run san --src "$SRC" --label c1 --dest "$run_dir/candidates" --transcript "$BATS_TEST_TMPDIR/session.jsonl"
  [ "$status" -eq 0 ]
  [ "$(cat "$run_dir/candidates/c1/transcript.jsonl")" = "read [redacted]/skills/x/SKILL.md and [redacted]/skills/x/SKILL.md, wrote [redacted]/rubric.md" ]
  # No variants.json (as a final verdict has it): no path is a word, as judge.sh refuses none there.
  rm "$run_dir/variants.json"
  run san --src "$SRC" --label c1 --dest "$run_dir/candidates" --transcript "$BATS_TEST_TMPDIR/session.jsonl"
  [ "$status" -eq 0 ]
  [ "$(cat "$run_dir/candidates/c1/transcript.jsonl")" = "read $top_l/skills/x/SKILL.md and $top_p/skills/x/SKILL.md, wrote $run_dir/rubric.md" ]
}

@test "a hard link in the source is refused with a list, and nothing is copied" {
  printf 'outside\n' > "$BATS_TEST_TMPDIR/outside.txt"
  ln "$BATS_TEST_TMPDIR/outside.txt" "$SRC/src/inside.txt"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 2 ]
  [[ "$output" == *"hard link"*"src/inside.txt"* ]]
  [ ! -e "$DEST/c1" ]
}

@test "a hard link inside .vetdd/evidence is refused: the evidence is copied too" {
  printf 'outside\n' > "$BATS_TEST_TMPDIR/outside.log"
  ln "$BATS_TEST_TMPDIR/outside.log" "$SRC/.vetdd/evidence/s1/runs/002-after.log"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 2 ]
  [[ "$output" == *"hard link"*"002-after.log"* ]]
  [ ! -e "$DEST/c1" ]
}

@test "a hard link inside node_modules, .git, or .vetdd outside evidence does not block" {
  ln "$SRC/node_modules/dep/index.js" "$SRC/node_modules/dep/again.js"
  ln "$SRC/.vetdd/cache/c.txt" "$SRC/.vetdd/cache/d.txt"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 0 ]
}

@test "secret-bearing files are not copied, at any depth; similar names are" {
  mkdir -p "$SRC/sub/.ssh" "$SRC/.aws"
  printf 'x\n' > "$SRC/.npmrc"
  printf 'x\n' > "$SRC/sub/id.pem"
  printf 'x\n' > "$SRC/sub/.ssh/config"
  printf 'x\n' > "$SRC/.aws/credentials"
  printf 'x\n' > "$SRC/sub/.netrc"
  printf 'x\n' > "$SRC/.pypirc"
  printf 'x\n' > "$SRC/.envrc"
  printf 'x\n' > "$SRC/.dev.vars"
  printf 'x\n' > "$SRC/sub/tls.key"
  printf 'x\n' > "$SRC/cert.p12"
  printf 'x\n' > "$SRC/cert.pfx"
  printf 'x\n' > "$SRC/prod.tfvars"
  printf 'keep\n' > "$SRC/src/key.js"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 0 ]
  local p
  for p in .npmrc sub/id.pem sub/.ssh .aws sub/.netrc .pypirc .envrc .dev.vars sub/tls.key cert.p12 cert.pfx prod.tfvars; do
    [ ! -e "$DEST/c1/artifact/$p" ] || { echo "copied: $p"; false; }
  done
  [ -f "$DEST/c1/artifact/src/key.js" ]
}

@test "a strip word that starts with # or has surrounding spaces is refused (exit 2)" {
  run san --src "$SRC" --label c1 --dest "$DEST" --strip '#nightly'
  [ "$status" -eq 2 ]
  [[ "$output" == *"#nightly"* ]]
  printf '{"c1": " alpha "}\n' > "$BATS_TEST_TMPDIR/variants.json"
  run san --src "$SRC" --label c1 --dest "$DEST" --variants "$BATS_TEST_TMPDIR/variants.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"alpha"* ]]
  [ ! -e "$DEST/c1" ]
}

@test "a failed self-check names the judge check in general and lists the hits before the message" {
  printf 'the winner is this one\n' > "$SRC/NOTES.md"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact/NOTES.md:1: winner"*"fails the judge check (origin words, model names, secrets, binaries, node_modules or .git)"* ]]
  [[ "$output" != *"still reveals an origin"* ]]
}

@test "S2: --allow-secrets exempts secret-shaped test data from the self-check by path" {
  mkdir -p "$SRC/tests"
  {
    printf 'const who = "qa.person@%s.co.jp";\n' acme
    printf 'const cfg = { password: "%s" };\n' correct-horse
  } > "$SRC/tests/fixture.ts"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact/tests/fixture.ts:1: secret: email"* ]]
  [ ! -e "$DEST/c1" ]
  run san --src "$SRC" --label c1 --dest "$DEST" --allow-secrets 'artifact/tests/*'
  [ "$status" -eq 0 ]
  cmp "$SRC/tests/fixture.ts" "$DEST/c1/artifact/tests/fixture.ts"
  printf 'by claude\n' >> "$SRC/tests/fixture.ts"
  run san --src "$SRC" --label c1 --dest "$DEST" --allow-secrets 'artifact/tests/*'
  [ "$status" -eq 0 ]
  [ "$(sed -n 3p "$DEST/c1/artifact/tests/fixture.ts")" = "by [redacted]" ]
}

@test "S3: with --transcript, git's user.email is redacted and not written to --words-out" {
  local mail
  mail="dev.person@$(printf '%s-%s' acme corp).jp"
  git config --global user.email "$mail"
  printf '{"text":"signed in as %s","cwd":"/work/kata-app-1"}\n' "$mail" > "$BATS_TEST_TMPDIR/session.jsonl"
  run san --src "$SRC" --label c1 --dest "$DEST" --transcript "$BATS_TEST_TMPDIR/session.jsonl" \
    --words-out "$BATS_TEST_TMPDIR/w.txt"
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/c1/transcript.jsonl")" = '{"text":"signed in as [redacted]","cwd":"/work/[redacted]"}' ]
  [ "$(cat "$BATS_TEST_TMPDIR/w.txt")" = "kata-app-1" ]
}

@test "S3: another address in the transcript still stops the run" {
  printf '{"text":"cc ops.lead@%s.co.jp"}\n' acme > "$BATS_TEST_TMPDIR/session.jsonl"
  run san --src "$SRC" --label c1 --dest "$DEST" --transcript "$BATS_TEST_TMPDIR/session.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"transcript.jsonl:1: secret: email"* ]]
  [ ! -e "$DEST/c1" ]
}

@test "S6: secret-bearing files inside .vetdd/evidence are not copied; the rest of the evidence is" {
  printf 'TOKEN=x\n' > "$SRC/.vetdd/evidence/s1/.env"
  printf 'x\n' > "$SRC/.vetdd/evidence/s1/key.pem"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/c1/evidence/s1/meta.json")" = '{"slice_id":"s1"}' ]
  [ -f "$DEST/c1/evidence/s1/runs/001-after.log" ]
  [ ! -e "$DEST/c1/evidence/s1/.env" ]
  [ ! -e "$DEST/c1/evidence/s1/key.pem" ]
}

@test "more secret-bearing names and .DS_Store are not copied, at any depth" {
  mkdir -p "$SRC/sub/.docker" "$SRC/.kube" "$SRC/infra"
  printf 'Bud1\000\000\001' > "$SRC/.DS_Store"
  printf 'Bud1\000\000\001' > "$SRC/sub/.DS_Store"
  printf 'x\n' > "$SRC/id_rsa"
  printf 'x\n' > "$SRC/sub/id_ed25519"
  printf 'x\n' > "$SRC/sub/id_ecdsa"
  printf 'x\n' > "$SRC/.git-credentials"
  printf 'x\n' > "$SRC/sub/.pgpass"
  printf 'x\n' > "$SRC/.htpasswd"
  printf 'x\n' > "$SRC/sub/credentials.json"
  printf 'x\n' > "$SRC/infra/terraform.tfstate"
  printf 'x\n' > "$SRC/infra/prod.tfstate"
  printf 'x\n' > "$SRC/sub/.docker/config.json"
  printf 'x\n' > "$SRC/.kube/config"
  printf 'keep\n' > "$SRC/src/id_rsa.md"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 0 ]
  local p
  for p in .DS_Store sub/.DS_Store id_rsa sub/id_ed25519 sub/id_ecdsa .git-credentials sub/.pgpass .htpasswd \
           sub/credentials.json infra/terraform.tfstate infra/prod.tfstate sub/.docker .kube; do
    [ ! -e "$DEST/c1/artifact/$p" ] || { echo "copied: $p"; false; }
  done
  [ -f "$DEST/c1/artifact/src/id_rsa.md" ]
}

@test "T1: the run directory's path right after a JSON \\n in the transcript is redacted, the escape kept" {
  local run_l
  run_l="$BATS_TEST_TMPDIR/run"
  mkdir -p "$DEST"
  printf '{"c1": "alpha-lane"}\n' > "$run_l/variants.json"
  printf '{"text":"a\\n%s/rubric.md"}\n' "$run_l" > "$BATS_TEST_TMPDIR/session.jsonl"
  run san --src "$SRC" --label c1 --dest "$DEST" --transcript "$BATS_TEST_TMPDIR/session.jsonl"
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/c1/transcript.jsonl")" = '{"text":"a\n[redacted]/rubric.md"}' ]
}

@test "T1: a model name right after an ANSI color code in the evidence is redacted" {
  printf '\033[2mclaude\033[0m and \\u001b[1mopus\n' > "$SRC/.vetdd/evidence/s1/runs/001-after.log"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/c1/evidence/s1/runs/001-after.log")" = "$(printf '\033[2m[redacted]\033[0m and \\u001b[1m[redacted]')" ]
}

@test "the run directory's path written with JSON's \\/ escape is redacted and not written to --words-out" {
  local run_l run_p esc_l esc_p
  run_l="$BATS_TEST_TMPDIR/run"
  mkdir -p "$DEST"
  printf '{"c1": "alpha-lane"}\n' > "$run_l/variants.json"
  run_p="$(cd "$run_l" && pwd -P)"
  esc_l="$(printf '%s' "$run_l" | sed 's|/|\\/|g')"
  esc_p="$(printf '%s' "$run_p" | sed 's|/|\\/|g')"
  printf '{"cwd":"%s\\/rubric.md","real":"%s\\/rubric.md"}\n' "$esc_l" "$esc_p" > "$BATS_TEST_TMPDIR/session.jsonl"
  run san --src "$SRC" --label c1 --dest "$DEST" --transcript "$BATS_TEST_TMPDIR/session.jsonl" \
    --words-out "$BATS_TEST_TMPDIR/w.txt"
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/c1/transcript.jsonl")" = '{"cwd":"[redacted]\/rubric.md","real":"[redacted]\/rubric.md"}' ]
  [ "$(cat "$BATS_TEST_TMPDIR/w.txt")" = "kata-app-1" ]
}

@test "S3: a user.email set in the workspace's own git config is redacted too" {
  local mail
  mail="ws.owner@$(printf '%s-%s' acme corp).jp"
  (cd "$SRC" && git init -q && git config user.email "$mail" && git add -A && git commit -q -m init)
  printf '{"text":"committed as %s"}\n' "$mail" > "$BATS_TEST_TMPDIR/session.jsonl"
  run san --src "$SRC" --label c1 --dest "$DEST" --transcript "$BATS_TEST_TMPDIR/session.jsonl" \
    --words-out "$BATS_TEST_TMPDIR/w.txt"
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/c1/transcript.jsonl")" = '{"text":"committed as [redacted]"}' ]
  [ "$(cat "$BATS_TEST_TMPDIR/w.txt")" = "kata-app-1" ]
}

@test "U1: --allow-secrets 'transcript.jsonl:email' lets a confirmed address through; a token in the same file still stops the run" {
  local tok
  tok="$(printf '%s_%s' ghp abcdefghijklmnopqrstuvwxyz0123456789)"
  printf '{"text":"cc ops.lead@%s.co.jp"}\n' acme > "$BATS_TEST_TMPDIR/session.jsonl"
  run san --src "$SRC" --label c1 --dest "$DEST" --transcript "$BATS_TEST_TMPDIR/session.jsonl" \
    --allow-secrets 'transcript.jsonl:email'
  [ "$status" -eq 0 ]
  [ -f "$DEST/c1/transcript.jsonl" ]
  printf '{"text":"export GH=%s"}\n' "$tok" >> "$BATS_TEST_TMPDIR/session.jsonl"
  rm -rf "$DEST/c1"
  run san --src "$SRC" --label c1 --dest "$DEST" --transcript "$BATS_TEST_TMPDIR/session.jsonl" \
    --allow-secrets 'transcript.jsonl:email'
  [ "$status" -eq 1 ]
  [[ "$output" == *"transcript.jsonl:2: secret: github-token"* ]]
  [[ "$output" != *"transcript.jsonl:1: secret"* ]]
  [ ! -e "$DEST/c1" ]
}

@test "U1: --allow-secrets with an unknown kind fails and publishes nothing" {
  mkdir -p "$SRC/tests"
  printf 'const who = "qa.person@%s.co.jp";\n' acme > "$SRC/tests/fixture.ts"
  run san --src "$SRC" --label c1 --dest "$DEST" --allow-secrets 'artifact/tests/*:emial'
  # Y4: a usage error (exit 2), caught before anything is copied.
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown secret kind 'emial'"* ]]
  [ -z "$(ls -A "$DEST" 2>/dev/null)" ]
  run san --src "$SRC" --label c1 --dest "$DEST" --allow-secrets ':email'
  [ "$status" -eq 2 ]
  run san --src "$SRC" --label c1 --dest "$DEST" --allow-secrets 'artifact/*:email,'
  [ "$status" -eq 2 ]
  [ ! -e "$DEST/c1" ]
}

@test "X1: without --variants or variants.json the run directory's path is not redacted" {
  local run_l run_p
  run_l="$BATS_TEST_TMPDIR/run"
  mkdir -p "$DEST"
  run_p="$(cd "$run_l" && pwd -P)"
  printf '{"cwd":"%s/rubric.md","real":"%s/rubric.md"}\n' "$run_l" "$run_p" > "$BATS_TEST_TMPDIR/session.jsonl"
  run san --src "$SRC" --label c1 --dest "$DEST" --transcript "$BATS_TEST_TMPDIR/session.jsonl" \
    --words-out "$BATS_TEST_TMPDIR/w.txt"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  cmp "$BATS_TEST_TMPDIR/session.jsonl" "$DEST/c1/transcript.jsonl"
  [ "$(cat "$BATS_TEST_TMPDIR/w.txt")" = "kata-app-1" ]
}

@test "X3: a run directory given through a symlinked evals does not make a directory above it a word" {
  local top run_dir top_p
  top="$BATS_TEST_TMPDIR/store/deep/skillrepo"
  mkdir -p "$top/evals/e1/runs/r1"
  git -C "$top" init -q
  top_p="$(cd "$top" && pwd -P)"
  ln -s "$top/evals" "$BATS_TEST_TMPDIR/evals"
  run_dir="$BATS_TEST_TMPDIR/evals/e1/runs/r1"
  printf '{"c1": "alpha-lane"}\n' > "$run_dir/variants.json"
  printf 'read %s/skills/x/SKILL.md, wrote %s/home/notes.txt\n' "$top_p" "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/session.jsonl"
  run san --src "$SRC" --label c1 --dest "$run_dir/candidates" --variants "$run_dir/variants.json" \
    --transcript "$BATS_TEST_TMPDIR/session.jsonl"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$run_dir/candidates/c1/transcript.jsonl")" = "read [redacted]/skills/x/SKILL.md, wrote $BATS_TEST_TMPDIR/home/notes.txt" ]
}

@test "X3: a logical toplevel that climbs to / is dropped, not refused" {
  local top deep run_dir top_p i
  top="$BATS_TEST_TMPDIR/store/skillrepo"
  deep="$top"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do deep="$deep/d$i"; done
  mkdir -p "$deep/evals/e1/runs/r1"
  git -C "$top" init -q
  top_p="$(cd "$top" && pwd -P)"
  ln -s "$deep/evals" "$BATS_TEST_TMPDIR/evals"
  run_dir="$BATS_TEST_TMPDIR/evals/e1/runs/r1"
  printf '{"c1": "alpha-lane"}\n' > "$run_dir/variants.json"
  printf 'read %s/README.md\n' "$top_p" > "$BATS_TEST_TMPDIR/session.jsonl"
  run san --src "$SRC" --label c1 --dest "$run_dir/candidates" --variants "$run_dir/variants.json" \
    --transcript "$BATS_TEST_TMPDIR/session.jsonl"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$run_dir/candidates/c1/transcript.jsonl")" = "read [redacted]/README.md" ]
}

@test "Y3: with a symlinked candidates directory, the run directory is its parent as written, as in judge.sh" {
  local repo run_dir elsewhere
  repo="$BATS_TEST_TMPDIR/skillrepo"
  run_dir="$repo/evals/e1/runs/r1"
  elsewhere="$BATS_TEST_TMPDIR/scratch/cands"
  mkdir -p "$run_dir" "$elsewhere"
  (cd "$repo" && git init -q)
  printf '{"c1": "alpha-lane"}\n' > "$run_dir/variants.json"
  ln -s "$elsewhere" "$run_dir/candidates"
  printf 'read %s/skills/x/SKILL.md\n' "$repo" > "$BATS_TEST_TMPDIR/session.jsonl"
  run san --src "$SRC" --label c1 --dest "$run_dir/candidates" --variants "$run_dir/variants.json" \
    --transcript "$BATS_TEST_TMPDIR/session.jsonl"
  [ "$status" -eq 0 ]
  [ "$(cat "$elsewhere/c1/transcript.jsonl")" = "read [redacted]/skills/x/SKILL.md" ]
}

@test "Z3: a FIFO in the workspace is refused (exit 2) and nothing is copied" {
  mkfifo "$SRC/src/pipe"
  run san --src "$SRC" --label c1 --dest "$DEST"
  [ "$status" -eq 2 ]
  [[ "$output" == *"special files"*"src/pipe"* ]]
  [ ! -e "$DEST/c1" ]
}

@test "Z4: a short git root path (/w in a container) is redacted, not refused as a short strip word" {
  run bash -c '. "$1/lib/common.sh"; . "$1/lib/blind-words.sh"; f="$2/w"; vetdd_word_file "$f" /w; printf "see /w/evals/x\n" > "$2/in"; vetdd_redact "$f" "$2/in"' _ "$SCRIPTS" "$BATS_TEST_TMPDIR"
  [ "$output" = "see [redacted]/evals/x" ]
  grep -n 'MIN_STRIP_LEN' "$SCRIPTS/sanitize-candidates.sh" >/dev/null
  run grep -c 'check_strip "\$p"' "$SCRIPTS/sanitize-candidates.sh"
  [ "$output" = "0" ]
}
