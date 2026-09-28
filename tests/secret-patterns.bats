#!/usr/bin/env bats
# lib/secret-patterns.sh: a long line is searched in overlapping windows, so the time stays linear
# in the line length and a secret near a window edge is still found.

load test_helper

setup() {
  . "$SCRIPTS/lib/secret-patterns.sh"
  IN="$BATS_TEST_TMPDIR/in.txt"
  TOKEN="$(printf 'gh%s_%s' p aB3dE5gH7jK9mN1pQ3sT5vW7yZ9bC1dE3fG5)"
}

# long_line <repeats> <tail>: one line of exempt look-alikes, then <tail>.
long_line() {
  awk -v n="$1" -v t="$2" 'BEGIN { for (i = 0; i < n; i++) printf "accessToken: someVariableName, "; print t }' > "$IN"
}

@test "Y2: a 250 KB line of exempt look-alikes is searched in seconds, and a token at its end is found" {
  long_line 8000 " $TOKEN"
  local start=$SECONDS
  run vetdd_find_secrets x < "$IN"
  [ $((SECONDS - start)) -lt 5 ]
  [ "$status" -eq 0 ]
  [ "$output" = "x:1: secret: github-token" ]
}

@test "Y2: a secret that crosses the edge of a search window is found" {
  local pad k
  for k in 4080 4090 4095 4100; do
    pad="$(awk -v n="$k" 'BEGIN { for (i = 0; i < n; i++) printf "a" }')"
    printf '%s %s\n' "$pad" "$TOKEN" > "$IN"
    run vetdd_find_secrets x < "$IN"
    [ "$output" = "x:1: secret: github-token" ] || { echo "pad $k: $output"; false; }
  done
}

@test "Y2: a long line with no secret reports nothing" {
  long_line 8000 ""
  run vetdd_find_secrets x < "$IN"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

# jwt_of <payload chars>: a JWT whose payload has that many characters (no key word, no Bearer).
jwt_of() {
  awk -v n="$1" 'BEGIN { printf "eyJhbGciOiJIUzI1NiJ9.eyJ"; for (i = 3; i < n; i++) printf "a"; printf ".c2lnbmF0dXJlLXZhbHVl" }'
}

@test "Z1: a bare JWT with a long payload is found wherever it starts in a long line" {
  local jwt pad start
  jwt="$(jwt_of 1500)"
  for start in 3000 3300 3500 3584 3700; do
    pad="$(awk -v n="$start" 'BEGIN { for (i = 0; i < n; i++) printf "a" }')"
    printf '%s %s %s\n' "$pad" "$jwt" "$pad" > "$IN"
    run vetdd_find_secrets x < "$IN"
    [ "$output" = "x:1: secret: jwt" ] || { echo "start $start: $output"; false; }
  done
}

@test "Z5: an escaped slash or an escaped printable ASCII character does not hide a secret" {
  printf '%s\n' '{"dsn":"postgres:\/\/app:S3cretPw@db.internal:5432\/app"}' > "$IN"
  run vetdd_find_secrets x < "$IN"
  [ "$output" = "x:1: secret: url-credentials" ]
  printf '{"to":"alice\\u0040%s.io"}\n' corp > "$IN"
  run vetdd_find_secrets x < "$IN"
  [ "$output" = "x:1: secret: email" ]
}

@test "B2: a quoted password with spaces is an assignment" {
  printf 'password: "correct horse battery staple"\n' > "$IN"
  run vetdd_find_secrets x < "$IN"
  [ "$output" = "x:1: secret: assignment" ]
  printf "db_password = 'my long pass phrase'\n" > "$IN"
  run vetdd_find_secrets x < "$IN"
  [ "$output" = "x:1: secret: assignment" ]
  printf '{"secret": "quoted in json value"}\n' > "$IN"
  run vetdd_find_secrets x < "$IN"
  [ "$output" = "x:1: secret: assignment" ]
}

@test "B2: a quoted placeholder with spaces is still not an assignment" {
  printf 'password: "your password here"\n' > "$IN"
  run vetdd_find_secrets x < "$IN"
  [ "$output" = "" ]
}

# pad_to <n>: n filler characters that match no kind.
pad_to() { awk -v n="$1" 'BEGIN { for (i = 0; i < n; i++) printf "." }'; }

@test "M2: an exempt shape cut by a window edge is still exempt (the context comes from the whole line)" {
  # Window 2 starts at 3585: put "sk-" there, right after "ta" (task-..., not an OpenAI key).
  printf '%s task-queue-worker-process-abcdefghijklmnopqrst %s\n' "$(pad_to 3581)" "$(pad_to 5000)" > "$IN"
  run vetdd_find_secrets x < "$IN"
  [ "$output" = "" ] || { echo "sk: $output"; false; }
  # Window 1 ends at 4096: cut an SSH remote right after its host.
  printf '%s git@github.com:org/repo.git %s\n' "$(pad_to 4081)" "$(pad_to 5000)" > "$IN"
  run vetdd_find_secrets x < "$IN"
  [ "$output" = "" ] || { echo "ssh: $output"; false; }
}

@test "P1: any printable ASCII written as \\u00XX is read back, so gh\\u0070_ is still a GitHub token" {
  printf '{"text":"gh\\u0070_%s"}\n' aB3dE5gH7jK9mN1pQ3sT5vW7yZ9bC1dE3fG5 > "$IN"
  run vetdd_find_secrets x < "$IN"
  [ "$output" = "x:1: secret: github-token" ]
  printf '{"html":"\\u003cb\\u003e \\u0026amp; \\u005c"}\n' > "$IN"
  run vetdd_find_secrets x < "$IN"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "P2: a JWT whose payload does not start with eyJ (a space after the brace) is found" {
  printf 'eyJhbGciOiJIUzI1NiJ9.eyAic3ViIjogIjEyMzQ1Njc4OTAifQ.c2lnbmF0dXJlLXZhbHVl\n' > "$IN"
  run vetdd_find_secrets x < "$IN"
  [ "$output" = "x:1: secret: jwt" ]
}
