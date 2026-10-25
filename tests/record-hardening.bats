#!/usr/bin/env bats
# Record hardening (#9, #12, #46): the meta.json skeleton every script writes (with oracle_versions, so
# rule 8d asks every new slice), one writer of a slice's meta.json at a time (a lock in the git dir),
# a forced outcome recorded on its run (outcome_forced, infra_exits), the stubs an undefined-imports
# audit ran on (audit.files, only from calibrate.sh stub), and text files read only from .vetdd/notes/.
# A negated command mid-test is written `! cmd || false`: bats does not fail a test on a bare `! cmd`.

bats_require_minimum_version 1.5.0

load test_helper

setup() { make_repo; }

ov() { "$SCRIPTS/oracle-version.sh" "$@"; }
an() { "$SCRIPTS/audit-note.sh" "$@"; }
cal() { "$SCRIPTS/calibrate.sh" "$@"; }
lock_of() { printf '%s/vetdd-lock/%s' "$(git rev-parse --absolute-git-dir)" "$1"; }
# sum_of_text <printf format>: the sha256 of the text the format prints.
sum_of_text() { printf "$1" > "$BATS_TEST_TMPDIR/text.sum"; sha256_of "$BATS_TEST_TMPDIR/text.sum"; }

# --- the skeleton (#9) ----------------------------------------------------------------------------

@test "every script that creates a slice's meta.json writes one skeleton, with an empty oracle_versions" {
  ev s1 calibration -- true
  ov s2 --version v1 --change initial --reason r
  an s3 --kind undefined-imports --not-applicable --reason-file "$(note_text r.txt 'no import to stub')"
  local s
  for s in s1 s2 s3; do
    [ "$(mq "$s" 'has("oracle_versions")')" = true ] || { echo "$s: $(meta "$s")"; false; }
  done
  [ "$(mq s1 '.oracle_versions | tojson')" = '[]' ]
  [ "$(mq s3 '.oracle_versions | tojson')" = '[]' ]
  local want; want="$(jq -S 'del(.runs, .audits) | .slice_id = "x" | .oracle_versions = []' "$REPO/.vetdd/evidence/s1/meta.json")"
  for s in s2 s3; do
    [ "$(jq -S 'del(.runs, .audits) | .slice_id = "x" | .oracle_versions = []' "$REPO/.vetdd/evidence/$s/meta.json")" = "$want" ]
  done
}

