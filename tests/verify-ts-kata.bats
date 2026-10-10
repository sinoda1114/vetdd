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

APP="$VETDD_ROOT/fixtures/ts-kata"
SKILL="$APP/.claude/skills/verify-ts-kata"

# Commands the scripts use besides node. A PATH made of these alone isolates node.
BASE_CMDS="bash git date mkdir rmdir dirname cat grep head rm"

setup() {
  export VETDD_ARTIFACTS="$BATS_TEST_TMPDIR/artifacts"
}

# Print a bin directory holding symlinks to BASE_CMDS, plus node when $1 is "with-node".
make_bin() {
  local bin="$BATS_TEST_TMPDIR/bin-${1:-no-node}" c
  mkdir -p "$bin"
  for c in $BASE_CMDS; do ln -sf "$(command -v "$c")" "$bin/$c"; done
  [ "${1:-}" = with-node ] && ln -sf "$(command -v node)" "$bin/node"
  printf '%s\n' "$bin"
}

# Print a bin directory whose node exists but always fails (a broken runtime).
make_bin_broken_node() {
  local bin
  bin="$(make_bin)"
  printf '#!/bin/sh\necho "node: broken on purpose" >&2\nexit 1\n' > "$bin/node"
  chmod +x "$bin/node"
  printf '%s\n' "$bin"
}

needs_tsx() {
  command -v node >/dev/null || skip "node not installed"
  [ -x "$APP/node_modules/.bin/tsx" ] || skip "fixture dependencies not installed (npm ci in fixtures/ts-kata)"
}

# Copy the fixture outside git (node_modules linked) so a test can break its cli.
# Sets K (app root of the copy) and KV (its scripts dir).
copy_fixture() {
  K="$BATS_TEST_TMPDIR/kata"
  mkdir -p "$K"
  ( cd "$APP" && tar cf - --exclude ./node_modules --exclude ./.vetdd . ) | ( cd "$K" && tar xf - )
  ln -s "$APP/node_modules" "$K/node_modules"
  KV="$K/.claude/skills/verify-ts-kata/scripts"
}

@test "control: the minimal PATH with node drives both features (exit 0)" {
  needs_tsx
  bin="$(make_bin with-node)"
  run /usr/bin/env PATH="$bin" "$V/verify-due.sh"
  [ "$status" -eq 0 ]
  run /usr/bin/env PATH="$bin" "$V/verify-usage.sh"
  [ "$status" -eq 0 ]
}

@test "A1: node not on PATH is 'could not observe' (exit 2) and prints no artifacts line" {
  bin="$(make_bin)"
  run /usr/bin/env PATH="$bin" "$V/verify-due.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"could not observe: node"* ]]
  [[ "$output" != *"artifacts:"* ]]
  run /usr/bin/env PATH="$bin" "$V/verify-usage.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"could not observe: node"* ]]
  [[ "$output" != *"artifacts:"* ]]
}

@test "A1: tsx that cannot start (broken node) fails the probe: exit 2, no artifacts line" {
  needs_tsx
  bin="$(make_bin_broken_node)"
  run /usr/bin/env PATH="$bin" "$V/verify-due.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"could not observe: tsx probe failed"* ]]
  [[ "$output" != *"artifacts:"* ]]
  run /usr/bin/env PATH="$bin" "$V/verify-usage.sh"
  [ "$status" -eq 2 ]
  [[ "$output" != *"artifacts:"* ]]
}

@test "A4: doctor exits 1 and says why when node is not on PATH" {
  bin="$(make_bin)"
  run /usr/bin/env PATH="$bin" "$V/doctor.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"node is not on PATH"* ]]
}

@test "A4: doctor runs the tsx probe: a broken node is exit 1, a working one reports the probe" {
  needs_tsx
  run /usr/bin/env PATH="$(make_bin_broken_node)" "$V/doctor.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tsx probe failed"* ]]
  run /usr/bin/env PATH="$(make_bin with-node)" "$V/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tsx probe: ok"* ]]
}

@test "H2: default due drive checks both lines and the exit code" {
  needs_tsx
  run "$V/verify-due.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"actual line 1:   closing: 2026-01-31"* ]]
  [[ "$output" == *"actual line 2:   due: 2026-03-02"* ]]
  [[ "$output" == *"actual exit:     0"* ]]
}

@test "H2: --expect-due with a wrong value is observed and not met (exit 1)" {
  needs_tsx
  run "$V/verify-due.sh" --expect-due "due: 2026-03-03"
  [ "$status" -eq 1 ]
  run "$V/verify-due.sh" --expect-due
  [ "$status" -eq 2 ]
}

@test "R6: could not observe creates nothing under the artifacts root, not even the feature directory" {
  bin="$(make_bin)"
  run /usr/bin/env PATH="$bin" VETDD_ARTIFACTS="$VETDD_ARTIFACTS" "$V/verify-due.sh"
  [ "$status" -eq 2 ]
  run /usr/bin/env PATH="$bin" VETDD_ARTIFACTS="$VETDD_ARTIFACTS" "$V/verify-usage.sh"
  [ "$status" -eq 2 ]
  [ ! -e "$VETDD_ARTIFACTS" ]
}

@test "S4: an exported CDPATH does not stop the scripts from finding lib.sh" {
  needs_tsx
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere/.claude/skills/verify-ts-kata/scripts"
  cd "$APP"
  run env CDPATH=".:$BATS_TEST_TMPDIR/elsewhere" .claude/skills/verify-ts-kata/scripts/verify-usage.sh
  [ "$status" -eq 0 ]
  run env CDPATH=".:$BATS_TEST_TMPDIR/elsewhere" .claude/skills/verify-ts-kata/scripts/doctor.sh
  [ "$status" -eq 0 ]
}

