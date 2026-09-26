#!/usr/bin/env bats
# models.sh: role-to-model table. Unknown roles are rejected before any variable lookup.

load test_helper

m() { "$SCRIPTS/models.sh" "$@"; }

@test "a known role prints its default model" {
  unset VETDD_MODEL_JUDGE
  run m judge
  [ "$status" -eq 0 ]
  [ "$output" = "gpt-6-sol" ]
}

@test "an environment override replaces the default for a known role" {
  VETDD_MODEL_REFACTORER=sonnet run m refactorer
  [ "$status" -eq 0 ]
  [ "$output" = "sonnet" ]
}

@test "an unknown role exits 2 even when a matching VETDD_MODEL_ variable is set" {
  VETDD_MODEL_WHATEVER=x run m whatever
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown role"* ]]
}

@test "a role containing an array subscript is rejected without running the subscript" {
  # The role is upper-cased before the lookup, so the payload avoids lower-case letters:
  # the command name is written in octal ($'\164\157\165\143\150' = touch) and the path
  # comes from an upper-case variable.
  export MARKER="$BATS_TEST_TMPDIR/ran"
  run m 'x[$($'"'"'\164\157\165\143\150'"'"' $MARKER)]'
  [ "$status" -eq 2 ]
  [ ! -e "$MARKER" ]
}

@test "a judge override from the author family is rejected (principle 6)" {
  VETDD_MODEL_JUDGE=opus run m judge
  [ "$status" -eq 2 ]
  [[ "$output" == *"different model family"* ]]
  VETDD_MODEL_JUDGE=claude-fable-5-1 run m judge
  [ "$status" -eq 2 ]
}

@test "an override value with shell metacharacters is rejected" {
  VETDD_MODEL_JUDGE='gpt-6-sol; id' run m judge
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid model name"* ]]
}

@test "the judge family check ignores case and matches anywhere in the name" {
  local v
  for v in Opus OPUS Claude-sonnet-5 us.anthropic.claude-opus-5-5 anthropic/claude-fable-5-1; do
    VETDD_MODEL_JUDGE="$v" run m judge
    [ "$status" -eq 2 ] || { echo "accepted: $v"; false; }
  done
}

@test "the judge takes exactly one model: a comma-separated list is rejected" {
  VETDD_MODEL_JUDGE='gpt-6-sol,opus' run m judge
  [ "$status" -eq 2 ]
}

@test "--list fails when any role's override is invalid" {
  VETDD_MODEL_JUDGE=opus run m --list
  [ "$status" -eq 2 ]
}

@test "a value starting with a dash is rejected so it cannot become a CLI option" {
  VETDD_MODEL_JUDGE='--full-auto' run m judge
  [ "$status" -eq 2 ]
  VETDD_MODEL_AUTHOR='-x' run m author
  [ "$status" -eq 2 ]
}

@test "judge-effort accepts only known effort levels" {
  VETDD_MODEL_JUDGE_EFFORT=xhigh run m judge-effort
  [ "$status" -eq 0 ]
  VETDD_MODEL_JUDGE_EFFORT=opus run m judge-effort
  [ "$status" -eq 2 ]
}

@test "arena-runner rejects empty list elements" {
  VETDD_MODEL_ARENA_RUNNER='opus,,sonnet' run m arena-runner
  [ "$status" -eq 2 ]
  VETDD_MODEL_ARENA_RUNNER='opus,sonnet' run m arena-runner
  [ "$status" -eq 0 ]
}

@test "author-side roles must be Claude models, so the judge family stays separate" {
  VETDD_MODEL_AUTHOR=gpt-6-sol run m author
  [ "$status" -eq 2 ]
  VETDD_MODEL_REFACTORER=gpt-6-sol run m refactorer
  [ "$status" -eq 2 ]
  VETDD_MODEL_ARENA_RUNNER='opus,gpt-6-sol' run m arena-runner
  [ "$status" -eq 2 ]
  VETDD_MODEL_AUTHOR=sonnet run m author
  [ "$status" -eq 0 ]
  # The Agent tool takes the aliases opus, sonnet, haiku, fable; a full model id would fail later.
  VETDD_MODEL_AUTHOR=claude-opus-5-5 run m author
  [ "$status" -eq 2 ]
}

@test "an arena-runner value with glob characters is rejected even when files match" {
  cd "$BATS_TEST_TMPDIR" && touch README.md opus
  VETDD_MODEL_ARENA_RUNNER='opus,*' run m arena-runner
  [ "$status" -eq 2 ]
  VETDD_MODEL_ARENA_RUNNER='op?s' run m arena-runner
  [ "$status" -eq 2 ]
}

@test "judge-effort must equal one level, not a run of several" {
  VETDD_MODEL_JUDGE_EFFORT='low medium' run m judge-effort
  [ "$status" -eq 2 ]
}

@test "R26: an override set to the empty string is rejected, not replaced by the default" {
  VETDD_MODEL_JUDGE= run m judge
  [ "$status" -eq 2 ]
  VETDD_MODEL_JUDGE_EFFORT= run m judge-effort
  [ "$status" -eq 2 ]
}