@test "rule 8d asks a new slice for the entry of a bumped version" {
  record_good_slice s1
  printf '# stronger\n' >> test.sh
  printf '0\n' > value.txt
  ev s1 calibration --oracle-version v2 --oracle-file test.sh -- sh test.sh >/dev/null 2>&1
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh >/dev/null 2>&1
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (8: oracle version v2 has no recorded reason"* ]]
  # Evidence recorded before the log (no key) is still exempt.
  tamper s1 'del(.oracle_versions)'
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# --- one writer per slice (#9, #12) ---------------------------------------------------------------

@test "evidence.sh, oracle-version.sh, and audit-note.sh refuse a slice another live process is recording, writing nothing" {
  local lock; lock="$(lock_of s1)"
  mkdir -p "${lock%/*}" && ln -s "pid:$$" "$lock"
  run ev s1 calibration -- touch ran
  [ "$status" -eq 2 ]
  [[ "$output" == *"pid $$"* ]]
  [[ "$output" == *"$lock"* ]]
  [ ! -e ran ]
  [ ! -e .vetdd/evidence/s1/meta.json ]
  run ov s1 --version v1 --change initial --reason r
  [ "$status" -eq 2 ]
  [[ "$output" == *"$lock"* ]]
  run an s1 --kind undefined-imports --not-applicable --reason-file "$(note_text r.txt r)"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$lock"* ]]
  [ ! -e .vetdd/evidence/s1/meta.json ]
  # The lock was another's: it is left as it was.
  [ "$(readlink "$lock")" = "pid:$$" ]
  # Another slice is not held up.
  run ev s2 calibration -- true
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a lock its killed writer left is taken over, and every writer removes its lock when it ends" {
  local lock dead; lock="$(lock_of s1)"
  sh -c 'exit 0' & dead=$!; wait "$dead" || true
  mkdir -p "${lock%/*}" && ln -s "pid:$dead" "$lock"
  run ev s1 calibration -- true
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$lock" ]
  [ ! -L "$lock" ]
  # A red, a refusal after the lock (a malformed inherited path), oracle-version.sh, and audit-note.sh.
  run ev s1 before -- sh -c 'exit 1'
  [ ! -L "$lock" ]
  tamper s1 '.oracle.files = [{"path": "a\tb", "sha256": null}]'
  run ev s1 calibration -- true
  [ "$status" -eq 2 ]
  [ ! -L "$lock" ]
  run ov s2 --version v1 --change initial --reason r
  [ "$status" -eq 0 ]
  [ ! -L "$(lock_of s2)" ]
  run an s2 --kind undefined-imports --not-applicable --reason-file "$(note_text r.txt r)"
  [ "$status" -eq 0 ]
  [ ! -L "$(lock_of s2)" ]
  # Nothing of the lock is under .vetdd/: worktree.sh never carries it, the judge never gets it.
  [ -z "$(find .vetdd -name 'vetdd-lock*' -o -name '*.lock' | head -1)" ]
}

@test "review r1: a directory at the lock's name is never taken for a held lock, nor written into" {
  local lock; lock="$(lock_of s1)"
  mkdir -p "$lock"
  run ev s1 calibration -- touch ran
  [ "$status" -eq 2 ]
  [[ "$output" == *"$lock"* ]]
  [ ! -e ran ]
  [ -z "$(ls -A "$lock")" ]
  run ov s1 --version v1 --change initial --reason r
  [ "$status" -eq 2 ]
  [ -z "$(ls -A "$lock")" ]
}

@test "review r1: a slice named <slice>.takeover is not the takeover guard of <slice>" {
  local lock dead; lock="$(lock_of s1)"
  sh -c 'exit 0' & dead=$!; wait "$dead" || true
  mkdir -p "${lock%/*}"
  ln -s "pid:$dead" "$lock"
  ln -s "pid:$$" "$(lock_of s1.takeover)"
  run ev s1 calibration -- true
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -L "$lock" ]
  [ "$(readlink "$(lock_of s1.takeover)")" = "pid:$$" ]
}

@test "review r2: a lock whose name is a link to a directory is refused, and nothing is written into the directory" {
  local lock; lock="$(lock_of s1)"
  mkdir -p "${lock%/*}/pid:$$"
  ln -s "pid:$$" "$lock"
  run ev s1 calibration -- touch ran
  [ "$status" -eq 2 ]
  [ ! -e ran ]
  [ -z "$(ls -A "${lock%/*}/pid:$$")" ]
}

@test "review r2: a lock names its holder's start time: a live pid that started at another time is a reused pid, so the lock is taken over" {
  local lock; lock="$(lock_of s1)"
  mkdir -p "${lock%/*}"
  ln -s "pid:$$:-:Mon_Jan__1_00:00:00_2001" "$lock"
  run ev s1 calibration -- true
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -L "$lock" ]
  # With this process's own start time it is held.
  ln -s "pid:$$:-:$(. "$SCRIPTS/lib/meta.sh"; vetdd_proc_start "$$")" "$lock"
  run ev s1 calibration -- true
  [ "$status" -eq 2 ]
  [[ "$output" == *"pid $$"* ]]
}

@test "review r3: a live holder's lock is held whatever time zone the next writer runs in" {
  local lock; lock="$(lock_of s1)"
  mkdir -p "${lock%/*}"
  ln -s "pid:$$:-:$(TZ=Asia/Tokyo bash -c '. "$1"; vetdd_proc_start "$2"' _ "$SCRIPTS/lib/meta.sh" "$$")" "$lock"
  TZ=UTC run ev s1 calibration -- touch ran
  [ "$status" -eq 2 ]
  [[ "$output" == *"pid $$"* ]]
  [ ! -e ran ]
}

@test "review r2: a lock made in another pid namespace is never taken over, whatever kill says" {
  [ -e /proc/self/ns/pid ] || skip "no pid namespaces here"
  local lock dead; lock="$(lock_of s1)"
  sh -c 'exit 0' & dead=$!; wait "$dead" || true
  mkdir -p "${lock%/*}"
  ln -s "pid:$dead:pid_[1]:x" "$lock"
  run ev s1 calibration -- touch ran
  [ "$status" -eq 2 ]
  [[ "$output" == *"namespace"* ]]
  [ ! -e ran ]
}

@test "an oracle-version.sh entry cannot slip in while evidence.sh runs the slice's command" {
  ev s1 calibration --oracle-version v1 --oracle-file test.sh -- sh -c 'touch started; i=0; while [ ! -e go ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done; exit 1' >/dev/null 2>&1 &
  local bg=$! i=0
  while [ ! -e started ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
  [ -e started ]
  run ov s1 --version v2 --change implementation --reason r
  touch go
  wait "$bg" || true
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [ "$(mq s1 '.oracle_versions | length')" = 0 ]
  [ "$(mq s1 '.runs | length')" = 1 ]
  [ ! -L "$(lock_of s1)" ]
}

# --- a forced outcome (#3 leftover, #9) -----------------------------------------------------------

@test "a run whose outcome --outcome forced records outcome_forced and the declared infra exits; any other run neither" {
  run ev s1 before --infra-exit 3 --infra-exit 2 --outcome target_failure -- sh -c 'exit 2'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s1 '.runs[0].outcome')" = target_failure ]
  [ "$(mq s1 '.runs[0].outcome_forced')" = true ]
  [ "$(mq s1 '.runs[0].infra_exits | tojson')" = '[2,3]' ]
  # Forced on exit 0, with no --infra-exit: an empty list.
  ev s2 before --outcome target_failure -- true
  [ "$(mq s2 '.runs[0].outcome_forced')" = true ]
  [ "$(mq s2 '.runs[0].infra_exits | tojson')" = '[]' ]
  # --outcome that says what the exit code says forces nothing; nor does a plain run.
  ev s3 before --outcome target_failure -- sh -c 'exit 1'
  ev s3 before --infra-exit 2 -- sh -c 'exit 1'
  ev s3 calibration --infra-exit 2 -- sh -c 'exit 2'
  [ "$(mq s3 '[.runs[] | has("outcome_forced") or has("infra_exits")] | any')" = false ]
  run validate_schema "$REPO/.vetdd/evidence/s1/meta.json"
  [ "$status" -eq 0 ]
  [ "$output" = valid ]
  local f
  for f in '.runs[0].outcome_forced = false' '.runs[0].outcome_forced = "yes"' 'del(.runs[0].infra_exits)' \
           'del(.runs[0].outcome_forced)' '.runs[0].infra_exits = [0]' '.runs[0].infra_exits = ["2"]'; do
    jq "$f" "$REPO/.vetdd/evidence/s1/meta.json" > "$BATS_TEST_TMPDIR/bad.json"
    run validate_schema "$BATS_TEST_TMPDIR/bad.json"
    [ "$status" -ne 0 ] || { echo "accepted: $f"; false; }
  done
}

@test "rule 8 does not count a red --outcome forced over an exit code declared with --infra-exit" {
  printf '0\n' > value.txt
  ev s1 before --oracle-version v1 --oracle-file test.sh --infra-exit 2 --outcome target_failure -- sh -c 'exit 2'
  printf '42\n' > value.txt
  ev s1 after -- sh test.sh
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (8: the only red runs with the oracle of the final green run 2 (version v1) were forced with --outcome"* ]]
}

@test "rule 3 reads outcome_forced: a green whose pass was forced fails, whatever its exit code" {
  record_good_slice s1
  tamper s1 '.runs[-1] += {outcome_forced: true, infra_exits: []}'
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (3: after run 2 ended pass only because --outcome forced it"* ]]
}

# --- the stubs an undefined-imports audit ran on (#12) --------------------------------------------

@test "calibrate.sh stub records each stubbed file with the sha256 of its stub on the audit run" {
  printf 'export const f = 1;\n' > lib.ts
  printf 'module.exports = {};\n// real\n' > old.cjs
  git add -A && git commit -q -m product
  run cal stub s1 --file lib.ts --file old.cjs --oracle-file test.sh -- sh -c 'exit 1'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s1 '.runs[-1].audit.kind')" = undefined-imports ]
  [ "$(mq s1 '.runs[-1].audit.files | map(.path) | tojson')" = '["lib.ts","old.cjs"]' ]
  [ "$(mq s1 '.runs[-1].audit.files[0].sha256')" = "$(sum_of_text 'export {};\n')" ]
  [ "$(mq s1 '.runs[-1].audit.files[1].sha256')" = "$(sum_of_text 'module.exports = {};\n')" ]
  run validate_schema "$REPO/.vetdd/evidence/s1/meta.json"
  [ "$status" -eq 0 ]
  [ "$output" = valid ]
  local f
  for f in '.runs[-1].audit.files = []' '.runs[-1].audit.files = [{"path": "lib.ts"}]' '.runs[-1].audit.files[0].sha256 = "x"' \
           '.runs[-1].audit.files[0].extra = 1' '.runs[-1].audit.files = "lib.ts"'; do
    jq "$f" "$REPO/.vetdd/evidence/s1/meta.json" > "$BATS_TEST_TMPDIR/bad.json"
    run validate_schema "$BATS_TEST_TMPDIR/bad.json"
    [ "$status" -ne 0 ] || { echo "accepted: $f"; false; }
  done
}

@test "evidence.sh takes --audit undefined-imports only from a running calibrate.sh stub of the slice, refused before the command runs" {
  run ev s1 calibration --audit undefined-imports -- touch ran
  [ "$status" -eq 2 ]
  [[ "$output" == *"calibrate.sh stub"* ]]
  local st; st="$(git rev-parse --absolute-git-dir)/vetdd-calib/s1"
  mkdir -p "$st" && printf 'value.txt\n' > "$st/files"
  # Another mode, or the stub mode with a pid that is not the process running evidence.sh.
  echo plant > "$st/mode" && echo 1 > "$st/pid"
  run ev s1 calibration --audit undefined-imports -- touch ran;    [ "$status" -eq 2 ]
  echo stub > "$st/mode"
  run ev s1 calibration --audit undefined-imports -- touch ran;    [ "$status" -eq 2 ]
  run ev s2 calibration --audit undefined-imports -- touch ran;    [ "$status" -eq 2 ]
  [ ! -e ran ]
  [ ! -e .vetdd/evidence/s1/meta.json ]
  [ ! -e .vetdd/evidence/s2/meta.json ]
  rm -rf "$st"
  run stub_ev s1 -- true
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s1 '.runs[-1].audit.files | tojson')" = "[{\"path\":\"ignored/stub.mjs\",\"sha256\":\"$(sum_of_text 'export {};\n')\"}]" ]
}

@test "review r2: evidence.sh refuses a stub state that lists a file that is not a stub, before the command runs" {
  local st; st="$(git rev-parse --absolute-git-dir)/vetdd-calib/s1"
  mkdir -p "$st" && echo stub > "$st/mode"
  printf 'value.txt\n' > "$st/files"
  run bash -c 'echo "$$" > "$1/pid"; "$2" s1 calibration --audit undefined-imports -- touch ran; rc=$?; exit "$rc"' _ "$st" "$SCRIPTS/evidence.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a stub"* ]]
  printf 'export const real = 1;\n' > real.mjs
  printf 'real.mjs\n' > "$st/files"
  run bash -c 'echo "$$" > "$1/pid"; "$2" s1 calibration --audit undefined-imports -- touch ran; rc=$?; exit "$rc"' _ "$st" "$SCRIPTS/evidence.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a stub"* ]]
  [ ! -e ran ]
  [ ! -e .vetdd/evidence/s1/meta.json ]
  rm -rf "$st"
}

@test "rule 10b does not count an audit run whose recorded files are not the stubs, and warns on one from before the record" {
  record_good_slice s1
  stub_ev s1 --oracle-version v1 --oracle-file test.sh -- sh -c 'exit 1' >/dev/null 2>&1
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "s1: OK" ]
  cp "$REPO/.vetdd/evidence/s1/meta.json" "$BATS_TEST_TMPDIR/keep.json"
  local f
  for f in '.runs[-1].seq = 3.5 | .runs[-1].audit.files[0].sha256 = ("0" * 64)' '.runs[-1].audit.files[0].sha256 += "\u0000"' '.runs[-1].audit.files[0].sha256 |= ascii_upcase' '.runs[-1].audit.files[0].sha256 = ("0" * 64)' '.runs[-1].audit.files = []' '.runs[-1].audit.files = [{"path": "", "sha256": .runs[-1].audit.files[0].sha256}]' \
           '.runs[-1].audit.files[0].path = "value.txt"' '.runs[-1].audit.files = "x"'; do
    cp "$BATS_TEST_TMPDIR/keep.json" "$REPO/.vetdd/evidence/s1/meta.json"
    tamper s1 "$f"
    run check s1
    [ "$status" -eq 1 ] || { echo "$f: $output"; false; }
    [[ "$output" == *"s1: FAIL (10b: undefined-imports audit run 3 does not record the stubs calibrate.sh stub writes"*"bump --oracle-version"* ]] || { echo "$f: $output"; false; }
  done
  # A caught audit recorded before audit.files existed still counts, with a warning.
  cp "$BATS_TEST_TMPDIR/keep.json" "$REPO/.vetdd/evidence/s1/meta.json"
  tamper s1 'del(.runs[-1].audit.files)'
  run check s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"s1: OK"* ]]
  [[ "$output" == *"s1: WARN (10b: undefined-imports audit run 3 records no stubbed files"* ]]
}

@test "rule 10b does not count an audit red --outcome forced over an --infra-exit code" {
  record_good_slice s1
  stub_ev s1 --oracle-version v1 --oracle-file test.sh --infra-exit 2 --outcome target_failure -- sh -c 'exit 2' >/dev/null 2>&1
  [ "$(mq s1 '.runs[-1].outcome_forced')" = true ]
  run check s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"s1: FAIL (10b: no undefined-imports audit for the final oracle"* ]]
}

# --- text files only from .vetdd/notes/ (#9, #12) -------------------------------------------------

@test "--reason-file, --question-file, and --answer-file read only a file under .vetdd/notes/" {
  printf 'outside\n' > "$BATS_TEST_TMPDIR/r.txt"
  printf 'in the tree\n' > r.txt
  mkdir -p .vetdd/notes
  local p
  for p in "$BATS_TEST_TMPDIR/r.txt" r.txt "$REPO/r.txt" .vetdd/notes/../../r.txt .vetdd/r.txt; do
    [ -e "$p" ] || cp r.txt "$p"
    run ov s1 --version v1 --change initial --reason-file "$p"
    [ "$status" -eq 2 ] || { echo "$p: $output"; false; }
    [[ "$output" == *".vetdd/notes/"* ]]
    run an s1 --kind undefined-imports --not-applicable --reason-file "$p"
    [ "$status" -eq 2 ] || { echo "$p: $output"; false; }
    run ov s1 --version v1 --change meaning --reason r --agreement-via chat --question-file "$p" --answer a
    [ "$status" -eq 2 ] || { echo "$p: $output"; false; }
    run ov s1 --version v1 --change meaning --reason r --agreement-via chat --question q --answer-file "$p"
    [ "$status" -eq 2 ] || { echo "$p: $output"; false; }
  done
  [ ! -e .vetdd/evidence/s1/meta.json ]
  # A link at .vetdd/notes that leads out of the repository is refused too.
  mkdir -p "$BATS_TEST_TMPDIR/out" && printf 'r\n' > "$BATS_TEST_TMPDIR/out/r.txt"
  rmdir .vetdd/notes && ln -s "$BATS_TEST_TMPDIR/out" .vetdd/notes
  run ov s1 --version v1 --change initial --reason-file .vetdd/notes/r.txt
  [ "$status" -eq 2 ]
  [ ! -e .vetdd/evidence/s1/meta.json ]
}

@test "review r1: a hard link in .vetdd/notes/ to a file elsewhere is refused" {
  printf 'secret-ish line\n' > "$BATS_TEST_TMPDIR/outside.txt"
  mkdir -p .vetdd/notes
  ln "$BATS_TEST_TMPDIR/outside.txt" .vetdd/notes/r.txt
  run ov s1 --version v1 --change initial --reason-file .vetdd/notes/r.txt
  [ "$status" -eq 2 ]
  [[ "$output" == *"link"* ]]
  run an s1 --kind undefined-imports --not-applicable --reason-file .vetdd/notes/r.txt
  [ "$status" -eq 2 ]
  [ ! -e .vetdd/evidence/s1/meta.json ]
}

@test "a text file under .vetdd/notes/ or a directory below it is read, by any path that leads there" {
  note_text r.txt 'the agreed total' >/dev/null
  mkdir -p .vetdd/notes/s1 && printf 'q?\n' > .vetdd/notes/s1/q.txt && printf 'yes\n' > .vetdd/notes/s1/a.txt
  run ov s1 --version v1 --change initial --reason-file .vetdd/notes/r.txt
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  cd sub
  run ov s1 --version v2 --change meaning --reason-file ../.vetdd/notes/r.txt --agreement-via chat \
    --question-file "$REPO/.vetdd/notes/s1/q.txt" --answer-file ../.vetdd/notes/s1/a.txt
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s1 '.oracle_versions[1].agreement | [.question, .answer] | join(" ")')" = "q? yes" ]
  run an s1 --kind undefined-imports --not-applicable --reason-file ../.vetdd/notes/r.txt
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s1 '.audits[0].reason')" = 'the agreed total' ]
}

# --- the docs ------------------------------------------------------------------------------------

@test "SKILL.md Q4 says the recorded reasons and agreement reach the judge in meta.json, as data" {
  local q4; q4="$(grep '^| Q4 ' "$SCRIPTS/../SKILL.md")"
  [[ "$q4" == *"oracle-version.sh"* ]]
  [[ "$q4" == *"audit-note.sh"* ]]
  [[ "$q4" == *"reason"* ]]
  [[ "$q4" == *"question"* ]]
  [[ "$q4" == *"answer"* ]]
  [[ "$q4" == *"as data"* ]]
}