@test "Y1: a relative VETDD_ARTIFACTS is taken from the caller's directory, not the app root" {
  needs_tsx
  mkdir -p "$BATS_TEST_TMPDIR/caller"
  cd "$BATS_TEST_TMPDIR/caller"
  run env VETDD_ARTIFACTS=rel-artifacts "$V/verify-due.sh"
  [ "$status" -eq 0 ]
  [ -n "$(ls "$BATS_TEST_TMPDIR/caller/rel-artifacts/due")" ]
  [ ! -e "$APP/rel-artifacts" ]
}

@test "S5: drive returns 2 (could not observe) when it cannot write its artifacts" {
  [ "$(id -u)" -ne 0 ] || skip "root writes to read-only directories"
  needs_tsx
  local ro="$BATS_TEST_TMPDIR/readonly"
  mkdir -p "$ro"
  chmod 555 "$ro"
  run bash -c '. "$1/lib.sh" && drive "$2" due 2026-01-10' _ "$V" "$ro"
  [ -e "$ro" ] && chmod 755 "$ro"
  [ "$status" -eq 2 ]
  [[ "$output" == *"could not observe: cannot write"* ]]
  [[ "$output" != *"artifacts:"* ]]
  # The directory drive was given is removed, as SKILL.md promises.
  [ ! -e "$ro" ]
}

@test "W3: an artifacts root that cannot be created is could-not-observe (exit 2) with that message" {
  [ "$(id -u)" -ne 0 ] || skip "root writes to read-only directories"
  needs_tsx
  local locked="$BATS_TEST_TMPDIR/locked"
  mkdir -p "$locked"
  chmod 555 "$locked"
  run env VETDD_ARTIFACTS="$locked/artifacts" "$V/verify-due.sh"
  chmod 755 "$locked"
  [ "$status" -eq 2 ]
  [[ "$output" == *"could not observe: cannot create the artifact directory"* ]]
  [ ! -e "$locked/artifacts" ]
}

@test "artifact_dir never reuses an existing directory (someone may have planted links in it)" {
  run bash -c 'date() { printf "20260101T000000Z\n"; }; . "$1/lib.sh" && artifact_dir due && artifact_dir due' _ "$V"
  [ "$status" -ne 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^/')" -eq 1 ]
}

@test "H2: a cli that prints the closing date as the due date and exits 1 is caught (exit 1)" {
  needs_tsx
  copy_fixture
  sed -i.bak -e 's/due: \${schedule.dueDate}/due: ${schedule.closingDate}/' -e 's/    return 0;/    return 1;/' "$K/src/cli.ts"
  run cmp -s "$K/src/cli.ts" "$K/src/cli.ts.bak"
  [ "$status" -ne 0 ]
  run "$KV/verify-due.sh"
  [ "$status" -eq 1 ]
}

@test "H2: a cli that prints a third stdout line is caught (exit 1)" {
  needs_tsx
  copy_fixture
  sed -i.bak 's/\\ndue: \${schedule.dueDate}\\n/&extra\\n/' "$K/src/cli.ts"
  run cmp -s "$K/src/cli.ts" "$K/src/cli.ts.bak"
  [ "$status" -ne 0 ]
  run "$KV/verify-due.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"actual lines:    3"* ]]
}

@test "usage line match is case-sensitive: 'Usage:' is not the agreed 'usage' line (exit 1)" {
  needs_tsx
  copy_fixture
  sed -i.bak 's/"usage: tsx/"Usage: tsx/' "$K/src/cli.ts"
  run cmp -s "$K/src/cli.ts" "$K/src/cli.ts.bak"
  [ "$status" -ne 0 ]
  run "$KV/verify-usage.sh"
  [ "$status" -eq 1 ]
}

@test "scripts run when invoked by bare name from the scripts directory" {
  needs_tsx
  run bash -c 'cd "$1" && bash verify-usage.sh' _ "$V"
  [ "$status" -eq 0 ]
  run bash -c 'cd "$1" && bash verify-due.sh' _ "$V"
  [ "$status" -eq 0 ]
}

@test "outside git, artifacts default to <app root>/.vetdd/artifacts" {
  needs_tsx
  copy_fixture
  unset VETDD_ARTIFACTS
  run "$KV/verify-due.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"artifacts: $K/.vetdd/artifacts/due/"* ]]
}

@test "cleanup exits 1 and says why when the stale pid file cannot be removed" {
  [ "$(id -u)" -ne 0 ] || skip "root removes files in read-only directories"
  copy_fixture
  mkdir -p "$K/.vetdd/run"
  printf '123\n' > "$K/.vetdd/run/ts-kata.pid"
  chmod 555 "$K/.vetdd/run"
  run "$KV/cleanup.sh"
  chmod 755 "$K/.vetdd/run"
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not remove"* ]]
  run "$KV/cleanup.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$K/.vetdd/run/ts-kata.pid" ]
}

@test "docs never tell the driver to run npx tsx" {
  run grep -rn 'npx tsx' "$SKILL/SKILL.md" "$SKILL/features"
  [ "$status" -eq 1 ]
}

@test "SKILL.md states what exit 2 means as implemented (node, tsx, probe)" {
  grep -q 'could not observe' "$SKILL/SKILL.md"
  grep -q 'probe' "$SKILL/SKILL.md"
  ! grep -q '(node or tsx missing)' "$SKILL/SKILL.md" || false
}
