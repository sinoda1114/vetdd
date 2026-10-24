#!/usr/bin/env bats
# calibrate.sh: record a calibration red without ever losing the uncommitted fix.
# unfix   parks the fix (staged, unstaged, and new files) and runs the oracle on the defect.
# plant   saves files so the agent can plant a mutation; planted runs the oracle and restores.
# restore puts back whatever an interrupted calibration left parked.

load test_helper

setup() {
  make_repo
  # The fix: value.txt 0 -> 42, plus a new helper file the fix created.
  printf '42\n' > value.txt
  printf 'helper\n' > helper.txt
}

cal() { "$SCRIPTS/calibrate.sh" "$@"; }
state_dir() { printf '%s/vetdd-calib/%s' "$(git rev-parse --git-dir)" "$1"; }

@test "unfix records target_failure on the defect and restores the fix exactly" {
  run cal unfix s1 --file value.txt --file helper.txt --seam unit --oracle-version 1 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ]
  [ "$(mq s1 '.runs[-1].kind')" = "calibration" ]
  [ "$(mq s1 '.runs[-1].outcome')" = "target_failure" ]
  [ "$(cat value.txt)" = "42" ]
  [ "$(cat helper.txt)" = "helper" ]
  [ ! -e "$(state_dir s1)" ]
}

@test "unfix includes a staged part of the fix" {
  git add value.txt
  run cal unfix s1 --file value.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ]
  [ "$(mq s1 '.runs[-1].outcome')" = "target_failure" ]
  [ "$(cat value.txt)" = "42" ]
  [ -n "$(git diff --cached --name-only -- value.txt)" ]
}

@test "unfix is not affected by diff.noprefix or an external diff driver" {
  git config diff.noprefix true
  git config diff.external false
  run cal unfix s1 --file value.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ]
  [ "$(mq s1 '.runs[-1].outcome')" = "target_failure" ]
  [ "$(cat value.txt)" = "42" ]
}

@test "unfix leaves no intent-to-add entry behind for a new file" {
  run cal unfix s1 --file value.txt --file helper.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ]
  [ -z "$(git ls-files -- helper.txt)" ]
}

@test "unfix refuses to park an oracle file" {
  run cal unfix s1 --file value.txt --file test.sh --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"oracle"* ]]
  [ "$(cat value.txt)" = "42" ]
}

@test "unfix refuses when the files hold no change against HEAD" {
  run cal unfix s1 --file sub/keep.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"nothing to unfix"* ]]
}

@test "an interrupted unfix leaves the patch where restore finds it" {
  # The oracle command kills the calibration from inside, as a Bash timeout would.
  export VETDD_TEST_HOOKS=1
  printf '#!/bin/sh\nkill -9 "$VETDD_CALIBRATE_PID"\n' > killer.sh
  run cal unfix s1 --file value.txt --file helper.txt --oracle-file test.sh -- sh killer.sh
  [ "$(cat value.txt)" = "0" ]
  [ -f "$(state_dir s1)/fix.patch" ]
  run cal unfix s1 --file value.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"restore s1"* ]]
  run cal restore s1
  [ "$status" -eq 0 ]
  [ "$(cat value.txt)" = "42" ]
  [ "$(cat helper.txt)" = "helper" ]
  [ ! -e "$(state_dir s1)" ]
}

@test "the parked patch location is printed before the oracle runs" {
  run cal unfix s1 --file value.txt --oracle-file test.sh -- sh test.sh
  [[ "${lines[0]}" == *"vetdd-calib/s1"* ]]
}

@test "restore refuses when a saved copy was modified" {
  export VETDD_TEST_HOOKS=1
  printf '#!/bin/sh\nkill -9 "$VETDD_CALIBRATE_PID"\n' > killer.sh
  run cal unfix s1 --file value.txt --oracle-file test.sh -- sh killer.sh
  printf 'tampered\n' >> "$(state_dir s1)/copies/value.txt"
  run cal restore s1
  [ "$status" -eq 3 ]
  [[ "$output" == *"changed"* ]]
}

@test "plant then planted records a red on the planted mutation and restores the file" {
  git add -A && git commit -q -m fixed
  run cal plant s2 --file value.txt --oracle-file test.sh
  [ "$status" -eq 0 ]
  printf '41\n' > value.txt
  run cal planted s2 --seam unit --oracle-version 1 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ]
  [ "$(mq s2 '.runs[-1].outcome')" = "target_failure" ]
  [ "$(cat value.txt)" = "42" ]
  [ ! -e "$(state_dir s2)" ]
}

@test "planted without a prior plant refuses" {
  run cal planted s3 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
}

@test "R18: a project in a subdirectory resolves paths and runs the oracle from where it was called" {
  mkdir -p proj && cp test.sh proj/test.sh && printf '0\n' > proj/value.txt
  git add -A && git commit -q -m "add proj"
  cd proj && printf '42\n' > value.txt
  run cal unfix p1 --file value.txt --seam unit --oracle-version 1 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ]
  [ "$(mq p1 '.runs[-1].outcome')" = "target_failure" ]
  [ "$(mq p1 '.runs[-1].conditions.cwd')" = "proj" ]
  [ "$(cat value.txt)" = "42" ]
}

@test "R19: the oracle is protected whatever the spelling" {
  run cal unfix s1 --file ./test.sh --file value.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"oracle"* ]]
  run cal unfix s1 --file value.txt --file test.sh --oracle-file ./test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [ "$(cat value.txt)" = "42" ]
}

@test "R19: directories are refused, so an oracle inside one cannot be parked" {
  run cal unfix s1 --file sub --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"regular file"* ]]
}

@test "R19: unfix requires --oracle-file" {
  run cal unfix s1 --file value.txt -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"--oracle-file"* ]]
  [ "$(cat value.txt)" = "42" ]
}

