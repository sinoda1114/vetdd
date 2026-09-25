#!/usr/bin/env bats
# evidence.sh: records one run per call into .vetdd/evidence/<slice>/meta.json

load test_helper

setup() { make_repo; }

@test "command arguments starting with -- are recorded verbatim, not parsed as options" {
  run ev s1 after -- sh -c 'exit 0' --prefix sub --json
  [ "$status" -eq 0 ]
  [ "$(mq s1 '.runs | length')" = "1" ]
  [ "$(mq s1 '.runs[0].cmd | join(" ")')" = "sh -c exit 0 --prefix sub --json" ]
}

@test "before run that fails is recorded as target_failure with its log" {
  run ev s1 before -- sh test.sh
  [ "$status" -eq 0 ]
  [ "$(mq s1 '.slice_id')" = "s1" ]
  [ "$(mq s1 '.runs | length')" = "1" ]
  [ "$(mq s1 '.runs[0].seq')" = "1" ]
  [ "$(mq s1 '.runs[0].kind')" = "before" ]
  [ "$(mq s1 '.runs[0].exit_code')" = "1" ]
  [ "$(mq s1 '.runs[0].outcome')" = "target_failure" ]
  [ "$(mq s1 '.runs[0].accepted')" = "true" ]
  [ "$(mq s1 '.runs[0].cmd | type')" = "array" ]
  [ "$(mq s1 '.runs[0].cmd | join(" ")')" = "sh test.sh" ]
  log="$REPO/.vetdd/evidence/s1/$(mq s1 '.runs[0].log')"
  [ "$(mq s1 '.runs[0].log')" = "runs/001-before.log" ]
  grep -q "value is 0" "$log"
  [[ "$output" == *"value is 0"* ]]
}

@test "before run that passes is rejected but still recorded" {
  printf '42\n' > value.txt
  run ev s1 before -- sh test.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"before"* ]]
  [[ "$output" == *"target_failure"* ]]
  [ "$(mq s1 '.runs[0].outcome')" = "pass" ]
  [ "$(mq s1 '.runs[0].accepted')" = "false" ]
  [ -f "$REPO/.vetdd/evidence/s1/runs/001-before.log" ]
}

@test "after run that passes is recorded as pass" {
  ev s1 before -- sh test.sh
  printf '42\n' > value.txt
  run ev s1 after -- sh test.sh
  [ "$status" -eq 0 ]
  [ "$(mq s1 '.runs[1].seq')" = "2" ]
  [ "$(mq s1 '.runs[1].kind')" = "after" ]
  [ "$(mq s1 '.runs[1].outcome')" = "pass" ]
  [ "$(mq s1 '.runs[1].accepted')" = "true" ]
  [ -f "$REPO/.vetdd/evidence/s1/runs/002-after.log" ]
}

@test "after run that fails is rejected but still recorded" {
  run ev s1 after -- sh test.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"after"* ]]
  [[ "$output" == *"pass"* ]]
  [ "$(mq s1 '.runs[0].outcome')" = "target_failure" ]
  [ "$(mq s1 '.runs[0].accepted')" = "false" ]
}

@test "integrated run that fails is rejected" {
  run ev s1 integrated -- sh test.sh
  [ "$status" -ne 0 ]
  [ "$(mq s1 '.runs[0].accepted')" = "false" ]
}

@test "calibration accepts both outcomes" {
  run ev s1 calibration -- sh test.sh
  [ "$status" -eq 0 ]
  printf '42\n' > value.txt
  run ev s1 calibration -- sh test.sh
  [ "$status" -eq 0 ]
  [ "$(mq s1 '[.runs[].outcome] | join(",")')" = "target_failure,pass" ]
  [ "$(mq s1 '[.runs[].accepted] | all')" = "true" ]
}

@test "--outcome infrastructure_error overrides the exit code" {
  run ev s1 calibration --outcome infrastructure_error -- sh test.sh
  [ "$status" -eq 0 ]
  [ "$(mq s1 '.runs[0].exit_code')" = "1" ]
  [ "$(mq s1 '.runs[0].outcome')" = "infrastructure_error" ]
}

@test "before with --outcome infrastructure_error is rejected (not red)" {
  run ev s1 before --outcome infrastructure_error -- sh test.sh
  [ "$status" -ne 0 ]
  [ "$(mq s1 '.runs[0].outcome')" = "infrastructure_error" ]
  [ "$(mq s1 '.runs[0].accepted')" = "false" ]
}

@test "command not found defaults to infrastructure_error, not red" {
  run ev s1 before -- vetdd-no-such-command-xyz
  [ "$status" -ne 0 ]
  [ "$(mq s1 '.runs[0].exit_code')" = "127" ]
  [ "$(mq s1 '.runs[0].outcome')" = "infrastructure_error" ]
}

