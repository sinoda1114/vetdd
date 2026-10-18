#!/usr/bin/env bats
# #62: the dogfood frictions of #57 get a hint at the point of failure, not only a note in the docs.
# zsh does not split a variable holding several words, so "--oracle-file a --oracle-file b" or
# "a.sh b.sh" arrives as one argument; a fix that is already committed leaves unfix nothing to take out.

load test_helper

setup() { make_repo; }

cal() { "$SCRIPTS/calibrate.sh" "$@"; }

split_hint='holds several words'

@test "#62: evidence.sh names the unsplit argument when one argument holds several options" {
  run ev s1 before --seam unit '--oracle-file test.sh --oracle-version v1' -- sh test.sh
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"$split_hint"*zsh* ]] || { echo "$output"; false; }
}

@test "#62: evidence.sh names the unsplit argument when an oracle file value holds several paths" {
  printf 'x\n' > b.sh
  run ev s1 before --seam unit --oracle-version v1 --oracle-file 'test.sh b.sh' -- sh test.sh
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"oracle file not found"*"$split_hint"* ]] || { echo "$output"; false; }
}

@test "#62: calibrate.sh names the unsplit argument for an option or a file value with several words" {
  printf '42\n' > value.txt
  run cal unfix s1 --file value.txt '--oracle-file test.sh' -- sh test.sh
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"unknown option"*"$split_hint"* ]] || { echo "$output"; false; }
  run cal unfix s1 --file 'value.txt test.sh' --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"$split_hint"* ]] || { echo "$output"; false; }
}

@test "#62: a one-word mistake gets no split hint" {
  run ev s1 before --bogus -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" != *"$split_hint"* ]] || { echo "$output"; false; }
  run cal unfix s1 --file missing.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" != *"$split_hint"* ]] || { echo "$output"; false; }
}

@test "#62: a real file name with a space still works" {
  printf '#!/bin/sh\n[ "$(cat value.txt)" = "42" ]\n' > 'my test.sh'
  run ev s1 before --seam unit --oracle-version v1 --oracle-file 'my test.sh' -- sh 'my test.sh'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "#62: unfix with nothing to take out points to plant and planted for a committed fix" {
  run cal unfix s1 --file sub/keep.txt --oracle-file test.sh -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"nothing to unfix"*"plant"*"planted"* ]] || { echo "$output"; false; }
}

@test "#62 r1: the hint is worded as a condition, and a newline in a name is not taken for several words" {
  run ev s1 before --seam unit --oracle-version v1 --oracle-file 'test.sh b.sh' -- sh test.sh
  [[ "$output" == *"if you meant several arguments"* ]] || { echo "$output"; false; }
  run ev s1 before --seam unit --oracle-version v1 --oracle-file $'a\nb.sh' -- sh test.sh
  [ "$status" -eq 2 ]
  [[ "$output" != *"$split_hint"* ]] || { echo "$output"; false; }
}

@test "#62 r1: a command passed as one argument with a space (zsh's \"\$CMD\") gets the hint when it is not found" {
  run ev s1 before --seam unit --oracle-version v1 --oracle-file test.sh -- 'sh test.sh'
  [[ "$output" == *"command not found"*"$split_hint"* ]] || { echo "$output"; false; }
  run ev s2 before --seam unit --oracle-version v1 --oracle-file test.sh -- no-such-command-62
  [[ "$output" != *"$split_hint"* ]] || { echo "$output"; false; }
}