@test "R20: plant requires --oracle-file, and planted refuses when the oracle changed since plant" {
  git add -A && git commit -q -m fixed
  run cal plant s2 --file value.txt
  [ "$status" -eq 2 ]
  run cal plant s2 --file value.txt --oracle-file test.sh
  [ "$status" -eq 0 ]
  printf '#!/bin/sh\nexit 1\n' > test.sh
  run cal planted s2 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"oracle"*"changed"* ]]
  [ -z "$(jq -r '.runs | length' .vetdd/evidence/s2/meta.json 2>/dev/null | grep -v '^0$')" ]
}

@test "R20: planted refuses when nothing was planted" {
  git add -A && git commit -q -m fixed
  cal plant s2 --file value.txt --oracle-file test.sh
  run cal planted s2 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"no mutation"* ]]
}

@test "R21: an ignored new file cannot be parked, and nothing is touched" {
  mkdir -p ignored && printf 'x\n' > ignored/new.txt
  run cal unfix s1 --file value.txt --file ignored/new.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  # calibrate.sh's own refusal, before any state is saved (#1: git add -N refused it later, with
  # git's own word "ignored", while the guard itself never fired).
  [[ "$output" == *"ignored/new.txt is ignored by git and cannot be parked"* ]] || { echo "$output"; false; }
  [[ "$output" != *"saved state"* ]]
  [ "$(cat value.txt)" = "42" ]
  [ -f ignored/new.txt ]
  [ ! -e "$(state_dir s1)" ]
}

@test "R22: a missing command is refused before anything is changed" {
  run cal unfix s1 --file value.txt --oracle-file test.sh
  [ "$status" -eq 2 ]
  [ "$(cat value.txt)" = "42" ]
  [ ! -e "$(state_dir s1)" ]
  git add -A && git commit -q -m fixed
  cal plant s2 --file value.txt --oracle-file test.sh
  printf '41\n' > value.txt
  run cal planted s2 --oracle-file test.sh
  [ "$status" -eq 2 ]
  [ "$(cat value.txt)" = "41" ]
  [ -d "$(state_dir s2)" ]
}

@test "R23: restore cleans up a state that was interrupted before the patch was written" {
  mkdir -p "$(state_dir s1)" && echo unfix > "$(state_dir s1)/mode" && echo value.txt > "$(state_dir s1)/files"
  run cal restore s1
  [ "$status" -eq 0 ]
  [ ! -e "$(state_dir s1)" ]
  [ "$(cat value.txt)" = "42" ]
}

@test "a calibration that does not end target_failure exits 1 and says so" {
  printf 'changed\n' > sub/keep.txt
  run cal unfix s1 --file sub/keep.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not end target_failure"* ]]
  [ "$(cat sub/keep.txt)" = "changed" ]
}

@test "the calibrating PID is exported only for tests" {
  printf '#!/bin/sh\n[ -z "${VETDD_CALIBRATE_PID:-}" ] || exit 0\nexit 1\n' > probe.sh
  run cal unfix s1 --file value.txt --oracle-file test.sh -- sh probe.sh
  [ "$(mq s1 '.runs[-1].outcome')" = "target_failure" ]
}

@test "R24: planted refuses a saved file that became a symlink, and restore never writes through one" {
  git add -A && git commit -q -m fixed
  cal plant s2 --file value.txt --oracle-file test.sh
  cp test.sh "$BATS_TEST_TMPDIR/oracle-copy" && rm value.txt && ln -s test.sh value.txt
  run cal planted s2 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"symlink"* ]]
  run cal restore s2
  [ "$status" -eq 0 ]
  [ ! -L value.txt ]
  [ "$(cat value.txt)" = "42" ]
  cmp test.sh "$BATS_TEST_TMPDIR/oracle-copy"
}

@test "R25: planted sees a content change in a file that was already modified before plant" {
  git add -A && git commit -q -m fixed
  printf 'first edit\n' > sub/keep.txt
  cal plant s2 --file value.txt --oracle-file test.sh
  printf '41\n' > value.txt
  printf 'second edit\n' > sub/keep.txt
  run cal planted s2 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"outside the saved"* ]]
}

@test "R27: unknown options and --outcome are refused before anything changes" {
  run cal unfix s1 --file value.txt --oracle-file test.sh --seem unit -- sh test.sh
  [ "$status" -eq 2 ]
  run cal unfix s1 --file value.txt --oracle-file test.sh --outcome target_failure -- sh test.sh
  [ "$status" -eq 2 ]
  [ "$(cat value.txt)" = "42" ]
}

@test "R27: a failed evidence recording never passes for an earlier red" {
  run cal unfix s1 --file value.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ]
  chmod 555 .vetdd/evidence/s1
  run cal unfix s1 --file value.txt --oracle-file test.sh -- sh test.sh
  chmod 755 .vetdd/evidence/s1
  [ "$status" -ne 0 ]
  [[ "$output" == *"no new calibration run"* ]]
  [ "$(cat value.txt)" = "42" ]
}

@test "R28: apply.whitespace in the user's config does not change the parked or restored bytes" {
  printf '0  \n' > value.txt && git add -A && git commit -q -m "trailing spaces"
  printf '42  \n' > value.txt
  git config apply.whitespace fix
  printf '#!/bin/sh\n[ "$(cat value.txt)" = "42  " ]\n' > t2.sh
  git add t2.sh && git commit -q -m t2
  run cal unfix s1 --file value.txt --oracle-file t2.sh -- sh t2.sh
  [ "$status" -eq 0 ]
  [ "$(cat value.txt)" = "42  " ]
  git config apply.whitespace error
  run cal unfix s1 --file value.txt --oracle-file t2.sh -- sh t2.sh
  [ "$status" -eq 0 ]
}