@test "invalid outcome value is a usage error and records nothing" {
  run ev s1 before --outcome maybe -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"outcome"* ]]
  [ ! -e "$REPO/.vetdd/evidence/s1/meta.json" ]
}

@test "invalid kind is a usage error" {
  run ev s1 green -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"kind"* ]]
}

@test "missing command after -- is a usage error" {
  run ev s1 before --
  [ "$status" -eq 2 ]
  run ev s1 before sh test.sh
  [ "$status" -eq 2 ]
}

@test "slice id that could escape the evidence directory is rejected" {
  run ev ../escape before -- sh test.sh
  [ "$status" -eq 2 ]
  [ ! -e "$REPO/.vetdd/escape" ]
}

@test "missing oracle file is a usage error" {
  run ev s1 before --oracle-file nope.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"nope.sh"* ]]
}

@test "outside a git repository is a usage error" {
  mkdir -p "$BATS_TEST_TMPDIR/plain" && cd "$BATS_TEST_TMPDIR/plain"
  run ev s1 before -- false
  [ "$status" -eq 2 ]
  [[ "$output" == *"git"* ]]
}

@test "tree_hash equals the HEAD tree on a clean working tree, head_sha equals HEAD" {
  ev s1 before -- sh test.sh
  [ "$(mq s1 '.runs[0].tree.tree_hash')" = "$(git rev-parse 'HEAD^{tree}')" ]
  [ "$(mq s1 '.runs[0].tree.head_sha')" = "$(git rev-parse HEAD)" ]
}

@test "tree_hash changes when a tracked file changes without a commit" {
  ev s1 calibration -- sh test.sh
  printf '42\n' > value.txt
  ev s1 calibration -- sh test.sh
  [ "$(mq s1 '.runs[0].tree.tree_hash')" != "$(mq s1 '.runs[1].tree.tree_hash')" ]
  [ "$(mq s1 '.runs[0].tree.head_sha')" = "$(mq s1 '.runs[1].tree.head_sha')" ]
}

@test "tree_hash includes untracked files and excludes gitignored files" {
  ev s1 calibration -- sh test.sh
  mkdir -p ignored && printf 'x\n' > ignored/junk.txt
  ev s1 calibration -- sh test.sh
  [ "$(mq s1 '.runs[0].tree.tree_hash')" = "$(mq s1 '.runs[1].tree.tree_hash')" ]
  printf 'new\n' > untracked.txt
  ev s1 calibration -- sh test.sh
  [ "$(mq s1 '.runs[1].tree.tree_hash')" != "$(mq s1 '.runs[2].tree.tree_hash')" ]
}

@test "tree_hash does not change when only .vetdd changes (even when .vetdd is not gitignored)" {
  ev s1 calibration -- sh test.sh
  printf 'noise\n' > .vetdd/extra.txt
  ev s2 calibration -- sh test.sh
  ev s1 calibration -- sh test.sh
  [ "$(mq s1 '.runs[0].tree.tree_hash')" = "$(mq s1 '.runs[1].tree.tree_hash')" ]
  [ "$(mq s1 '.runs[0].tree.tree_hash')" = "$(mq s2 '.runs[0].tree.tree_hash')" ]
}

@test "tree_hash works when .vetdd/ is gitignored" {
  printf '.vetdd/\n' >> .gitignore
  git add .gitignore && git commit -q -m "ignore .vetdd"
  run ev s1 before -- sh test.sh
  [ "$status" -eq 0 ]
  [ "$(mq s1 '.runs[0].tree.tree_hash')" = "$(git rev-parse 'HEAD^{tree}')" ]
}

@test "tree hashing leaves the real index untouched" {
  printf 'staged\n' > staged.txt && git add staged.txt
  printf 'unstaged\n' > unstaged.txt
  ev s1 calibration -- sh test.sh
  [ "$(git diff --cached --name-only)" = "staged.txt" ]
  [[ "$(git status --porcelain)" == *"?? unstaged.txt"* ]]
}

@test "conditions record cwd relative to the repo root" {
  ev s1 calibration -- sh test.sh
  [ "$(mq s1 '.runs[0].conditions.cwd')" = "." ]
  cd sub
  "$SCRIPTS/evidence.sh" s1 calibration -- true
  [ "$(mq s1 '.runs[1].conditions.cwd')" = "sub" ]
  [ -f "$REPO/.vetdd/evidence/s1/runs/002-calibration.log" ]
}

