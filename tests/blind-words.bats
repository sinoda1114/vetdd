#!/usr/bin/env bats
# lib/blind-words.sh: the whole-word matchers shared by check-blind.sh and sanitize-candidates.sh.
# A word right after a JSON escape (\n \r \t \uXXXX) or an ANSI color code counts as a whole word.

load test_helper

setup() {
  . "$SCRIPTS/lib/blind-words.sh"
  MAIL="dev.person@$(printf '%s-%s' acme corp).jp"
  RUN_DIR="/Users/x/repo/evals/e1/runs/r1"
  W="$BATS_TEST_TMPDIR/words"
  vetdd_word_file "$W" "$RUN_DIR" "$MAIL" opus alpha-lane
  IN="$BATS_TEST_TMPDIR/in.txt"
}

# find_in <text>: vetdd_find_words over one line of text.
find_in() { printf '%s\n' "$1" > "$IN"; vetdd_find_words "$W" t "" < "$IN"; }
# redact_line <text>: vetdd_redact over one line of text.
redact_line() { printf '%s\n' "$1" > "$IN"; vetdd_redact "$W" "$IN"; }

@test "a path right after a JSON \\n is found and redacted, and the escape is kept" {
  local line='{"text":"ok\n'"$RUN_DIR"'/variants.json"}'
  run find_in "$line"
  [ "$status" -eq 0 ]
  [ "$output" = "t:1: $(printf '%s' "$RUN_DIR" | tr 'A-Z' 'a-z')" ]
  run redact_line "$line"
  [ "$status" -eq 0 ]
  [ "$output" = '{"text":"ok\n[redacted]/variants.json"}' ]
}

@test "a word right after \\r, \\t, or \\uXXXX is found and redacted" {
  local e
  for e in '\r' '\t' ' ' ' '; do
    run find_in "x${e}opus 5"
    [ "$output" = "t:1: opus" ] || { echo "escape $e: $output"; false; }
    run redact_line "x${e}opus 5"
    [ "$output" = "x${e}[redacted] 5" ] || { echo "escape $e: $output"; false; }
  done
}

@test "the email, the model name, and the variant name right after \\n are found and redacted" {
  run find_in "by\\n${MAIL}\\nopus\\nalpha-lane"
  [[ "$output" == *"t:1: $MAIL"* ]]
  [[ "$output" == *"t:1: opus"* ]]
  [[ "$output" == *"t:1: alpha-lane"* ]]
  run redact_line "by\\n${MAIL}\\nopus\\nalpha-lane"
  [ "$output" = 'by\n[redacted]\n[redacted]\n[redacted]' ]
}

@test "a word right after an ANSI color code (raw ESC or its escaped spellings) is found and redacted" {
  local esc code
  esc="$(printf '\033')"
  for code in "${esc}[2m" "${esc}[1;31m" '\033[1;31m' '\x1b[0m' '\x1B[0m' '\e[1m' '\u001b[2m' '\u001B[38;5;2m'; do
    run find_in "log ${code}${RUN_DIR}/variants.json"
    [ "$output" = "t:1: $(printf '%s' "$RUN_DIR" | tr 'A-Z' 'a-z')" ] || { echo "code $code: $output"; false; }
    run redact_line "log ${code}opus"
    [ "$output" = "log ${code}[redacted]" ] || { echo "code $code: $output"; false; }
  done
}

@test "a word followed by an escape or a color code keeps its trailing boundary" {
  run find_in 'x opus\n'
  [ "$output" = "t:1: opus" ]
  run redact_line 'x opus\u001b[0m y'
  [ "$output" = 'x [redacted]\u001b[0m y' ]
}

@test "a letter or digit that is not the end of an escape still blocks the match" {
  local line
  for line in 'anopus' 'x2mopus' 'x[2mopus' 'x\u00Gopus' 'the magnum opusx' 'ab\qopus'; do
    run find_in "$line"
    [ -z "$output" ] || { echo "$line: $output"; false; }
    run redact_line "$line"
    [ "$status" -eq 3 ] || { echo "$line: $output"; false; }
    [ "$output" = "$line" ]
  done
}

@test "redaction after an escape continues along the line and leaves earlier redactions alone" {
  run redact_line 'opus\nopus [redacted]\topus\u001b[1mopus'
  [ "$status" -eq 0 ]
  [ "$output" = '[redacted]\n[redacted] [redacted]\t[redacted]\u001b[1m[redacted]' ]
}

@test "W4: an absolute path needs no boundary before it (/@fs/Users/..., file://localhost/Users/...)" {
  local low
  low="$(printf '%s' "$RUN_DIR" | tr 'A-Z' 'a-z')"
  for pre in '/@fs' 'file://localhost' 'vscode://file'; do
    run find_in "see ${pre}${RUN_DIR}/rubric.md"
    [ "$output" = "t:1: $low" ] || { echo "prefix $pre: $output"; false; }
    run redact_line "see ${pre}${RUN_DIR}/rubric.md"
    [ "$output" = "see ${pre}[redacted]/rubric.md" ] || { echo "prefix $pre: $output"; false; }
  done
}

@test "W4: an ordinary word still needs a boundary before it" {
  run find_in "anopus 5"
  [ "$output" = "" ]
}
