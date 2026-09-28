#!/usr/bin/env bats
# check-blind.sh: flags forbidden words and model names in names and text contents below a directory.

load test_helper
load helpers/eval_fixtures

setup() {
  W="$BATS_TEST_TMPDIR/ws"
  mkdir -p "$W"
}

blind() { "$SCRIPTS/check-blind.sh" "$@"; }

@test "a clean directory exits 0 with no output; latest and attest are not whole-word hits" {
  mkdir -p "$W/src"
  printf 'the latest invoice\nwe attest to it\n' > "$W/src/notes.md"
  run blind "$W" --placed .
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "--profile judge ignores evaluation words but still flags model names and origin words" {
  mkdir -p "$W/c1/artifact"
  printf 'npm test\nit("closes on the 28th", ...)\n' > "$W/c1/artifact/diff.patch"
  run blind "$W" --profile judge
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  printf 'written by claude\n' > "$W/c1/artifact/notes.md"
  printf 'this is the baseline variant\n' > "$W/c1/artifact/origin.md"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [[ "$output" == *"c1/artifact/notes.md:1: claude"* ]]
  [[ "$output" == *"c1/artifact/origin.md:1: baseline"* ]]
  [[ "$output" == *"c1/artifact/origin.md:1: variant"* ]]
}

@test "a whole-word hit in contents prints path:line: word and exits 1" {
  printf 'first line\nimport x from "./test.ts"\n' > "$W/notes.md"
  run blind "$W" --placed .
  [ "$status" -eq 1 ]
  [ "$output" = "notes.md:2: test" ]
}

@test "matching is case-insensitive and accepts a plural s (Tests)" {
  printf 'Tests pass.\n' > "$W/a.md"
  run blind "$W" --placed .
  [ "$status" -eq 1 ]
  [ "$output" = "a.md:1: test" ]
}

@test "file and directory names are checked (foo.test.ts, tests/)" {
  mkdir -p "$W/tests"
  printf 'x\n' > "$W/tests/keep.txt"
  printf 'x\n' > "$W/foo.test.ts"
  run blind "$W" --placed .
  [ "$status" -eq 1 ]
  [[ "$output" == *"foo.test.ts:name: test"* ]]
  [[ "$output" == *"tests:name: test"* ]]
  [ "${#lines[@]}" -eq 2 ]
}

@test "every forbidden word from eval mode rule 1 is flagged" {
  printf 'eval judge experiment rubric score compare benchmark candidate arena variant baseline\n' > "$W/a.md"
  run blind "$W" --placed .
  [ "$status" -eq 1 ]
  for w in eval judge experiment rubric score compare benchmark candidate arena variant baseline; do
    [[ "$output" == *"a.md:1: $w"* ]]
  done
}

@test "model names are flagged, including the gpt- prefix" {
  printf 'written by Claude Opus 5\n' > "$W/a.md"
  printf 'model = "gpt-6-sol"\n' > "$W/b.toml"
  printf 'sonnet haiku fable codex grok anthropic openai\n' > "$W/c.txt"
  run blind "$W" --placed .
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.md:1: claude"* ]]
  [[ "$output" == *"a.md:1: opus"* ]]
  [[ "$output" == *"b.toml:1: gpt-"* ]]
  for w in sonnet haiku fable codex grok anthropic openai; do
    [[ "$output" == *"c.txt:1: $w"* ]]
  done
}

@test "--allow exempts matching relative paths and nothing else" {
  write_rubric "$W/rubric.md"
  mkdir -p "$W/c1/evidence/s1" "$W/c1/artifact"
  printf '{"cmd":["npm","test"]}\n' > "$W/c1/evidence/s1/meta.json"
  printf 'npm test\n' > "$W/c1/artifact/notes.md"
  run blind "$W" --placed . --allow 'rubric.md' --allow '*/evidence/*'
  [ "$status" -eq 1 ]
  [ "$output" = "c1/artifact/notes.md:1: test" ]
}

@test "--allow exemptions make an otherwise clean run directory pass" {
  write_rubric "$W/rubric.md"
  mkdir -p "$W/c1/evidence/s1" "$W/c1/artifact"
  printf '{"cmd":["npm","test"]}\n' > "$W/c1/evidence/s1/meta.json"
  printf '42\n' > "$W/c1/artifact/value.txt"
  run blind "$W" --placed . --allow 'rubric.md' --allow '*/evidence/*'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the candidate profile skips node_modules and .git directories and binary files" {
  mkdir -p "$W/node_modules/test" "$W/.git"
  printf 'test\n' > "$W/node_modules/test/index.js"
  printf 'ref: refs/heads/test\n' > "$W/.git/HEAD"
  printf 'test\000binary\n' > "$W/blob.bin"
  run blind "$W" --placed .
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "--extra-words adds words from a file (worktree or branch names)" {
  printf 'on branch fast-path in kata-app-1\n' > "$W/a.md"
  printf '# one per line\nkata-app-1\n\nfast-path\n' > "$BATS_TEST_TMPDIR/extra.txt"
  run blind "$W" --placed . --extra-words "$BATS_TEST_TMPDIR/extra.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.md:1: kata-app-1"* ]]
  [[ "$output" == *"a.md:1: fast-path"* ]]
}

