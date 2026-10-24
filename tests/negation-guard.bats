#!/usr/bin/env bats
# #26: a negated command mid-test (`! cmd`) never fails a bats test: bash's set -e ignores a command
# inverted with !, so only the last line of a test would count. Write `! cmd || false` (or `run ! cmd`).
# #32: the scanner (helpers/bare-negations.pl) finds a negation wherever a command can start inside
# @test: at the start of a line, after ; && || & | ( then do else, inside { }, and in a case branch.

load test_helper

SCAN="$BATS_TEST_DIRNAME/helpers/bare-negations.pl"
FIX="$BATS_TEST_DIRNAME/fixtures/negation-guard"

@test "no test file has a bare negated command (write ! cmd || false)" {
  run perl "$SCAN" "$BATS_TEST_DIRNAME"/*.bats
  [ "$status" -eq 0 ] || { echo "status $status: $output"; false; }
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "the scanner reports every bare negation in the fixture, and only those lines" {
  local want got
  want="$(grep -nE '![[:space:]]+caught' "$FIX/bare.fixture" | cut -d: -f1 | tr '\n' ' ')"
  run perl "$SCAN" "$FIX/bare.fixture"
  [ "$status" -eq 1 ] || { echo "status $status: $output"; false; }
  got="$(printf '%s\n' "$output" | cut -d: -f2 | tr '\n' ' ')"
  [ "$got" = "$want" ] || { echo "want lines: $want"; echo "got: $output"; false; }
  # Each report names the file and the line as written.
  [[ "${lines[0]}" == "$FIX/bare.fixture:6:  ! caught" ]] || { echo "${lines[0]}"; false; }
}

@test "the scanner reports nothing for ! cmd || false, run !, [ ! ], [[ ! ]], strings, comments, heredocs and conditions" {
  run perl "$SCAN" "$FIX/clean.fixture"
  [ "$status" -eq 0 ] || { echo "status $status: $output"; false; }
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "the scanner fails loudly on a file it cannot follow instead of passing it" {
  local f="$BATS_TEST_TMPDIR/broken.bats"
  printf '@test "x" {\n  echo "open\n  ! cmd\n}\n' > "$f"
  run perl "$SCAN" "$f"
  [ "$status" -eq 2 ] || { echo "status $status: $output"; false; }
  [[ "$output" == *"$f"*unterminated* ]] || { echo "$output"; false; }
  printf '@test "x" {\n  cat <<EOF\n! cmd\n}\n' > "$f"
  run perl "$SCAN" "$f"
  [ "$status" -eq 2 ] || { echo "status $status: $output"; false; }
  [[ "$output" == *"$f"*heredoc* ]] || { echo "$output"; false; }
  printf '@test "x" {\n  cat <<EOF' > "$f"
  run perl "$SCAN" "$f"
  [ "$status" -eq 2 ] || { echo "status $status: $output"; false; }
  [[ "$output" == *"$f:2"*heredoc* ]] || { echo "$output"; false; }
  printf '@test "x" {\n  if true; then\n    :\n}\n' > "$f"
  run perl "$SCAN" "$f"
  [ "$status" -eq 2 ] || { echo "status $status: $output"; false; }
  [[ "$output" == *"$f:4"* ]] || { echo "$output"; false; }
}

@test "the scanner reads every file it is given and reports the bare negations of each" {
  local a="$BATS_TEST_TMPDIR/a.bats" b="$BATS_TEST_TMPDIR/b.bats"
  printf '@test "a" {\n  ! one\n}\n' > "$a"
  printf '@test "b" {\n  true\n  ! two\n}\n' > "$b"
  run perl "$SCAN" "$a" "$b"
  [ "$status" -eq 1 ] || { echo "status $status: $output"; false; }
  [ "$output" = "$a:2:  ! one
$b:3:  ! two" ] || { echo "$output"; false; }
}
