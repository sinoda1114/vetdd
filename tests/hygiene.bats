#!/usr/bin/env bats
# Repository hygiene checks that encode past review findings (principle 9).

load test_helper

@test "tests never write to the shared /tmp; they use \$BATS_TEST_TMPDIR" {
  # /tmp is world-writable and predictable names can be pre-seeded with symlinks (ai-review R37).
  run grep -nE '(^|[^A-Za-z_])[/]tmp[/]' "$VETDD_ROOT"/tests/*.bats "$VETDD_ROOT"/tests/*.bash
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}