@test "R29: a path with glob characters is taken literally" {
  mkdir -p app && printf 'i\n' > app/i.txt && git add -A && git commit -q -m app
  printf 'i edited\n' > app/i.txt
  printf 'new\n' > 'app/[i].txt'
  export VETDD_TEST_HOOKS=1
  printf '#!/bin/sh\nkill -9 "$VETDD_CALIBRATE_PID"\n' > killer.sh
  run cal unfix s1 --file 'app/[i].txt' --oracle-file test.sh -- sh killer.sh
  grep -q 'app/\[i\].txt' "$(state_dir s1)/fix.patch"
  ! grep -q 'app/i.txt' "$(state_dir s1)/fix.patch" || false
  [ "$(cat app/i.txt)" = "i edited" ]
  cal restore s1
  [ "$(cat 'app/[i].txt')" = "new" ]
}

@test "R30: a non-ASCII file name can be planted" {
  printf 'x\n' > 日本.txt && git add -A && git commit -q -m jp
  cal plant s2 --file 日本.txt --oracle-file test.sh
  printf 'y\n' > 日本.txt
  run cal planted s2 --oracle-file test.sh -- sh test.sh
  [[ "$output" != *"outside the saved"* ]]
  [ "$status" -eq 1 ]  # the oracle does not read 日本.txt, so the planted mutation is not seen
  [ "$(cat 日本.txt)" = "x" ]
}

@test "R31: a file name starting with a dash is accepted" {
  printf 'x\n' > ./-dash.txt && git add -A && git commit -q -m dash
  run cal plant s2 --file -dash.txt --oracle-file test.sh
  [ "$status" -eq 0 ]
  cal restore s2
}

@test "R32: a file name containing a newline is refused" {
  printf 'x\n' > "$(printf 'a\nb.txt')"
  run cal unfix s1 --file "$(printf 'a\nb.txt')" --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"newline"* ]]
}

@test "R33: planted sees a mode change in a file outside the saved set" {
  git add -A && git commit -q -m fixed
  printf 'first edit\n' > sub/keep.txt
  cal plant s2 --file value.txt --oracle-file test.sh
  printf '41\n' > value.txt
  chmod +x sub/keep.txt
  run cal planted s2 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"outside the saved"* ]]
}

@test "R34: a failed patch fingerprint stops unfix before the fix is taken out" {
  mkdir -p "$BATS_TEST_TMPDIR/shim"
  printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/shim/sha256sum"
  printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/shim/shasum"
  chmod +x "$BATS_TEST_TMPDIR/shim/"*
  PATH="$BATS_TEST_TMPDIR/shim:$PATH" run cal unfix s1 --file value.txt --file helper.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [ "$(cat value.txt)" = "42" ]
  [ "$(cat helper.txt)" = "helper" ]
  [ ! -e "$(state_dir s1)" ]
}

@test "R36: an oracle file whose name starts with a dash reaches evidence.sh intact" {
  cp test.sh ./-oracle.sh && git add -- ./-oracle.sh && git commit -q -m dash-oracle
  printf '42\n' > value.txt
  run cal unfix s1 --file value.txt --oracle-file -oracle.sh -- sh ./-oracle.sh
  [ "$status" -eq 0 ]
  [ "$(mq s1 '.runs[-1].outcome')" = "target_failure" ]
}

@test "planted refuses --file, which belongs to plant" {
  git add -A && git commit -q -m fixed
  cal plant s2 --file value.txt --oracle-file test.sh
  printf '41\n' > value.txt
  run cal planted s2 --file value.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [ "$(cat value.txt)" = "41" ]
}

@test "a CDPATH in the environment does not change which file is parked" {
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere/sub" && printf 'decoy\n' > "$BATS_TEST_TMPDIR/elsewhere/sub/keep.txt"
  printf 'edited\n' > sub/keep.txt
  printf '#!/bin/sh\n[ "$(cat sub/keep.txt)" = "edited" ]\n' > t3.sh && git add t3.sh && git commit -q -m t3
  CDPATH="$BATS_TEST_TMPDIR/elsewhere" run cal unfix s1 --file sub/keep.txt --oracle-file t3.sh -- sh t3.sh
  [ "$status" -eq 0 ]
  [ "$(cat sub/keep.txt)" = "edited" ]
}

@test "two calibrations of one slice cannot both claim the state directory" {
  mkdir -p "$(dirname "$(state_dir s1)")"
  mkdir "$(state_dir s1)"
  run cal unfix s1 --file value.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [ "$(cat value.txt)" = "42" ]
  [ -d "$(state_dir s1)" ]
}

@test "R38: a mutation staged after plant is taken out of the index too" {
  git add -A && git commit -q -m fixed
  cal plant s2 --file value.txt --oracle-file test.sh
  printf '41\n' > value.txt && git add value.txt
  run cal planted s2 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ]
  [ "$(cat value.txt)" = "42" ]
  [ -z "$(git diff --cached --name-only -- value.txt)" ]
}

@test "R39: a changed file with a newline in its name, outside the saved set, is still watched" {
  git add -A && git commit -q -m fixed
  printf 'one\n' > "$(printf 'odd\nname.txt')"
  cal plant s2 --file value.txt --oracle-file test.sh
  printf '41\n' > value.txt
  printf 'two\n' > "$(printf 'odd\nname.txt')"
  run cal planted s2 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"outside the saved"* ]]
}

@test "R40: line-ending conversion in the user's config does not change the restored bytes" {
  git config core.autocrlf true
  run cal unfix s1 --file value.txt --file helper.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ]
  ! grep -q "$(printf '\r')" value.txt || false
  ! grep -q "$(printf '\r')" helper.txt || false
}

