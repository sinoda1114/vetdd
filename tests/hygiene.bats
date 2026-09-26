#!/usr/bin/env bats
# Repository hygiene checks that encode past review findings (principle 9).

load test_helper

@test "tests never write to the shared /tmp; they use \$BATS_TEST_TMPDIR" {
  # /tmp is world-writable and predictable names can be pre-seeded with symlinks (ai-review R37).
  run grep -nE '(^|[^A-Za-z_])[/]tmp[/]' "$VETDD_ROOT"/tests/*.bats "$VETDD_ROOT"/tests/*.bash
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "the eval scripts create temporary files only inside a private mktemp -d directory" {
  # A sibling like "$tmp.prompt" is a predictable name beside a random one (review E16).
  local f
  for f in judge check-blind sanitize-candidates; do
    run grep -c 'mktemp -d ' "$SCRIPTS/$f.sh"
    [ "$output" -ge 1 ] || { echo "$f.sh: no mktemp -d"; false; }
    run sh -c 'grep -n "mktemp" "$1" | grep -v "mktemp -d "' _ "$SCRIPTS/$f.sh"
    [ "$status" -eq 1 ] || { echo "$f.sh: $output"; false; }
  done
}