@test "conditions record sorted VETDD_ env var names only" {
  VETDD_ZETA=1 VETDD_ALPHA=secret OTHER_VAR=1 ev s1 calibration -- true
  [ "$(mq s1 '.runs[0].conditions.env_keys | join(",")')" = "VETDD_ALPHA,VETDD_ZETA" ]
  ! grep -q secret "$REPO/.vetdd/evidence/s1/meta.json"
}

@test "conditions record node_version when node exists" {
  command -v node >/dev/null || skip "node not installed"
  ev s1 calibration -- true
  [ "$(mq s1 '.runs[0].conditions.node_version')" = "$(node --version)" ]
}

@test "oracle records seam, version, and sha256 of files relative to the repo root" {
  cd sub
  "$SCRIPTS/evidence.sh" s1 calibration --seam cli --oracle-version v2 \
    --oracle-file ../test.sh --oracle-file keep.txt -- true
  [ "$(mq s1 '.oracle.seam')" = "cli" ]
  [ "$(mq s1 '.oracle.version')" = "v2" ]
  [ "$(mq s1 '[.oracle.files[].path] | join(",")')" = "test.sh,sub/keep.txt" ]
  [ "$(mq s1 '.oracle.files[0].sha256')" = "$(sha256_of "$REPO/test.sh")" ]
  [ "$(mq s1 '.oracle.files[1].sha256')" = "$(sha256_of "$REPO/sub/keep.txt")" ]
  [ "$(mq s1 '.runs[0].oracle.version')" = "v2" ]
}

@test "later runs inherit the oracle and rehash its files at record time" {
  ev s1 before --seam unit --oracle-version v1 --oracle-file test.sh -- sh test.sh
  first="$(mq s1 '.oracle.files[0].sha256')"
  printf '\n# edited\n' >> test.sh
  ev s1 calibration --oracle-version v2 -- true
  [ "$(mq s1 '.oracle.seam')" = "unit" ]
  [ "$(mq s1 '.oracle.version')" = "v2" ]
  [ "$(mq s1 '.oracle.files[0].path')" = "test.sh" ]
  [ "$(mq s1 '.oracle.files[0].sha256')" = "$(sha256_of "$REPO/test.sh")" ]
  [ "$(mq s1 '.oracle.files[0].sha256')" != "$first" ]
  [ "$(mq s1 '.runs[0].oracle.version')" = "v1" ]
}

@test "timestamps are UTC ISO 8601 and ordered" {
  ev s1 calibration -- true
  started="$(mq s1 '.runs[0].started_at')"
  ended="$(mq s1 '.runs[0].ended_at')"
  [[ "$started" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
  [[ "$ended" > "$started" || "$ended" == "$started" ]]
}

@test "meta.json validates against evidence.schema.json" {
  ev s1 calibration --seam unit --oracle-version v1 --oracle-file test.sh -- sh test.sh
  ev s1 before -- sh test.sh
  printf '42\n' > value.txt
  run ev s1 before -- sh test.sh
  ev s1 after -- sh test.sh
  ev s1 integrated --outcome pass -- true
  VETDD_X=1 ev s1 calibration --outcome inconclusive -- true
  run validate_schema "$REPO/.vetdd/evidence/s1/meta.json"
  [ "$status" -eq 0 ]
  [ "$output" = "valid" ]
}

@test "schema rejects an unknown kind and a missing tree" {
  ev s1 calibration --oracle-file test.sh -- true
  tamper s1 '.runs[0].kind = "green"'
  run validate_schema "$REPO/.vetdd/evidence/s1/meta.json"
  [ "$status" -ne 0 ]
  tamper s1 '.runs[0].kind = "after" | del(.runs[0].tree)'
  run validate_schema "$REPO/.vetdd/evidence/s1/meta.json"
  [ "$status" -ne 0 ]
}

@test "missing jq fails with an install hint" {
  mkdir -p "$BATS_TEST_TMPDIR/emptybin"
  PATH="$BATS_TEST_TMPDIR/emptybin" run /bin/bash "$SCRIPTS/evidence.sh" s1 before -- true
  [ "$status" -eq 2 ]
  [[ "$output" == *"jq"* ]]
  [[ "$output" == *"install"* ]]
  [ ! -e "$REPO/.vetdd/evidence/s1" ]
}

@test "works under macOS /bin/bash 3.2" {
  [ -x /bin/bash ] || skip "/bin/bash missing"
  /bin/bash "$SCRIPTS/evidence.sh" s1 before --oracle-file test.sh -- sh test.sh
  printf '42\n' > value.txt
  /bin/bash "$SCRIPTS/evidence.sh" s1 after -- sh test.sh
  run /bin/bash "$SCRIPTS/check-evidence.sh" s1
  [ "$status" -eq 0 ]
  [ "$output" = "s1: OK" ]
}