@test "R41: the oracle is recognised as the same file under another letter case" {
  run cal unfix s1 --file Test.sh --file value.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [ "$(cat value.txt)" = "42" ]
  [ -f test.sh ]
}

@test "R42: restore refuses cleanly when the state lost its file list" {
  mkdir -p "$(state_dir s1)" && echo unfix > "$(state_dir s1)/mode" && printf 'x\n' > "$(state_dir s1)/fix.patch"
  run cal restore s1
  [ "$status" -eq 3 ]
  [[ "$output" == *"incomplete"* ]]
}

@test "R43: restore refuses while the calibration that owns the state is still running" {
  mkdir -p "$(state_dir s1)" && echo unfix > "$(state_dir s1)/mode" && echo $$ > "$(state_dir s1)/pid"
  run cal restore s1
  [ "$status" -eq 2 ]
  [[ "$output" == *"still running"* ]]
  [ -d "$(state_dir s1)" ]
  # A reused pid must not lead to stopping an unrelated process (#1): the way out is the pid file.
  [[ "$output" != *"stop it"* ]]
  [[ "$output" == *"ps -p $$"* ]] || { echo "$output"; false; }
  [[ "$output" == *"vetdd-calib/s1/pid"* ]]
}

@test "R44: plant refuses when a fingerprint cannot be taken" {
  git add -A && git commit -q -m fixed
  mkdir -p "$BATS_TEST_TMPDIR/shim"
  printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/shim/sha256sum"
  printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/shim/shasum"
  chmod +x "$BATS_TEST_TMPDIR/shim/"*
  PATH="$BATS_TEST_TMPDIR/shim:$PATH" run cal plant s2 --file value.txt --oracle-file test.sh
  [ "$status" -eq 2 ]
  [ ! -e "$(state_dir s2)" ]
}

@test "R45: diff.context in the user's config does not stop unfix" {
  printf '1\n2\n3\n4\n5\n6\n7\n8\n0\n9\n' > value.txt && git add value.txt && git commit -q -m long
  printf '#!/bin/sh\ngrep -qx 42 value.txt\n' > t4.sh && git add t4.sh && git commit -q -m t4
  sed -i.bak 's/^0$/42/' value.txt && rm -f value.txt.bak
  git config diff.context 0
  run cal unfix s1 --file value.txt --oracle-file t4.sh -- sh t4.sh
  [ "$status" -eq 0 ]
  grep -qx 42 value.txt
}

@test "R46: index entries of names with a backslash or a tab survive the calibration" {
  printf 'b\n' > 'back\slash.txt' && printf 't\n' > "$(printf 'ta\tb.txt')"
  git add -- 'back\slash.txt' "$(printf 'ta\tb.txt')" && git commit -q -m odd
  printf 'b2\n' > 'back\slash.txt' && printf 't2\n' > "$(printf 'ta\tb.txt')"
  run cal unfix s1 --file value.txt --file 'back\slash.txt' --file "$(printf 'ta\tb.txt')" --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ]
  [ -n "$(git ls-files -- 'back\slash.txt')" ]
  [ -n "$(git ls-files -- "$(printf 'ta\tb.txt')")" ]
  [ -z "$(git diff --cached --name-only --diff-filter=D)" ]
}

@test "R47: an intent-to-add entry stays intent-to-add" {
  git add -N helper.txt
  run cal unfix s1 --file value.txt --file helper.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ]
  [ -n "$(git ls-files -- helper.txt)" ]
  [ -z "$(git diff --cached --name-only -- helper.txt)" ]
  [ "$(cat helper.txt)" = "helper" ]
}

@test "R47: skip-worktree and assume-unchanged files are refused" {
  git update-index --skip-worktree sub/keep.txt
  printf 'x\n' > sub/keep.txt
  run cal unfix s1 --file value.txt --file sub/keep.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"skip-worktree"* ]]
  [ "$(cat value.txt)" = "42" ]
}

@test "R48: restore refuses while planted is running the oracle" {
  export CAL="$SCRIPTS/calibrate.sh"
  printf '#!/bin/sh\n"$CAL" restore s2 >/dev/null 2>&1; echo $? > "$RC"\nexit 1\n' > nested.sh
  git add -A && git commit -q -m fixed
  export RC="$BATS_TEST_TMPDIR/rc.txt"
  cal plant s2 --file value.txt --oracle-file test.sh
  printf '41\n' > value.txt
  run cal planted s2 --oracle-file test.sh -- sh nested.sh
  [ "$(cat "$RC")" = "2" ]
  [ "$(cat value.txt)" = "42" ]
}

@test "R49: plant and planted work in a repository without commits and still watch other files" {
  NOHEAD="$BATS_TEST_TMPDIR/nohead" && mkdir -p "$NOHEAD" && cd "$NOHEAD" && git init -q
  printf '#!/bin/sh\n[ "$(cat value.txt)" = "42" ]\n' > test.sh
  printf '42\n' > value.txt && printf 'o\n' > other.txt && git add -A
  cal plant s9 --file value.txt --oracle-file test.sh
  printf '41\n' > value.txt && printf 'o2\n' > other.txt
  run cal planted s9 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"outside the saved"* ]]
}

@test "R50: restore keeps a copy of edits made after the state was saved" {
  git add -A && git commit -q -m fixed
  cal plant s2 --file value.txt --oracle-file test.sh
  printf 'later edit\n' > value.txt
  run cal restore s2
  [ "$status" -eq 0 ]
  [[ "$output" == *"replaced"* ]]
  [ "$(cat value.txt)" = "42" ]
  grep -rqx 'later edit' "$(git rev-parse --absolute-git-dir)/vetdd-calib/"s2.replaced.*
}

