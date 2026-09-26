#!/usr/bin/env bats
# verdict.schema.json is sent to the judge as `codex exec --output-schema`, which OpenAI enforces in
# strict structured-output mode. Strict mode rejects the whole request (HTTP 400) when the schema uses
# a keyword outside its subset, an object with open or schema-valued additionalProperties, or an
# object whose properties are not all required. These tests keep the schema inside that subset.

load test_helper
load helpers/eval_fixtures

# Every schema node (the root, each property, each items, each anyOf branch, each $defs entry).
NODES='def nodes: ., ((.properties // {}) | .[] | nodes), ((.items // empty) | nodes),
                   ((.anyOf // []) | .[] | nodes), ((."$defs" // {}) | .[] | nodes); nodes'

@test "the schema uses only keywords allowed in strict structured output" {
  local allowed='["$schema","$id","title","description","type","properties","required",
                  "additionalProperties","items","enum","const","pattern","format","minimum","maximum",
                  "minItems","maxItems","anyOf","$defs","$ref"]'
  run jq -r --argjson ok "$allowed" "$NODES | keys[] | select(IN(\$ok[]) | not)" "$VERDICT_SCHEMA"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "disallowed keywords: $output"; false; }
}

@test "every object in the schema is closed and requires every property it declares" {
  run jq -r "$NODES | select(.type == \"object\")
             | select(.additionalProperties != false
                      or ((.required // []) | sort) != ((.properties // {}) | keys | sort))
             | (.title // .description // \"(untitled object)\")" "$VERDICT_SCHEMA"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "open or partially required objects: $output"; false; }
}

@test "the fixture verdict validates against the schema" {
  local V="$BATS_TEST_TMPDIR/judge.json"
  write_verdict "$V"
  node "$SCRIPTS/lib/validate-json.mjs" "$VERDICT_SCHEMA" "$V"
}
