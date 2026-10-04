#!/usr/bin/env bats
# oracle-version.sh: records why an oracle's version changed (and, for a change in meaning, the
# re-agreement) into oracle_versions[] of .vetdd/evidence/<slice>/meta.json

load test_helper

setup() { make_repo; }

ov() { "$SCRIPTS/oracle-version.sh" "$@"; }

@test "an initial entry is appended with every field" {
  run ov s1 --version v1 --change initial --reason "total is 42 for the sample cart"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = "1" ]
  [[ "$output" == *"v1"* ]]
  [ "$(mq s1 '.oracle_versions | length')" = "1" ]
  [ "$(mq s1 '.oracle_versions[0].version')" = "v1" ]
  [ "$(mq s1 '.oracle_versions[0].change')" = "initial" ]
  [ "$(mq s1 '.oracle_versions[0].reason')" = "total is 42 for the sample cart" ]
  [ "$(mq s1 '.oracle_versions[0].agreement')" = "null" ]
  [ "$(mq s1 '.oracle_versions[0].after_seq')" = "0" ]
  [[ "$(mq s1 '.oracle_versions[0].recorded_at')" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "a meta.json created here has the same skeleton evidence.sh creates" {
  ov s1 --version v1 --change initial --reason r
  ev s2 calibration -- true
  [ "$(jq -S 'del(.runs, .oracle_versions) | .slice_id = "x"' "$REPO/.vetdd/evidence/s1/meta.json")" = \
    "$(jq -S 'del(.runs, .oracle_versions) | .slice_id = "x"' "$REPO/.vetdd/evidence/s2/meta.json")" ]
  [ "$(mq s1 '.runs')" = "[]" ]
}

@test "evidence.sh keeps the entries when it records runs after them" {
  ov s1 --version v1 --change initial --reason r
  ev s1 before --oracle-version v1 --oracle-file test.sh -- sh test.sh
  [ "$(mq s1 '.runs | length')" = "1" ]
  [ "$(mq s1 '.oracle_versions[0].version')" = "v1" ]
}

@test "after_seq is the highest run seq recorded so far" {
  ev s1 before --oracle-version v1 --oracle-file test.sh -- sh test.sh
  ev s1 calibration -- sh test.sh
  ov s1 --version v2 --change implementation --reason "clearer message"
  [ "$(mq s1 '.oracle_versions[0].after_seq')" = "2" ]
}

@test "a meaning change stores the agreement" {
  run ov s1 --version v2 --change meaning --reason "total now includes tax" \
    --agreement-via AskUserQuestion --question "Include tax?" --answer "Yes, include tax"
  [ "$status" -eq 0 ]
  [ "$(mq s1 '.oracle_versions[0].agreement.via')" = "AskUserQuestion" ]
  [ "$(mq s1 '.oracle_versions[0].agreement.question')" = "Include tax?" ]
  [ "$(mq s1 '.oracle_versions[0].agreement.answer')" = "Yes, include tax" ]
}

@test "an implementation change may carry an agreement too, and a second entry appends" {
  ov s1 --version v1 --change initial --reason r
  run ov s1 --version v2 --change implementation --reason "rename helper" \
    --agreement-via chat --question q --answer a
  [ "$status" -eq 0 ]
  [ "$(mq s1 '.oracle_versions | map(.version) | join(",")')" = "v1,v2" ]
  [ "$(mq s1 '.oracle_versions[1].agreement.via')" = "chat" ]
}

@test "a meaning change without the three agreement items is a usage error and writes nothing" {
  run ov s1 --version v2 --change meaning --reason "tax is in"
  [ "$status" -eq 2 ]
  [ ! -e "$REPO/.vetdd/evidence/s1/meta.json" ]
  run ov s1 --version v2 --change meaning --reason "tax is in" --agreement-via chat --question q
  [ "$status" -eq 2 ]
  run ov s1 --version v2 --change meaning --reason "tax is in" --question q --answer a
  [ "$status" -eq 2 ]
  [ ! -e "$REPO/.vetdd/evidence/s1/meta.json" ]
  ov s1 --version v1 --change initial --reason r
  before="$(cat "$REPO/.vetdd/evidence/s1/meta.json")"
  run ov s1 --version v2 --change meaning --reason "tax is in" --agreement-via chat --answer a
  [ "$status" -eq 2 ]
  [ "$(cat "$REPO/.vetdd/evidence/s1/meta.json")" = "$before" ]
}

@test "a partial agreement is a usage error for any change" {
  run ov s1 --version v1 --change initial --reason r --agreement-via chat
  [ "$status" -eq 2 ]
  run ov s1 --version v1 --change implementation --reason r --question q --answer a
  [ "$status" -eq 2 ]
  [ ! -e "$REPO/.vetdd/evidence/s1/meta.json" ]
}

@test "a duplicate version is a usage error and leaves meta.json as it was" {
  ov s1 --version v1 --change initial --reason r
  before="$(cat "$REPO/.vetdd/evidence/s1/meta.json")"
  run ov s1 --version v1 --change implementation --reason again
  [ "$status" -eq 2 ]
  [ "$(cat "$REPO/.vetdd/evidence/s1/meta.json")" = "$before" ]
}

@test "bad arguments are usage errors and write nothing" {
  run ov; [ "$status" -eq 2 ]
  run ov 'bad slice' --version v1 --change initial --reason r; [ "$status" -eq 2 ]
  run ov s1 --version 'v 1' --change initial --reason r; [ "$status" -eq 2 ]
  run ov s1 --version '../v' --change initial --reason r; [ "$status" -eq 2 ]
  run ov s1 --version v1 --change other --reason r; [ "$status" -eq 2 ]
  run ov s1 --version v1 --change initial; [ "$status" -eq 2 ]
  run ov s1 --change initial --reason r; [ "$status" -eq 2 ]
  run ov s1 --version v1 --reason r; [ "$status" -eq 2 ]
  run ov s1 --version v1 --change initial --reason ""; [ "$status" -eq 2 ]
  run ov s1 --version v1 --change meaning --reason r --agreement-via email --question q --answer a; [ "$status" -eq 2 ]
  run ov s1 --version v1 --change meaning --reason r --agreement-via chat --question "" --answer a; [ "$status" -eq 2 ]
  run ov s1 --version v1 --change meaning --reason r --agreement-via chat --question q --answer ""; [ "$status" -eq 2 ]
  run ov s1 --version v1 --change initial --reason r --bogus x; [ "$status" -eq 2 ]
  run ov s1 s2 --version v1 --change initial --reason r; [ "$status" -eq 2 ]
  run ov s1 --version; [ "$status" -eq 2 ]
  [ ! -e "$REPO/.vetdd/evidence/s1/meta.json" ]
}

@test "control characters in --reason, --question, or --answer are refused" {
  run ov s1 --version v1 --change initial --reason "$(printf 'a\033[2Jb')"; [ "$status" -eq 2 ]
  run ov s1 --version v1 --change initial --reason "$(printf 'a\302\233b')"; [ "$status" -eq 2 ]
  run ov s1 --version v1 --change initial --reason "$(printf 'a\nb')"; [ "$status" -eq 2 ]
  run ov s1 --version v1 --change meaning --reason r --agreement-via chat --question "$(printf 'q\033')" --answer a
  [ "$status" -eq 2 ]
  run ov s1 --version v1 --change meaning --reason r --agreement-via chat --question q --answer "$(printf 'a\033')"
  [ "$status" -eq 2 ]
  [ ! -e "$REPO/.vetdd/evidence/s1/meta.json" ]
}

@test "a Japanese reason is accepted" {
  run ov s1 --version v1 --change initial --reason "合計は税込みで42になる"
  [ "$status" -eq 0 ]
  [ "$(mq s1 '.oracle_versions[0].reason')" = "合計は税込みで42になる" ]
}

@test "a meta.json for another slice or without runs is refused, not overwritten" {
  mkdir -p "$REPO/.vetdd/evidence/s1"
  printf '{"slice_id": "other", "oracle": {"seam": null, "version": null, "files": []}, "runs": []}\n' > "$REPO/.vetdd/evidence/s1/meta.json"
  before="$(cat "$REPO/.vetdd/evidence/s1/meta.json")"
  run ov s1 --version v1 --change initial --reason r
  [ "$status" -eq 2 ]
  printf 'not json\n' > "$REPO/.vetdd/evidence/s1/meta.json"
  run ov s1 --version v1 --change initial --reason r
  [ "$status" -eq 2 ]
  [ "$(cat "$REPO/.vetdd/evidence/s1/meta.json")" = "not json" ]
  [ -n "$before" ]
}

@test "an oracle_versions that is not an array is refused" {
  ov s1 --version v1 --change initial --reason r
  tamper s1 '.oracle_versions = "x"'
  run ov s1 --version v2 --change implementation --reason r
  [ "$status" -eq 2 ]
}

@test "meta.json with entries validates against evidence.schema.json" {
  ov s1 --version v1 --change initial --reason r
  ev s1 before --oracle-version v1 --oracle-file test.sh -- sh test.sh
  ov s1 --version v2 --change meaning --reason "tax is in" --agreement-via AskUserQuestion --question q --answer a
  ov s1 --version v3 --change implementation --reason "rename"
  run validate_schema "$REPO/.vetdd/evidence/s1/meta.json"
  [ "$status" -eq 0 ]
  [ "$output" = "valid" ]
}

@test "meta.json without oracle_versions still validates (old evidence)" {
  ev s1 before --oracle-version v1 --oracle-file test.sh -- sh test.sh
  [ "$(mq s1 'has("oracle_versions")')" = "false" ]
  run validate_schema "$REPO/.vetdd/evidence/s1/meta.json"
  [ "$status" -eq 0 ]
}

@test "the schema rejects a tampered oracle_versions entry" {
  ov s1 --version v1 --change initial --reason r
  tamper s1 '.oracle_versions[0].change = "weakened"'
  run validate_schema "$REPO/.vetdd/evidence/s1/meta.json"
  [ "$status" -ne 0 ]
  tamper s1 '.oracle_versions[0].change = "meaning" | .oracle_versions[0].agreement = null'
  run validate_schema "$REPO/.vetdd/evidence/s1/meta.json"
  [ "$status" -ne 0 ]
  tamper s1 '.oracle_versions[0].change = "initial" | .oracle_versions[0].extra = 1'
  run validate_schema "$REPO/.vetdd/evidence/s1/meta.json"
  [ "$status" -ne 0 ]
}