@test "R51: a mutation of the executable bit alone counts as planted" {
  git add -A && git commit -q -m fixed
  printf '#!/bin/sh\n[ ! -x value.txt ]\n' > t5.sh && git add t5.sh && git commit -q -m t5
  cal plant s2 --file value.txt --oracle-file t5.sh
  chmod +x value.txt
  run cal planted s2 --oracle-file t5.sh -- sh t5.sh
  [ "$status" -eq 0 ]
  [ ! -x value.txt ]
}

@test "R53: a gitfile named .git is refused" {
  printf 'gitdir: elsewhere\n' > sub/.git
  run cal plant s2 --file sub/.git --oracle-file test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *".git"* ]]
}

@test "R54: plant does not leave its pid behind" {
  git add -A && git commit -q -m fixed
  cal plant s2 --file value.txt --oracle-file test.sh
  [ ! -e "$(state_dir s2)/pid" ]
}

@test "R55: a --file spelled in another letter case is recorded under its real name" {
  touch Value.probe 2>/dev/null; if [ ! -e value.probe ]; then skip "case-sensitive file system"; fi
  rm -f Value.probe
  run cal unfix s1 --file VALUE.TXT --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ]
  [ -n "$(ls | grep -x value.txt)" ]
  [ -z "$(ls | grep -x VALUE.TXT)" ]
}

@test "an --oracle-version evidence.sh would refuse is a usage error (exit 2) before the fix is parked (H1)" {
  local before_fix
  before_fix="$(cat value.txt)"
  run cal unfix s1 --file value.txt --oracle-version '1.0+rc' --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"--oracle-version"* ]]
  [ "$(cat value.txt)" = "$before_fix" ]
  [ ! -e "$REPO/.vetdd/evidence/s1/meta.json" ]
}

@test "plant and planted accept the same oracle file named twice (K3)" {
  run cal plant s1 --file value.txt --oracle-file test.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '0\n' > value.txt
  run cal planted s1 --oracle-file test.sh --oracle-file ./test.sh -- sh test.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "an --oracle-file name with a control character is a usage error before the fix is parked (Q4)" {
  local before_fix
  before_fix="$(cat value.txt)"
  cp test.sh "$(printf 'a\tb.sh')"
  run cal unfix s1 --file value.txt --oracle-version v1 --oracle-file "$(printf 'a\tb.sh')" -- sh test.sh
  [ "$status" -eq 2 ]
  [ "$(cat value.txt)" = "$before_fix" ]
  [ ! -e "$REPO/.vetdd/evidence/s1/meta.json" ]
}

@test "plant and planted name one oracle file whose directory is spelled in another case (R3)" {
  mkdir -p sub && cp test.sh sub/t.sh
  [ -e SUB/t.sh ] || skip "the file system is case-sensitive"
  run cal plant s1 --file value.txt --oracle-file sub/t.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '0\n' > value.txt
  run cal planted s1 --oracle-file SUB/t.sh -- sh sub/t.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# --- PR8: --infra-exit for verify scripts (exit 2 = could not observe) ------------------------------

@test "planted passes --infra-exit to evidence.sh: a script that could not observe is infrastructure_error, not red" {
  git add -A && git commit -q -m fix
  printf '#!/bin/sh\nexit 2\n' > blind.sh
  git add blind.sh && git commit -q -m blind
  cal plant p1 --file value.txt --oracle-file blind.sh
  printf '7\n' > value.txt
  run cal planted p1 --oracle-file blind.sh --infra-exit 2 -- sh blind.sh
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(mq p1 '.runs[-1].outcome')" = infrastructure_error ]
  [ "$(cat value.txt)" = 42 ]
  [ ! -e "$(git rev-parse --git-dir)/vetdd-calib/p1" ]
}

@test "unfix takes --infra-exit too, and a bad value is refused before anything is parked" {
  printf '#!/bin/sh\nexit 2\n' > blind.sh
  git add blind.sh
  run cal unfix u1 --file value.txt --oracle-file blind.sh --infra-exit 2 -- sh blind.sh
  [ "$(mq u1 '.runs[-1].outcome')" = infrastructure_error ] || { echo "$output"; false; }
  [ "$(cat value.txt)" = 42 ]
  local v
  for v in 0 256 x ''; do
    run cal unfix u2 --file value.txt --oracle-file blind.sh --infra-exit "$v" -- sh blind.sh
    [ "$status" -eq 2 ] || { echo "accepted --infra-exit [$v]"; false; }
    [ "$(cat value.txt)" = 42 ]
    [ ! -e "$(git rev-parse --git-dir)/vetdd-calib/u2" ]
  done
}

# bash 3.2 matches a bracket range by the locale's collation (utf8_locale in test_helper.bash): [a-z]
# holds the capital letters too, so a range must never stand for "lower case".
@test "locale: plant and planted work under a UTF-8 locale (a tracked file is not taken for assume-unchanged)" {
  local loc; loc="$(utf8_locale)"
  [ -n "$loc" ] || skip "no UTF-8 locale on this machine"
  git add -A && git commit -q -m fixed
  LC_ALL="$loc" run cal plant s2 --file value.txt --oracle-file test.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '41\n' > value.txt
  LC_ALL="$loc" run cal planted s2 --seam unit --oracle-version 1 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s2 '.runs[-1].outcome')" = "target_failure" ]
}

@test "#50: an assume-unchanged file is refused under the C locale and under a UTF-8 locale" {
  local loc; loc="$(utf8_locale)"
  [ -n "$loc" ] || skip "no UTF-8 locale on this machine"
  git update-index --assume-unchanged sub/keep.txt
  local l
  for l in C "$loc"; do
    LC_ALL="$l" run cal unfix s1 --file value.txt --file sub/keep.txt --oracle-file test.sh -- sh test.sh
    [ "$status" -eq 2 ] || { echo "$l: $output"; false; }
    [[ "$output" == *"sub/keep.txt is marked assume-unchanged"* ]] || { echo "$l: $output"; false; }
    [ "$(cat value.txt)" = "42" ]
    [ ! -e "$(state_dir s1)" ]
  done
}

@test "#50: planted run under another locale than plant still finds nothing else changed" {
  local loc; loc="$(utf8_locale)"
  [ -n "$loc" ] || skip "no UTF-8 locale on this machine"
  # Oracle files and untracked files whose order and spelling (printf %q) depend on the locale: same
  # contents, so the names decide the order (C puts B before a), and a name outside ASCII.
  cp test.sh a.sh; cp test.sh B.sh
  git add -A && git commit -q -m fixed
  printf 'same\n' > B.txt; printf 'same\n' > a.txt; printf 'same\n' > "$(printf 'caf\303\251.txt')"
  local from to
  for from in C "$loc"; do
    if [ "$from" = C ]; then to="$loc"; else to=C; fi
    LC_ALL="$from" run cal plant s2 --file value.txt --oracle-file a.sh --oracle-file B.sh
    [ "$status" -eq 0 ] || { echo "plant under $from: $output"; false; }
    printf '41\n' > value.txt
    LC_ALL="$to" run cal planted s2 --seam unit --oracle-version 1 --oracle-file a.sh --oracle-file B.sh -- sh test.sh
    [ "$status" -eq 0 ] || { echo "planted under $to: $output"; false; }
    [ "$(mq s2 '.runs[-1].outcome')" = "target_failure" ]
    [ "$(cat value.txt)" = "42" ]
  done
}

# --- #5: --test-report reaches evidence.sh from unfix and planted ------------------------------------

# A test command that writes a jest-json report and passes only when value.txt holds 42.
report_oracle() {
  printf '#!/bin/sh\nmkdir -p .vetdd/reports\ncp "%s" .vetdd/reports/r.json\n[ "$(cat value.txt)" = "42" ]\n' \
    "$BATS_TEST_DIRNAME/fixtures/reports/vitest5-pass.json" > rtest.sh
}

@test "unfix forwards --test-report: the calibration run records the runner's counts (#5)" {
  report_oracle
  run cal unfix s1 --file value.txt --file helper.txt --oracle-file rtest.sh --test-report jest-json:.vetdd/reports/r.json -- sh rtest.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s1 '.runs[-1].kind')" = calibration ]
  [ "$(mq s1 '.runs[-1].tests.status')" = ok ]
  [ "$(mq s1 '.runs[-1].tests.total')" -gt 0 ]
  [ "$(cat value.txt)" = 42 ]
}

