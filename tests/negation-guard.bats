#!/usr/bin/env bats
# #26: a negated command mid-test (`! cmd`) never fails a bats test: bash's set -e ignores a command
# inverted with !, so only the last line of a test would count. Write `! cmd || false` (or `run ! cmd`).

load test_helper

@test "no test file has a bare negated command (write ! cmd || false)" {
  run bash -c "grep -nE '^[[:space:]]+! ' \"\$1\"/*.bats | grep -v '|| false\$'" _ "$BATS_TEST_DIRNAME"
  [ -z "$output" ] || { echo "$output"; false; }
}