@test "a missing directory is a usage error (exit 2)" {
  run blind "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 2 ]
}

# A copy of fixtures/ts-kata as a candidate would get it, under a neutral project name.
copy_kata() {
  K="$BATS_TEST_TMPDIR/work/${1:-invoice-app}"
  mkdir -p "${K%/*}"
  cp -R "$VETDD_ROOT/fixtures/ts-kata" "$K"
  rm -rf "$K/node_modules"
  TASK="$BATS_TEST_TMPDIR/work/request.md"
  printf 'Invoices closing on the 31st get the wrong due date in February. Please fix it.\n' > "$TASK"
}

@test "the candidate check passes an ordinary project with tests (fixtures/ts-kata under a neutral name)" {
  copy_kata
  run blind "$K"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run blind "$K" --file "$TASK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the candidate check fails on an evaluation word in the request file or in the workspace name" {
  copy_kata
  printf 'This is an eval of the closing rule.\n' >> "$TASK"
  run blind "$K" --file "$TASK"
  [ "$status" -eq 1 ]
  [ "$output" = "$TASK:2: eval" ]
  copy_kata eval-kata-1
  run blind "$K" --file "$TASK"
  [ "$status" -eq 1 ]
  [ "$output" = "eval-kata-1:name: eval" ]
}

@test "the candidate check covers the placed files, not the rest of the project" {
  copy_kata
  mkdir -p "$K/.claude/skills/closing-helper/notes"
  printf 'Keep the closing day rule.\n' > "$K/.claude/skills/closing-helper/SKILL.md"
  run blind "$K" --placed .claude/skills/closing-helper
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  printf 'The rubric rewards short answers.\n' > "$K/.claude/skills/closing-helper/notes/hint.md"
  printf 'x\n' > "$K/.claude/skills/closing-helper/notes/baseline.md"
  run blind "$K" --placed .claude/skills/closing-helper
  [ "$status" -eq 1 ]
  [[ "$output" == *".claude/skills/closing-helper/notes/hint.md:1: rubric"* ]]
  [[ "$output" == *".claude/skills/closing-helper/notes/baseline.md:name: baseline"* ]]
  [ "${#lines[@]}" -eq 2 ]
}

@test "a placed item's own name is checked; a placed path outside the directory is a usage error" {
  copy_kata
  mkdir -p "$K/.claude/skills/judge-helper"
  printf 'x\n' > "$K/.claude/skills/judge-helper/SKILL.md"
  run blind "$K" --placed .claude/skills/judge-helper
  [ "$status" -eq 1 ]
  [ "$output" = ".claude/skills/judge-helper:name: judge" ]
  run blind "$K" --placed ../request.md
  [ "$status" -eq 2 ]
  run blind "$K" --placed no/such/path
  [ "$status" -eq 2 ]
}

@test "the root directory's own name is checked for the candidate profile only" {
  mkdir -p "$BATS_TEST_TMPDIR/claude-kata/src"
  printf 'x\n' > "$BATS_TEST_TMPDIR/claude-kata/src/a.md"
  run blind "$BATS_TEST_TMPDIR/claude-kata"
  [ "$status" -eq 1 ]
  [ "$output" = "claude-kata:name: claude" ]
  mkdir -p "$BATS_TEST_TMPDIR/candidates/c1"
  run blind "$BATS_TEST_TMPDIR/candidates" --profile judge
  [ "$status" -eq 0 ]
}

@test "any symlink below the directory fails the check, in either profile" {
  mkdir -p "$W/c1/artifact"
  printf 'x\n' > "$W/c1/artifact/a.md"
  ln -s ../../../variants.json "$W/c1/artifact/link.json"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [ "$output" = "c1/artifact/link.json:symlink: not allowed" ]
  run blind "$W"
  [ "$status" -eq 1 ]
  [[ "$output" == *"c1/artifact/link.json:symlink: not allowed"* ]]
}

@test "G10: hits are reported without control characters from file names" {
  printf 'x\n' > "$W/$(printf 'claude\033[31mred')"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [[ "$output" != *$'\033'* ]]
}

# A UTF-8 locale other than C, or empty when the machine has none of them.
utf8_locale() {
  local l
  for l in ja_JP.UTF-8 ja_JP.utf8; do
    locale -a 2>/dev/null | grep -qx "$l" && { printf '%s\n' "$l"; return 0; }
  done
  return 0
}

@test "H5: the judge profile reports node_modules and .git as hits without reading them" {
  mkdir -p "$W/c1/artifact/node_modules/pkg" "$W/c1/artifact/.git"
  printf 'claude-opus variant-B\n' > "$W/c1/artifact/node_modules/pkg/index.js"
  printf '[remote "origin"]\n\turl = claude-opus\n' > "$W/c1/artifact/.git/config"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [[ "$output" == *"c1/artifact/node_modules:name: not allowed in a judge input"* ]]
  [[ "$output" == *"c1/artifact/.git:name: not allowed in a judge input"* ]]
  [ "${#lines[@]}" -eq 2 ]
}

@test "H5: the judge profile reports a file or a symlink named node_modules or .git" {
  mkdir -p "$W/c1" "$W/c2"
  printf 'gitdir: ../elsewhere\n' > "$W/c1/.git"
  ln -s ../elsewhere "$W/c2/node_modules"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [[ "$output" == *"c1/.git:name: not allowed in a judge input"* ]]
  [[ "$output" == *"c2/node_modules:name: not allowed in a judge input"* ]]
}

@test "H9: the candidate profile reports a symlink named node_modules or .git" {
  mkdir -p "$W/app"
  ln -s ../../elsewhere "$W/app/node_modules"
  ln -s ../../elsewhere "$W/app/.git"
  run blind "$W" --placed .
  [ "$status" -eq 1 ]
  [[ "$output" == *"app/node_modules:symlink: not allowed"* ]]
  [[ "$output" == *"app/.git:symlink: not allowed"* ]]
}

@test "H6: the judge profile reports a non-text file (NUL, UTF-16) as a hit; an empty file is not; --allow exempts it" {
  mkdir -p "$W/c1/artifact"
  printf 'written by opus\000\n' > "$W/c1/artifact/nul.txt"
  printf '\377\376o\000p\000u\000s\000\n\000' > "$W/c1/artifact/utf16.txt"
  : > "$W/c1/artifact/empty.txt"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [[ "$output" == *"c1/artifact/nul.txt:binary: not scanned"* ]]
  [[ "$output" == *"c1/artifact/utf16.txt:binary: not scanned"* ]]
  [ "${#lines[@]}" -eq 2 ]
  run blind "$W" --profile judge --allow '*/nul.txt' --allow '*/utf16.txt'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "H6: an invalid UTF-8 byte does not hide a hit under a UTF-8 locale" {
  local loc; loc="$(utf8_locale)"
  [ -n "$loc" ] || skip "no ja_JP UTF-8 locale on this machine"
  printf 'caf\351 by opus\n' > "$W/a.md"
  LC_ALL="$loc" run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [ "$output" = "a.md:1: opus" ]
}

@test "H6: vetdd_redact redacts past an invalid UTF-8 byte under a UTF-8 locale" {
  local loc; loc="$(utf8_locale)"
  [ -n "$loc" ] || skip "no ja_JP UTF-8 locale on this machine"
  printf 'opus\n' > "$BATS_TEST_TMPDIR/words"
  printf 'caf\351 by opus\n' > "$W/a.md"
  run env LC_ALL="$loc" bash -c '. "$1"; vetdd_redact "$2" "$3"' _ \
    "$SCRIPTS/lib/blind-words.sh" "$BATS_TEST_TMPDIR/words" "$W/a.md"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'caf\351 by [redacted]')" ]
}

# Secret-shaped values are assembled at run time so this file never holds one whole.
@test "H1: the judge profile flags private keys, tokens, and email addresses" {
  mkdir -p "$W/c1/artifact"
  {
    printf -- '-----BEGIN RSA %s KEY-----\n' PRIVATE
    printf 'k2 %s%s\n' AKIA ABCDEFGHIJ234567
    printf 'k3 %s_%s\n' ghp abcdefghijklmnopqrstuvwxyz0123456789
    printf 'k4 %s-%s\n' xoxb 1234567890-abcdefghij
    printf 'k5 %s-%s\n' sk proj-abcdefghijklmnopqrstuvwx
    printf 'k6 %s-%s\n' sk ant-api03-abcdefghijklmnopqrstu
    printf 'k7 %s.%s.%s\n' eyJhbGciOiJIUzI1NiJ9 eyJzdWIiOiIxMjM0NTY3ODkwIn0 sig
    printf 'k8 alice.smith@%s.co.jp\n' corp-mail
    printf 'k9 password = "%s"\n' hunter2hunter2
    printf 'k10 {\\"API_KEY\\": \\"%s\\"}\n' abcd1234efgh5678
    printf '{"k11":"hi\\nbob@%s.co.jp"}\n' corp-mail
  } > "$W/c1/artifact/leak.txt"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [ "$output" = "c1/artifact/leak.txt:1: secret: private-key
c1/artifact/leak.txt:2: secret: aws-key
c1/artifact/leak.txt:3: secret: github-token
c1/artifact/leak.txt:4: secret: slack-token
c1/artifact/leak.txt:5: secret: openai-key
c1/artifact/leak.txt:6: secret: anthropic-key
c1/artifact/leak.txt:7: secret: jwt
c1/artifact/leak.txt:8: secret: email
c1/artifact/leak.txt:9: secret: assignment
c1/artifact/leak.txt:10: secret: assignment
c1/artifact/leak.txt:11: secret: email" ]
  run blind "$W" --profile judge --allow '*/leak.txt'
  [ "$status" -eq 0 ]
}

@test "H1: placeholders, reserved domains, noreply addresses, and look-alikes are not secrets" {
  mkdir -p "$W/c1/artifact"
  {
    printf 'Co-Authored-By: Bot <noreply@%s.com>\n' vendor
    printf 'contact dev@example.com or ops@example.org\n'
    printf 'git config user.email dev@example.invalid\n'
    printf 'password: {{password}}\n'
    printf 'token=$GITHUB_TOKEN\n'
    printf 'api_key: <your key here>\n'
    printf 'secret = REDACTED_VALUE\n'
    printf 'token: xxxxxxxxxxxx\n'
    printf 'API_KEY=your-api-key-here\n'
    printf 'const token = getToken(request)\n'
    printf 'const token = req.headers.authorization\n'
    printf 'run task-abcdefghijklmnopqrstuvwxyz\n'
    printf 'max_tokens: 100000000\n'
    printf '{"text":"README.md\\n@notes.md and icon@2x.png"}\n'
  } > "$W/c1/artifact/notes.md"
  run blind "$W" --profile judge
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "H1: a --file is checked for secrets in either profile; the candidate's own tree is not" {
  printf 'reach me at alice.smith@%s.co.jp\n' corp-mail > "$BATS_TEST_TMPDIR/prompt.md"
  cp "$BATS_TEST_TMPDIR/prompt.md" "$W/CONTACT.md"
  run blind "$W" --placed . --file "$BATS_TEST_TMPDIR/prompt.md"
  [ "$status" -eq 1 ]
  [ "$output" = "$BATS_TEST_TMPDIR/prompt.md:1: secret: email" ]
  mkdir -p "$BATS_TEST_TMPDIR/j"
  run blind "$BATS_TEST_TMPDIR/j" --profile judge --file "$BATS_TEST_TMPDIR/prompt.md"
  [ "$status" -eq 1 ]
  [ "$output" = "$BATS_TEST_TMPDIR/prompt.md:1: secret: email" ]
}

@test "R1: a NUL byte after 100KB of text is still a non-text file in the judge profile" {
  mkdir -p "$W/c1/artifact"
  awk 'BEGIN { for (i = 0; i < 3000; i++) print "plain line of text that is fifty bytes long ....." }' \
    > "$W/c1/artifact/late.txt"
  [ "$(wc -c < "$W/c1/artifact/late.txt")" -gt 100000 ]
  printf '\000' >> "$W/c1/artifact/late.txt"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [ "$output" = "c1/artifact/late.txt:binary: not scanned" ]
}

@test "R1: vetdd_is_text (lib/text.sh) reads the whole file: late NUL, UTF-16, empty, text" {
  awk 'BEGIN { for (i = 0; i < 2000; i++) print "plain line of text that is fifty bytes long ....." }' > "$W/late"
  printf '\000' >> "$W/late"
  printf '\377\376o\000p\000' > "$W/utf16"
  : > "$W/empty"
  printf 'caf\351 ok\n' > "$W/latin1"
  is_text() { bash -c '. "$1"; vetdd_is_text "$2"' _ "$SCRIPTS/lib/text.sh" "$1"; }
  run is_text "$W/late";   [ "$status" -eq 1 ]
  run is_text "$W/utf16";  [ "$status" -eq 1 ]
  run is_text "$W/empty";  [ "$status" -eq 0 ]
  run is_text "$W/latin1"; [ "$status" -eq 0 ]
}

@test "R2: an assignment whose value is an identifier is not a secret" {
  mkdir -p "$W/c1/artifact"
  {
    printf 'res.json({ token: accessToken })\n'
    printf 'const user = { password: passwordHash }\n'
    printf '  token: AuthToken;\n'
    printf 'password = hashPassword\n'
    printf 'const authToken = process.env.NPM_TOKEN\n'
    printf '  authToken: string;\n'
    printf '_authToken=${NPM_TOKEN}\n'
  } > "$W/c1/artifact/code.ts"
  run blind "$W" --profile judge
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "R2: a quoted value or a 16+ character mix of letters and digits is still an assignment" {
  mkdir -p "$W/c1/artifact"
  {
    printf 'password: "%s"\n' hunter2hunter2
    printf 'api_key=%s\n' ab12cd34ef56gh78ij
  } > "$W/c1/artifact/conf.txt"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [ "$output" = "c1/artifact/conf.txt:1: secret: assignment
c1/artifact/conf.txt:2: secret: assignment" ]
}

@test "secret kinds: npm, GitHub PAT, Google API key, Stripe, GitLab, PGP private key, camelCase keys" {
  mkdir -p "$W/c1/artifact"
  {
    printf 'k1 %s_%s\n' npm abcdefghijklmnopqrstuvwxyz0123456789
    printf 'k2 %s_%s\n' github pat_11ABCDEFG0123456789_abcdefghij
    printf 'k3 %s%s\n' AIza SyA-abcdefghijklmnopqrstuvwxyz01234
    printf 'k4 %s_%s\n' sk live_abcdefghij0123456789
    printf 'k5 %s_%s\n' rk live_abcdefghij0123456789
    printf 'k6 %s-%s\n' glpat abcdefghij-0123456789
    printf -- '-----BEGIN PGP %s KEY BLOCK-----\n' PRIVATE
    printf 'const clientSecret = "%s"\n' s3cr3tvalue
    printf "  authToken: '%s',\n" abcdefghijkl
    printf '{"githubToken": "%s"}\n' q1w2e3r4t5y6
    printf '//registry.npmjs.org/:_authToken=%s\n' 0a1b2c3d-4e5f
  } > "$W/c1/artifact/leak.txt"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [ "$output" = "c1/artifact/leak.txt:1: secret: npm-token
c1/artifact/leak.txt:2: secret: github-pat
c1/artifact/leak.txt:3: secret: google-api-key
c1/artifact/leak.txt:4: secret: stripe-key
c1/artifact/leak.txt:5: secret: stripe-key
c1/artifact/leak.txt:6: secret: gitlab-token
c1/artifact/leak.txt:7: secret: private-key
c1/artifact/leak.txt:8: secret: assignment
c1/artifact/leak.txt:9: secret: assignment
c1/artifact/leak.txt:10: secret: assignment
c1/artifact/leak.txt:11: secret: assignment" ]
}

@test "secret kinds need a non-alphanumeric character before them" {
  mkdir -p "$W/c1/artifact"
  {
    printf 'x%s_%s\n' npm abcdefghijklmnopqrstuvwxyz0123456789
    printf 'x%s_%s\n' github pat_11ABCDEFG0123456789_abcdefghij
    printf 'x%s%s\n' AIza SyA-abcdefghijklmnopqrstuvwxyz01234
    printf 'x%s_%s\n' sk live_abcdefghij0123456789
    printf 'x%s-%s\n' glpat abcdefghij-0123456789
  } > "$W/c1/artifact/near.txt"
  run blind "$W" --profile judge
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "S1: an address at a ccTLD that is also a file extension (.md, .sh, .py, .rs, .pl) is an email" {
  mkdir -p "$W/c1/artifact"
  {
    printf 'write to person@%s.md\n' company
    printf 'write to person@%s.sh\n' startup
    printf 'write to person@%s.py\n' shop
    printf 'write to person@%s.rs\n' firma
    printf 'write to person@%s.pl\n' sklep
    printf '![logo](icon@2x.png)\n'
    printf 'import x from "pkg@1.2.3/index.js"\n'
    printf '<script src="bundle@1.0.0.min.js"></script>\n'
    printf '@import url(theme@dark.css);\n'
  } > "$W/c1/artifact/mail.txt"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [ "$output" = "c1/artifact/mail.txt:1: secret: email
c1/artifact/mail.txt:2: secret: email
c1/artifact/mail.txt:3: secret: email
c1/artifact/mail.txt:4: secret: email
c1/artifact/mail.txt:5: secret: email" ]
}

@test "S7: a token right after a JSON escape (\\n \\t \\r\\n \\u001b[0m \\u00e9) or an ANSI color code is found" {
  mkdir -p "$W/c1/artifact"
  {
    printf '{"type":"start"}\n'
    printf '{"text":"$ gh auth token\\n%s_%s"}\n' ghp abcdefghijklmnopqrstuvwxyz0123456789
    printf '{"text":"key:\\t%s-%s"}\n' sk ant-api03-abcdefghijklmnopqrstu
    printf '{"text":"out\\r\\n%s%s"}\n' AKIA ABCDEFGHIJ234567
    printf '{"text":"\\u001b[0m%s_%s"}\n' ghp abcdefghijklmnopqrstuvwxyz0123456789
    printf '\033[32m%s-%s\033[0m\n' sk proj-abcdefghijklmnopqrstuvwx
    printf '{"text":"caf\\u00e9%s-%s"}\n' sk proj-abcdefghijklmnopqrstuvwx
    printf 'log: \\033[1;31m%s%s\n' AKIA ABCDEFGHIJ234567
  } > "$W/c1/artifact/transcript.jsonl"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [ "$output" = "c1/artifact/transcript.jsonl:2: secret: github-token
c1/artifact/transcript.jsonl:3: secret: anthropic-key
c1/artifact/transcript.jsonl:4: secret: aws-key
c1/artifact/transcript.jsonl:5: secret: github-token
c1/artifact/transcript.jsonl:6: secret: openai-key
c1/artifact/transcript.jsonl:7: secret: openai-key
c1/artifact/transcript.jsonl:8: secret: aws-key" ]
}

@test "X2: a match that starts inside an exempt match is still found (mysecret_token = ...)" {
  mkdir -p "$W/c1/artifact"
  printf 'mysecret_token = "%s%s"\n' S3cr3t Value99 > "$W/c1/artifact/conf.txt"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [ "$output" = "c1/artifact/conf.txt:1: secret: assignment" ]
}

@test "assignment keys may go on after the key word with _ (aws_secret_access_key, auth_token), not glued (tokenizer)" {
  mkdir -p "$W/c1/artifact"
  {
    printf 'aws_secret_access_key = %s%s\n' ab12cd34ef56 gh78ij90kl12
    printf 'client_secret="%s"\n' s3cr3tvalue
    printf 'auth_token: "%s"\n' abcdefghijkl
    printf 'client_secret = clientSecretFromEnv\n'
    printf 'auth_token: authTokenValue\n'
    printf 'secret_name = mySecretName\n'
    printf 'tokenizer: "bert-base-uncased"\n'
    printf 'passwordless: "enabled-for-all"\n'
  } > "$W/c1/artifact/conf.txt"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [ "$output" = "c1/artifact/conf.txt:1: secret: assignment
c1/artifact/conf.txt:2: secret: assignment
c1/artifact/conf.txt:3: secret: assignment" ]
}

@test "secret kinds: a Bearer token (any case) and Stripe test keys" {
  mkdir -p "$W/c1/artifact"
  {
    printf 'curl -H "Authorization: Bearer %s%s"\n' abcdefghij 0123456789.ABC-def
    printf 'authorization: bearer %s%s\n' abc~def+ghi/jkl 0123456789
    printf 'k3 %s_%s\n' sk test_abcdefghij0123456789
    printf 'k4 %s_%s\n' rk test_abcdefghij0123456789
    printf 'Authorization: Bearer ${TOKEN}\n'
    printf 'Authorization: Bearer <token>\n'
    printf 'the bearer of this note is short123\n'
    printf 'x%s_%s\n' sk test_abcdefghij0123456789
  } > "$W/c1/artifact/leak.txt"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [ "$output" = "c1/artifact/leak.txt:1: secret: bearer-token
c1/artifact/leak.txt:2: secret: bearer-token
c1/artifact/leak.txt:3: secret: stripe-key
c1/artifact/leak.txt:4: secret: stripe-key" ]
}

@test "R3: an absolute path given as an extra word (/srv/x/runs/r1) matches inside a longer path" {
  mkdir -p "$W/c1"
  printf 'read /srv/x/runs/r1/c1/artifact/a.md\nread /srv/x/runs/r1b and /srv/x/runs/r\n' > "$W/c1/transcript.jsonl"
  printf '/srv/x/runs/r1\n' > "$BATS_TEST_TMPDIR/paths.txt"
  run blind "$W" --profile judge --extra-words "$BATS_TEST_TMPDIR/paths.txt"
  [ "$status" -eq 1 ]
  [ "$output" = "c1/transcript.jsonl:1: /srv/x/runs/r1" ]
}

@test "a library in lib/ that fails to load is a usage error, not a clean pass" {
  local s="$BATS_TEST_TMPDIR/scripts"
  cp -R "$SCRIPTS" "$s"
  printf 'vetdd_is_text() {\n' > "$s/lib/text.sh"
  printf 'plain\n' > "$W/a.md"
  run "$s/check-blind.sh" "$W" --profile judge
  [ "$status" -eq 2 ]
  [[ "$output" == *"vetdd_is_text is not defined"* ]]
}

@test "a matcher that fails is exit 2, never a clean result" {
  mkdir -p "$BATS_TEST_TMPDIR/fakebin" "$BATS_TEST_TMPDIR/cands/c1"
  printf 'opus wrote this\n' > "$BATS_TEST_TMPDIR/cands/c1/notes.md"
  printf '#!/bin/sh\necho "awk: broken on purpose" >&2\nexit 2\n' > "$BATS_TEST_TMPDIR/fakebin/awk"
  chmod +x "$BATS_TEST_TMPDIR/fakebin/awk"
  run env PATH="$BATS_TEST_TMPDIR/fakebin:$PATH" "$VETDD_ROOT/skills/vetdd/scripts/check-blind.sh" "$BATS_TEST_TMPDIR/cands" --profile judge
  [ "$status" -eq 2 ]
}

# --allow-secrets: test data that looks like a secret, exempted by path from the secret check only.
@test "S2: --allow-secrets skips only the secret check for matching paths; words, names, and binaries are still checked" {
  mkdir -p "$W/c1/artifact/tests"
  {
    printf 'const who = "qa.person@%s.co.jp"\n' acme
    printf 'password: "%s"\n' correct-horse
    printf 'generated by claude\n'
  } > "$W/c1/artifact/tests/fixture.ts"
  printf 'bin\000ary' > "$W/c1/artifact/tests/blob.dat"
  printf 'owner ops.lead@%s.co.jp\n' acme > "$W/c1/artifact/notes.md"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [[ "$output" == *"c1/artifact/tests/fixture.ts:1: secret: email"* ]]
  [[ "$output" == *"c1/artifact/tests/fixture.ts:2: secret: assignment"* ]]
  run blind "$W" --profile judge --allow-secrets 'c1/artifact/tests/*'
  [ "$status" -eq 1 ]
  [[ "$output" == *"c1/artifact/tests/fixture.ts:3: claude"* ]]
  [[ "$output" == *"c1/artifact/tests/blob.dat:binary: not scanned"* ]]
  [[ "$output" == *"c1/artifact/notes.md:1: secret: email"* ]]
  [[ "$output" != *"fixture.ts:1: secret"* ]]
  [[ "$output" != *"fixture.ts:2: secret"* ]]
  [ "${#lines[@]}" -eq 3 ]
}

@test "S2: --allow-secrets matches a --file by the path as given" {
  mkdir -p "$BATS_TEST_TMPDIR/j"
  printf 'reach qa.person@%s.co.jp\n' acme > "$BATS_TEST_TMPDIR/cond.md"
  run blind "$BATS_TEST_TMPDIR/j" --profile judge --file "$BATS_TEST_TMPDIR/cond.md" --allow-secrets 'cond.md'
  [ "$status" -eq 1 ]
  run blind "$BATS_TEST_TMPDIR/j" --profile judge --file "$BATS_TEST_TMPDIR/cond.md" --allow-secrets "$BATS_TEST_TMPDIR/cond.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  printf 'by opus\n' >> "$BATS_TEST_TMPDIR/cond.md"
  run blind "$BATS_TEST_TMPDIR/j" --profile judge --file "$BATS_TEST_TMPDIR/cond.md" --allow-secrets '*/cond.md'
  [ "$status" -eq 1 ]
  [ "$output" = "$BATS_TEST_TMPDIR/cond.md:2: opus" ]
  run blind "$BATS_TEST_TMPDIR/j" --profile judge --allow-secrets
  [ "$status" -eq 2 ]
}

@test "T2: an SSH git remote (scp form, ssh://) is not an email; mailto:, lists, and address-then-colon still are" {
  mkdir -p "$W/c1/artifact"
  {
    printf 'origin\tgit@%s:org/repo.git (fetch)\n' github.com
    printf 'git clone ssh://git@%s/x\n' gitlab.corp-host.org
    printf '"url": "git@%s:team/app.git"\n' bitbucket.org
    printf 'git+ssh://git@%s/org/repo.git\n' github.com
    printf '[mail](mailto:alice@%s)\n' corp.io
    printf 'cc alice@%s, bob@%s\n' corp.io corp.io
    printf 'reach alice@%s: any time\n' corp.io
    printf 'alice@%s\n' corp.io
  } > "$W/c1/artifact/remotes.txt"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [ "$output" = "c1/artifact/remotes.txt:5: secret: email
c1/artifact/remotes.txt:6: secret: email
c1/artifact/remotes.txt:7: secret: email
c1/artifact/remotes.txt:8: secret: email" ]
}

@test "T3: the judge profile checks file and directory names for secrets; --allow-secrets skips them; the candidate profile does not" {
  local tok
  tok="$(printf '%s_%s' ghp abcdefghijklmnopqrstuvwxyz0123456789)"
  mkdir -p "$W/c1/artifact/$tok-dir"
  printf 'plain\n' > "$W/c1/artifact/$tok.txt"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [[ "$output" == *"c1/artifact/$tok.txt:name: secret: github-token"* ]]
  [[ "$output" == *"c1/artifact/$tok-dir:name: secret: github-token"* ]]
  [ "${#lines[@]}" -eq 2 ]
  run blind "$W" --profile judge --allow-secrets "c1/artifact/$tok.txt"
  [ "$status" -eq 1 ]
  [ "$output" = "c1/artifact/$tok-dir:name: secret: github-token" ]
  run blind "$W" --profile judge --allow-secrets 'c1/artifact/*'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run blind "$W" --placed .
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "secret kinds: credentials in a URL and an Authorization: Basic header; placeholders and short values are not" {
  mkdir -p "$W/c1/artifact"
  {
    printf 'DATABASE_URL=postgres://app:%s%s@localhost:5432/db\n' S3c ret99
    printf 'redis://:%s%s@cache:6379\n' hunter2 hunter2
    printf 'curl -H "Authorization: Basic %s%s"\n' YWxhZGRpbjpv cGVuc2VzYW1l
    printf '{\\"headers\\":{\\"authorization\\":\\"basic %s%s\\"}}\n' dXNlcm5hbWU6 cGFzc3dvcmQ=
    printf 'postgres://app:${DB_PASSWORD}@localhost/db\n'
    printf 'postgres://app:$DB_PASSWORD@localhost/db\n'
    printf 'postgres://app:<password>@localhost/db\n'
    printf 'postgres://app:[redacted]@localhost/db\n'
    printf 'postgres://app:***@localhost/db\n'
    printf 'http://localhost:8080/pkg@1.2.3\n'
    printf 'postgres://app@localhost:5432/db\n'
    printf 'Authorization: Basic <base64>\n'
    printf 'Authorization: Basic %s\n' dXNlcjpwYXNz
    printf 'the basic idea is simple enough for everyone\n'
  } > "$W/c1/artifact/conf.txt"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [ "$output" = "c1/artifact/conf.txt:1: secret: url-credentials
c1/artifact/conf.txt:2: secret: url-credentials
c1/artifact/conf.txt:3: secret: basic-auth
c1/artifact/conf.txt:4: secret: basic-auth" ]
}

@test "W1: an address then :password is an email; only an scp-form remote (~/, /, name/, name.git) is not" {
  mkdir -p "$W/c1/artifact"
  {
    printf 'alice@%s:%s\n' corp.io S3cretPass
    printf 'curl -u alice@%s:%s https://api.%s\n' corp.io hunter2secret corp.io
    printf 'git@%s:org/repo.git\n' github.com
    printf 'git@%s:org/repo\n' github.com
    printf 'deploy@%s:~/app\n' host.corp.io
    printf 'git@%s:/srv/repo.git\n' gitlab.corp.io
    printf 'git@%s:repo.git\n' gitlab.corp.io
    printf 'bob@%s:repo.gitlab\n' corp.io
  } > "$W/c1/artifact/remotes.txt"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [ "$output" = "c1/artifact/remotes.txt:1: secret: email
c1/artifact/remotes.txt:2: secret: email
c1/artifact/remotes.txt:8: secret: email" ]
}

@test "W2: a quoted value is an assignment even with a dot or a parenthesis; placeholders still are not" {
  mkdir -p "$W/c1/artifact"
  {
    printf 'password: "%s"\n' john.smith2024
    printf '"api_key": "%s"\n' corp.prod.k3y9x
    printf 'secret = "%s"\n' 'Pa(ss)w0rd99'
    printf 'password: "%s"\n' '{{ vault.password }}'
    printf 'token = "%s"\n' '${process.env.TOKEN}'
    printf 'api_key: "%s"\n' '<your-api-key>'
  } > "$W/c1/artifact/conf.txt"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [ "$output" = "c1/artifact/conf.txt:1: secret: assignment
c1/artifact/conf.txt:2: secret: assignment
c1/artifact/conf.txt:3: secret: assignment" ]
}

@test "U1: --allow-secrets <glob>:<kind> drops only that kind for the path; other kinds and paths are still reported" {
  local tok
  tok="$(printf '%s_%s' ghp abcdefghijklmnopqrstuvwxyz0123456789)"
  mkdir -p "$W/c1"
  {
    printf '{"text":"signed in as qa.person@%s.co.jp"}\n' acme
    printf '{"text":"export GH=%s"}\n' "$tok"
    printf '{"text":"password: \\"%s\\""}\n' correct-horse
  } > "$W/c1/transcript.jsonl"
  printf 'owner ops.lead@%s.co.jp\n' acme > "$W/c1/notes.md"
  run blind "$W" --profile judge --allow-secrets 'c1/transcript.jsonl:email'
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | LC_ALL=C sort)" = "c1/notes.md:1: secret: email
c1/transcript.jsonl:2: secret: github-token
c1/transcript.jsonl:3: secret: assignment" ]
  run blind "$W" --profile judge --allow-secrets 'c1/transcript.jsonl:email,assignment' --allow-secrets '*.md:email'
  [ "$status" -eq 1 ]
  [ "$output" = "c1/transcript.jsonl:2: secret: github-token" ]
  run blind "$W" --profile judge --allow-secrets 'c1/transcript.jsonl:email' --allow-secrets 'c1/*:github-token,assignment' \
    --allow-secrets 'c1/notes.md'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "U1: --allow-secrets with a kind applies to a --file and to the names' secret check" {
  local tok
  tok="$(printf '%s_%s' ghp abcdefghijklmnopqrstuvwxyz0123456789)"
  mkdir -p "$W/c1/artifact"
  printf 'plain\n' > "$W/c1/artifact/$tok.txt"
  run blind "$W" --profile judge --allow-secrets "c1/artifact/$tok.txt:email"
  [ "$status" -eq 1 ]
  [ "$output" = "c1/artifact/$tok.txt:name: secret: github-token" ]
  run blind "$W" --profile judge --allow-secrets "c1/artifact/*:github-token"
  [ "$status" -eq 0 ]
  rm "$W/c1/artifact/$tok.txt"
  {
    printf 'reach qa.person@%s.co.jp\n' acme
    printf 'aws %s%s\n' AKIA ABCDEFGHIJKLMNOP
  } > "$BATS_TEST_TMPDIR/cond.md"
  run blind "$W" --profile judge --file "$BATS_TEST_TMPDIR/cond.md" --allow-secrets '*/cond.md:email'
  [ "$status" -eq 1 ]
  [ "$output" = "$BATS_TEST_TMPDIR/cond.md:2: secret: aws-key" ]
}

@test "U1: an unknown or empty kind after ':' is a usage error (exit 2), never an allow-everything" {
  mkdir -p "$W/c1"
  printf 'owner ops.lead@%s.co.jp\n' acme > "$W/c1/notes.md"
  local v
  for v in 'c1/notes.md:emial' 'c1/notes.md:' 'c1/notes.md:email,' 'c1/notes.md:email,,jwt' ':email' \
           'c1/notes.md:assignment-camel' 'c1/notes.md:Email'; do
    run blind "$W" --profile judge --allow-secrets "$v"
    [ "$status" -eq 2 ] || { echo "not a usage error: $v ($status)"; return 1; }
    [[ "$output" == *"--allow-secrets"* ]]
  done
  run blind "$W" --profile judge --allow-secrets 'c1/notes.md:emial'
  [[ "$output" == *"emial"* ]]
}

@test "U1: every kind in VETDD_SECRET_KINDS is accepted, and the list names exactly the reported kinds" {
  mkdir -p "$W/c1"
  local k kinds
  kinds="$(bash -c '. "$1"; printf "%s" "$VETDD_SECRET_KINDS"' _ "$SCRIPTS/lib/secret-patterns.sh")"
  [ "$(printf '%s\n' $kinds | wc -l | tr -d ' ')" -eq 17 ]
  for k in $kinds; do
    run blind "$W" --profile judge --allow-secrets "c1/*:$k"
    [ "$status" -eq 0 ] || { echo "rejected: $k"; return 1; }
  done
  # A pattern whose kind is missing from the list makes the matcher fail (exit 2), not pass.
  run bash -c '. "$1"; VETDD_SECRET_KINDS="${VETDD_SECRET_KINDS% assignment}"; printf "x\n" | vetdd_find_secrets f' _ "$SCRIPTS/lib/secret-patterns.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"assignment is not in VETDD_SECRET_KINDS"* ]]
}

@test "Z3: a FIFO or other special file is a hit in the judge profile (the judge would hang reading it)" {
  mkdir -p "$W/c1/artifact"
  mkfifo "$W/c1/artifact/pipe"
  run blind "$W" --profile judge
  [ "$status" -eq 1 ]
  [ "$output" = "c1/artifact/pipe:special: not allowed in a judge input" ]
}