@test "planted forwards --test-report: the calibration run records the runner's counts (#5)" {
  report_oracle
  git add -A && git commit -q -m fixed
  cal plant s2 --file value.txt --oracle-file rtest.sh
  printf '41\n' > value.txt
  run cal planted s2 --oracle-file rtest.sh --test-report jest-json:.vetdd/reports/r.json -- sh rtest.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq s2 '.runs[-1].tests.status')" = ok ]
  [ "$(cat value.txt)" = 42 ]
}

@test "a --test-report evidence.sh would refuse is a usage error (exit 2) before the fix is parked (#5)" {
  report_oracle
  local bad
  # Not jest-json:, outside .vetdd/reports/, a tracked file, a directory.
  mkdir -p .vetdd/reports/dir
  for bad in r.json jest-json: jest-json:r.json jest-json:test.sh jest-json:.vetdd/reports/dir; do
    run cal unfix s1 --file value.txt --oracle-file rtest.sh --test-report "$bad" -- sh rtest.sh
    [ "$status" -eq 2 ] || { echo "accepted --test-report [$bad]: $output"; false; }
    [[ "$output" == *"--test-report"* ]]
    [[ "$output" != *"unknown option"* ]]
    [[ "$output" != *"saved state"* ]]
    [ "$(cat value.txt)" = 42 ]
    [ ! -e "$(state_dir s1)" ]
    [ ! -e .vetdd/evidence/s1/meta.json ]
  done
  run cal unfix s1 --file value.txt --oracle-file rtest.sh --test-report
  [ "$status" -eq 2 ]
}

@test "planted refuses a bad --test-report before running, and keeps the planted state for a corrected run (#5)" {
  report_oracle
  git add -A && git commit -q -m fixed
  cal plant s2 --file value.txt --oracle-file rtest.sh
  printf '41\n' > value.txt
  run cal planted s2 --oracle-file rtest.sh --test-report jest-json:out.json -- sh rtest.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"--test-report"* ]]
  [ "$(cat value.txt)" = 41 ]
  [ -d "$(state_dir s2)" ]
  [ ! -e .vetdd/evidence/s2/meta.json ]
  run cal planted s2 --oracle-file rtest.sh --test-report jest-json:.vetdd/reports/r.json -- sh rtest.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat value.txt)" = 42 ]
}

# --- #1 (R57): one calibration at a time in a working tree -------------------------------------------

lock_path() { printf '%s/vetdd-calib/.lock' "$(git rev-parse --git-dir)"; }

