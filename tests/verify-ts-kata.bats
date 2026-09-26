#!/usr/bin/env bats
# The fixture's verify skill scripts: exit 0 observed and met, 1 observed and not met,
# 2 could not observe or usage error. Usage errors must never look like "not met".

load test_helper

V="$VETDD_ROOT/fixtures/ts-kata/.claude/skills/verify-ts-kata/scripts"

@test "E15: --expect without a value is a usage error (exit 2), not 'observed and not met'" {
  run "$V/verify-due.sh" --expect
  [ "$status" -eq 2 ]
  run "$V/verify-usage.sh" --expect
  [ "$status" -eq 2 ]
}

@test "the drive runs the app's own tsx binary, never npx" {
  run grep -nE '^[^#]*npx' "$V/lib.sh"
  [ "$status" -eq 1 ]
}
