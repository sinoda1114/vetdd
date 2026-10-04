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

# --- review round 1 ---------------------------------------------------------------------------

@test "a link planted at a guessable temporary name is never written through (C2)" {
  ov s1 --version v1 --change initial --reason r
  printf 'precious\n' > "$BATS_TEST_TMPDIR/target"
  for n in 1 2 3 $$; do ln -s "$BATS_TEST_TMPDIR/target" "$REPO/.vetdd/evidence/s1/meta.json.tmp.$n"; done
  run ov s1 --version v2 --change implementation --reason r2
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/target")" = "precious" ]
  [ "$(mq s1 '.oracle_versions | length')" = "2" ]
  [ -z "$(ls "$REPO/.vetdd/evidence/s1" | grep -E '^meta\.json\.[A-Za-z0-9]{6}$')" ]
  # The name is made by mktemp (O_EXCL), not from the process id.
  grep -q 'mktemp "\$dir/meta.json' "$SCRIPTS/oracle-version.sh"
  run ! grep -q 'tmp\.\$\$' "$SCRIPTS/oracle-version.sh"
}

@test "a link at .vetdd, .vetdd/evidence, or the slice directory is refused and nothing is made outside (C3)" {
  mkdir -p "$BATS_TEST_TMPDIR/out"
  ln -s "$BATS_TEST_TMPDIR/out" .vetdd
  run ov s1 --version v1 --change initial --reason r
  [ "$status" -eq 2 ]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/out")" ]
  rm .vetdd; mkdir .vetdd; ln -s "$BATS_TEST_TMPDIR/out" .vetdd/evidence
  run ov s1 --version v1 --change initial --reason r
  [ "$status" -eq 2 ]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/out")" ]
  rm .vetdd/evidence; mkdir .vetdd/evidence; ln -s "$BATS_TEST_TMPDIR/out" .vetdd/evidence/s1
  run ov s1 --version v1 --change initial --reason r
  [ "$status" -eq 2 ]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/out")" ]
}

@test "a version log holding a non-object entry is refused, never read as having no duplicate (C6)" {
  ov s1 --version v1 --change initial --reason r
  jq '.oracle_versions = ["x"] + .oracle_versions' .vetdd/evidence/s1/meta.json > m && mv m .vetdd/evidence/s1/meta.json
  run ov s1 --version v1 --change implementation --reason again
  [ "$status" -eq 2 ]
  [ "$(mq s1 '.oracle_versions | length')" = "2" ]
}

@test "a failure after the directory was made leaves no empty slice directory behind (C7)" {
  mkdir -p "$BATS_TEST_TMPDIR/nomktemp"
  printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/nomktemp/mktemp"; chmod +x "$BATS_TEST_TMPDIR/nomktemp/mktemp"
  PATH="$BATS_TEST_TMPDIR/nomktemp:$PATH" run ov s1 --version v1 --change initial --reason r
  [ "$status" -eq 2 ]
  [ ! -e .vetdd/evidence/s1 ]
}

# --- review round 2 ---------------------------------------------------------------------------

# GNU stat first: BSD stat has no -c (no output), but GNU stat -f prints file system data.
perm() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

@test "text read from a file is recorded verbatim, quotes and shell syntax included (E1)" {
  printf "x'; echo pwned; echo '\$(touch $BATS_TEST_TMPDIR/ran)\n" > "$BATS_TEST_TMPDIR/reason.txt"
  printf 'what the user said? "yes" `now`\n' > "$BATS_TEST_TMPDIR/q.txt"
  printf "it's fine\n" > "$BATS_TEST_TMPDIR/a.txt"
  ov s1 --version v1 --change initial --reason first
  run ov s1 --version v2 --change meaning --reason-file "$BATS_TEST_TMPDIR/reason.txt" \
    --agreement-via chat --question-file "$BATS_TEST_TMPDIR/q.txt" --answer-file "$BATS_TEST_TMPDIR/a.txt"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s1 '.oracle_versions[1].reason')" = "x'; echo pwned; echo '\$(touch $BATS_TEST_TMPDIR/ran)" ]
  [ "$(mq s1 '.oracle_versions[1].agreement.question')" = 'what the user said? "yes" `now`' ]
  [ "$(mq s1 '.oracle_versions[1].agreement.answer')" = "it's fine" ]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
}

@test "a text file with a control character, an empty file, a link, a directory, or a big file is refused (E1)" {
  printf 'a\tb\n' > "$BATS_TEST_TMPDIR/tab.txt"; : > "$BATS_TEST_TMPDIR/empty.txt"
  printf 'x\n' > "$BATS_TEST_TMPDIR/real.txt"; ln -s real.txt "$BATS_TEST_TMPDIR/link.txt"
  mkdir "$BATS_TEST_TMPDIR/dir.txt"; head -c 5000 /dev/zero | tr '\0' 'a' > "$BATS_TEST_TMPDIR/big.txt"
  printf 'two\nlines\n' > "$BATS_TEST_TMPDIR/two.txt"
  for f in tab empty link dir big two nope; do
    run ov s1 --version v1 --change initial --reason-file "$BATS_TEST_TMPDIR/$f.txt"
    [ "$status" -eq 2 ] || { echo "$f: $output"; false; }
  done
  [ ! -e .vetdd/evidence/s1 ]
}

@test "a text option and its file form together, or twice, is a usage error (E1)" {
  printf 'x\n' > "$BATS_TEST_TMPDIR/r.txt"
  run ov s1 --version v1 --change initial --reason r --reason-file "$BATS_TEST_TMPDIR/r.txt"
  [ "$status" -eq 2 ]
  run ov s1 --version v1 --change initial --reason r --reason again
  [ "$status" -eq 2 ]
}

@test "--change initial is refused once the slice has an entry, and the message says how to recover (E2)" {
  ov s1 --version v1 --change initial --reason first
  run ov s1 --version v2 --change initial --reason second
  [ "$status" -eq 2 ]
  [[ "$output" == *"implementation or meaning"* ]]
  [ "$(mq s1 '.oracle_versions | length')" = "1" ]
}

@test "oracle-version.sh and evidence.sh keep the meta.json permissions the umask gives (E3)" {
  ( umask 077; ov s1 --version v1 --change initial --reason r )
  [ "$(perm .vetdd/evidence/s1/meta.json)" = "600" ]
  ( umask 077; ev s1 before --oracle-version v1 --oracle-file test.sh -- sh test.sh )
  [ "$(perm .vetdd/evidence/s1/meta.json)" = "600" ]
  ( umask 022; ov s1 --version v2 --change implementation --reason r2 )
  [ "$(perm .vetdd/evidence/s1/meta.json)" = "644" ]
}

@test "a text file whose path starts with a dash is read as a file, never as an option of cat (G2)" {
  printf 'from the file\n' > ./-n
  # stdin is closed: a cat that took -n for an option would otherwise wait for input.
  run ov s1 --version v1 --change initial --reason-file -n < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s1 '.oracle_versions[0].reason')" = "from the file" ]
}