@test "while one slice is calibrating, another slice's plant, unfix, and restore are refused, so no fix is lost (#1 R57)" {
  export CAL="$SCRIPTS/calibrate.sh" RCS="$BATS_TEST_TMPDIR/rcs.txt"
  # A state of s3 that restore would simply remove (no file list, no mode).
  mkdir -p "$(state_dir s3)"
  # The oracle of s1: while s1's fix is taken out, try the other slices, then fail (the red).
  printf '#!/bin/sh\n"$CAL" plant s2 --file value.txt --oracle-file test.sh >/dev/null 2>"$RCS.err"; echo "plant $?" >> "$RCS"\n"$CAL" unfix s4 --file helper.txt --oracle-file test.sh -- sh test.sh >/dev/null 2>>"$RCS.err"; echo "unfix $?" >> "$RCS"\n"$CAL" restore s3 >/dev/null 2>>"$RCS.err"; echo "restore $?" >> "$RCS"\nexit 1\n' > nested.sh
  git add nested.sh
  run cal unfix s1 --file value.txt --oracle-file nested.sh -- sh nested.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$RCS")" = "$(printf 'plant 2\nunfix 2\nrestore 2')" ] || { cat "$RCS" "$RCS.err"; false; }
  # Each refusal names the running slice.
  [ "$(grep -c 'slice s1' "$RCS.err")" -eq 3 ] || { cat "$RCS.err"; false; }
  [ ! -e "$(state_dir s2)" ]
  [ ! -e "$(state_dir s4)" ]
  [ -d "$(state_dir s3)" ]
  [ "$(cat value.txt)" = 42 ]
  [ "$(cat helper.txt)" = helper ]
  # The lock goes with the run.
  [ ! -e "$(lock_path)" ] && [ ! -L "$(lock_path)" ]
}

@test "the working tree's lock is released after a run, a refusal, and a planted run; plant leaves it to planted (#1 R57)" {
  run cal unfix s1 --file value.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ]
  [ ! -L "$(lock_path)" ]
  run cal unfix s1 --file sub/keep.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [ ! -L "$(lock_path)" ]
  git add -A && git commit -q -m fixed
  run cal plant s2 --file value.txt --oracle-file test.sh
  [ "$status" -eq 0 ]
  # Held for the planted run to come, by no live process.
  [ "$(readlink "$(lock_path)")" = "plant:s2" ]
  printf '41\n' > value.txt
  run cal planted s2 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ]
  [ ! -L "$(lock_path)" ]
}

@test "a killed calibration keeps the lock until its own restore, which names the way out (#1 R57)" {
  export VETDD_TEST_HOOKS=1
  printf '#!/bin/sh\nkill -9 "$VETDD_CALIBRATE_PID"\n' > killer.sh
  run cal unfix s1 --file value.txt --oracle-file test.sh -- sh killer.sh
  [ "$(cat value.txt)" = 0 ]
  run cal unfix s2 --file helper.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"slice s1"*"calibrate.sh restore s1"* ]] || { echo "$output"; false; }
  [ ! -e "$(state_dir s2)" ]
  run cal restore s2
  [ "$status" -eq 2 ]
  run cal restore s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat value.txt)" = 42 ]
  [ ! -L "$(lock_path)" ]
  run cal unfix s2 --file helper.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "restore of a slice clears the lock its killed run left after the state was already gone (#1 R57)" {
  export VETDD_TEST_HOOKS=1
  printf '#!/bin/sh\nkill -9 "$VETDD_CALIBRATE_PID"\n' > killer.sh
  run cal unfix s1 --file value.txt --oracle-file test.sh -- sh killer.sh
  run cal restore s1
  [ "$status" -eq 0 ]
  # The run was killed between removing its state and releasing the lock.
  run cal unfix s1 --file value.txt --oracle-file test.sh -- sh killer.sh
  rm -rf "$(state_dir s1)"
  printf '42\n' > value.txt
  [ -L "$(lock_path)" ]
  run cal restore s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"lock"* ]]
  [ ! -L "$(lock_path)" ]
}

# --- review round 1 ----------------------------------------------------------------------------------

@test "between plant and planted, another slice cannot plant, unfix, or stub the same tree (review 1 #2)" {
  git add -A && git commit -q -m fixed
  printf '42\n' > other.txt && git add other.txt && git commit -q -m other
  cal plant s2 --file value.txt --oracle-file test.sh
  printf '41\n' > value.txt
  # s1 would save the mutation as its original and later write it over the fix.
  run cal plant s1 --file value.txt --oracle-file test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"slice s2"*"planted s2"* ]] || { echo "$output"; false; }
  [ ! -e "$(state_dir s1)" ]
  printf '7\n' > other.txt
  run cal unfix s3 --file other.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [ "$(cat other.txt)" = 7 ]
  printf '7\n' > other.js
  run cal stub s4 --file other.js --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [ "$(cat other.js)" = 7 ]
  # Put the tree outside s2's saved set back as it was at plant.
  printf '42\n' > other.txt && rm -f other.js
  run cal planted s2 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat value.txt)" = 42 ]
  [ ! -L "$(lock_path)" ]
  run cal plant s1 --file value.txt --oracle-file test.sh
  [ "$status" -eq 0 ]
}

@test "a planted run refused before it starts keeps the plant's hold on the tree (review 1 #2)" {
  git add -A && git commit -q -m fixed
  cal plant s2 --file value.txt --oracle-file test.sh
  # Nothing planted yet: planted refuses, and the tree stays held for s2.
  run cal planted s2 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [ "$(readlink "$(lock_path)")" = "plant:s2" ]
  run cal restore s2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -L "$(lock_path)" ]
}

@test "restore never takes over a lock while another takeover is in progress (codex review 1)" {
  export VETDD_TEST_HOOKS=1
  printf '#!/bin/sh\nkill -9 "$VETDD_CALIBRATE_PID"\n' > killer.sh
  run cal unfix s1 --file value.txt --oracle-file test.sh -- sh killer.sh
  ln -s "1:s1" "$(lock_path).takeover"
  run cal restore s1
  [ "$status" -eq 2 ]
  [[ "$output" == *"taking over"* ]] || { echo "$output"; false; }
  [ "$(cat value.txt)" = 0 ]
  rm -f "$(lock_path).takeover"
  run cal restore s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat value.txt)" = 42 ]
  [ ! -L "$(lock_path).takeover" ]
}

@test "a lock naming pid 0 is unreadable, not a running calibration (review 1 D2)" {
  mkdir -p "$(dirname "$(lock_path)")" && ln -s "0:s9" "$(lock_path)"
  run cal unfix s1 --file value.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"unreadable"* ]] || { echo "$output"; false; }
}

@test "stub takes no --test-report: the audit is not a run to count (review 1 D1)" {
  printf 'export const a = 1;\n' > a.js
  report_oracle
  run cal stub s1 --file a.js --oracle-file rtest.sh --test-report jest-json:.vetdd/reports/r.json -- sh rtest.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"--test-report"* ]]
  [ "$(cat a.js)" = "export const a = 1;" ]
  [ ! -e .vetdd/evidence/s1/meta.json ]
}

# --- review round 2 ----------------------------------------------------------------------------------

@test "a takeover never leaves the tree unlocked: another slice started mid-takeover is refused (codex review 2)" {
  export VETDD_TEST_HOOKS=1 CAL="$SCRIPTS/calibrate.sh" RCS="$BATS_TEST_TMPDIR/rcs.txt" LOCK="$(cd "$(git rev-parse --git-dir)" && pwd -P)/vetdd-calib/.lock"
  printf '#!/bin/sh\nkill -9 "$VETDD_CALIBRATE_PID"\n' > killer.sh
  run cal unfix s1 --file value.txt --oracle-file test.sh -- sh killer.sh
  # An rm that, when it removes the lock while a takeover is under way, starts another slice at once.
  mkdir -p "$BATS_TEST_TMPDIR/shim"
  printf '#!/bin/sh\nfor a in "$@"; do last="$a"; done\n/bin/rm "$@"; rc=$?\nif [ -z "${IN_SHIM:-}" ] && [ "$last" = "$LOCK" ] && [ -L "$LOCK.takeover" ]; then\n  IN_SHIM=1 "$CAL" unfix s2 --file helper.txt --oracle-file test.sh -- sh test.sh >/dev/null 2>&1; echo $? >> "$RCS"\nfi\nexit $rc\n' > "$BATS_TEST_TMPDIR/shim/rm"
  chmod +x "$BATS_TEST_TMPDIR/shim/rm"
  PATH="$BATS_TEST_TMPDIR/shim:$PATH" run cal restore s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -s "$RCS" ] || [ "$(cat "$RCS")" = 2 ] || { echo "s2 ran mid-takeover: exit $(cat "$RCS")"; false; }
  [ "$(cat value.txt)" = 42 ]
  [ ! -e .vetdd/evidence/s2/meta.json ]
}

@test "planted resumes after a planted run killed before it claimed the run (review 2 #2)" {
  git add -A && git commit -q -m fixed
  cal plant s2 --file value.txt --oracle-file test.sh
  printf '41\n' > value.txt
  # A planted run killed during its checks leaves its own dead pid on the lock, and no run.lock.
  dead="$(sh -c 'echo $$')"
  rm -f "$(lock_path)" && ln -s "$dead:s2" "$(lock_path)"
  run cal planted s2 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat value.txt)" = 42 ]
  [ ! -L "$(lock_path)" ]
}

@test "plant fails (exit 3) when it cannot hand the lock to the plant hold, and the tree stays locked (review 2 #3)" {
  git add -A && git commit -q -m fixed
  mkdir -p "$BATS_TEST_TMPDIR/shim"
  printf '#!/bin/sh\nfor a in "$@"; do last="$a"; done\ncase "$last" in *.lock.new.*) exit 1 ;; esac\nexec /bin/ln "$@"\n' > "$BATS_TEST_TMPDIR/shim/ln"
  chmod +x "$BATS_TEST_TMPDIR/shim/ln"
  PATH="$BATS_TEST_TMPDIR/shim:$PATH" run cal plant s2 --file value.txt --oracle-file test.sh
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$(readlink "$(lock_path)")" == *":s2" ]]
  run cal plant s1 --file value.txt --oracle-file test.sh
  [ "$status" -eq 2 ]
  printf '41\n' > value.txt
  run cal planted s2 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat value.txt)" = 42 ]
}

# --- review round 3 ----------------------------------------------------------------------------------

@test "planted does not resume over a restore that was killed half way (review 3 #1)" {
  git add -A && git commit -q -m fixed
  cal plant s2 --file value.txt --file sub/keep.txt --oracle-file test.sh
  printf '41\n' > value.txt && printf 'mutated\n' > sub/keep.txt
  # A mktemp that fails for the second file: restore stops half way (exit 3), as a kill there would,
  # leaving its own pid on the lock and no temp file behind.
  mkdir -p "$BATS_TEST_TMPDIR/shim"
  printf '#!/bin/sh\ncase "$1" in */sub/keep.txt.*) exit 1 ;; esac\nexec "%s" "$@"\n' "$(command -v mktemp)" > "$BATS_TEST_TMPDIR/shim/mktemp"
  chmod +x "$BATS_TEST_TMPDIR/shim/mktemp"
  PATH="$BATS_TEST_TMPDIR/shim:$PATH" run cal restore s2
  [ "$status" -eq 3 ]
  [ "$(cat value.txt)" = 42 ] && [ "$(cat sub/keep.txt)" = mutated ] || { echo "the shim did not stop restore half way"; false; }
  run cal planted s2 --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"restore s2"* ]]
  [ ! -e .vetdd/evidence/s2/meta.json ]
  run cal restore s2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat sub/keep.txt)" = keep ]
}
