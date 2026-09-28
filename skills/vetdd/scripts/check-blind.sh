#!/usr/bin/env bash
# Check that a directory reveals nothing a blinded reader must not see (modes/eval.md, rule 1).
# Usage: check-blind.sh <dir> [--profile candidate|judge] [--placed <rel>]... [--file <path>]...
#                       [--extra-words <file>]... [--allow <glob>]...
#                       [--allow-secrets <glob>[:<kind>[,<kind>]...]]...
# Words: the lists in lib/blind-words.sh, case-insensitive and whole-word ("latest" does not match
# "test"; "test.ts" and "Tests" do). What is scanned depends on the profile:
#   --profile candidate (default)  what the eval harness exposes to a candidate, not the ordinary
#                         project files: the name of <dir> itself (the workspace name), every
#                         --placed item (its own name, the names below it, and its text contents),
#                         and every --file. Words: evaluation words + model names.
#   --profile judge       every name and text file below <dir>, plus every --file.
#                         Words: origin words (variant, baseline, winner) + model names.
#                         Also a hit: an entry named node_modules or .git (file, directory, or
#                         symlink; its contents are not read), a non-empty file that is not text
#                         (NUL bytes, UTF-16), and a secret-shaped string (lib/secret-patterns.sh:
#                         keys, tokens, email addresses) in a text file or in a file or directory
#                         name.
#   --placed <rel>        a file or directory the eval placed in the workspace, relative to <dir>
#                         (e.g. .claude/skills/<name>); "." scans everything below <dir>
#   --file <path>         also scan this text file's contents (task.md, the rendered prompt),
#                         for secrets too in either profile; it may live outside <dir> and is
#                         reported by the path as given
#   --extra-words <file>  more words, one per line (# comments allowed): worktree, branch, variant names
#   --allow <glob>        skip paths (relative to <dir>) matching a shell glob; "*" crosses "/"
#                         e.g. --allow 'rubric.md' --allow '*/evidence/*'. It is also the only
#                         way to exempt a non-text file (by path).
#   --allow-secrets <glob>[:<kind>[,<kind>]...]
#                         skip only the secret check for paths matching the glob (the same rules as
#                         --allow; a --file is matched by the path as given): for test data a human
#                         has confirmed (an address or a password in a fixture); that covers the
#                         names' secret check too. With kinds after the last ":" (the names in
#                         VETDD_SECRET_KINDS, lib/secret-patterns.sh: email, assignment, ...), only
#                         those kinds are dropped there and the others are still reported
#                         (transcript.jsonl:email); an unknown or empty kind is a usage error, never
#                         an allow-everything. Without kinds every kind is dropped, so name the kinds
#                         a human confirmed. Words (in names too), non-text files, and symlinks are
#                         still checked there.
# In every profile, any symlink below <dir> is a hit: a link can reach outside the copy (one named
# node_modules or .git too). The candidate profile skips non-text files and the node_modules and
# .git directories. Files are read byte-wise (LC_ALL=C), so no locale hides a hit.
# Output: one "path:line: word" line per hit ("path:name: word" for a file or directory name,
# "path:symlink: not allowed" for a symlink, "path:line: secret: <kind>" for a secret
# ("path:name: secret: <kind>" in a name),
# "path:binary: not scanned" and "path:name: not allowed in a judge input" in the judge profile).
# Exit: 0 clean, 1 any hit, 2 usage error.
set -u
unset CDPATH  # `cd dir` must never resolve through CDPATH or print a path

. "${BASH_SOURCE[0]%/*}/lib/common.sh"
die() { printf 'check-blind.sh: %s\n' "$1" | vetdd_printable >&2; exit 2; }

. "${BASH_SOURCE[0]%/*}/lib/blind-words.sh"
. "${BASH_SOURCE[0]%/*}/lib/secret-patterns.sh"
. "${BASH_SOURCE[0]%/*}/lib/text.sh"
# A library that failed to load would leave its matcher undefined, and every scan would pass.
for fn in vetdd_word_file vetdd_find_words vetdd_find_secrets vetdd_is_text; do
  declare -F "$fn" >/dev/null || die "internal error: $fn is not defined (a library in lib/ failed to load)"
done
[ -n "${VETDD_SECRET_KINDS:-}" ] || die "internal error: VETDD_SECRET_KINDS is not set (lib/secret-patterns.sh failed to load)"

# allow_secrets[i] is a glob; allow_secret_kinds[i] is "all" or the space-separated kinds it drops.
dir=""; extra_files=(); allow=(); allow_secrets=(); allow_secret_kinds=(); profile="candidate"; placed=(); files=()
# add_allow_secrets <value>: parse <glob> or <glob>:<kind>[,<kind>]... into the two arrays.
add_allow_secrets() {
  local v="$1" err
  err="$(vetdd_allow_secret_error "$v")" || die "$err"
  case "$v" in
    *:*) allow_secrets+=("${v%:*}"); allow_secret_kinds+=("$(printf '%s' "${v##*:}" | tr ',' ' ')") ;;
    *) allow_secrets+=("$v"); allow_secret_kinds+=(all) ;;
  esac
}
while [ $# -gt 0 ]; do
  case "$1" in
    --extra-words) [ $# -ge 2 ] || die "--extra-words needs a file"; extra_files+=("$2"); shift 2 ;;
    --allow) [ $# -ge 2 ] || die "--allow needs a glob"; allow+=("$2"); shift 2 ;;
    --allow-secrets) [ $# -ge 2 ] || die "--allow-secrets needs a glob"; add_allow_secrets "$2"; shift 2 ;;
    --profile) [ $# -ge 2 ] || die "--profile needs candidate or judge"; profile="$2"; shift 2 ;;
    --placed) [ $# -ge 2 ] || die "--placed needs a path"; placed+=("$2"); shift 2 ;;
    --file) [ $# -ge 2 ] || die "--file needs a path"; files+=("$2"); shift 2 ;;
    -*) die "unknown option '$1'" ;;
    *) [ -z "$dir" ] || die "only one directory is allowed"; dir="$1"; shift ;;
  esac
done
[ -n "$dir" ] || die "usage: check-blind.sh <dir> [--profile candidate|judge] [--placed <rel>]... [--file <path>]... [--extra-words <file>]... [--allow <glob>]... [--allow-secrets <glob>[:<kind>[,<kind>]...]]..."
[ -d "$dir" ] || die "not a directory: $dir"
dir="${dir%/}"

# The candidate profile hides the evaluation itself; the judge profile hides only origins and models.
case "$profile" in
  candidate) base_words="$VETDD_FORBIDDEN_WORDS $VETDD_MODEL_WORDS" ;;
  judge)
    base_words="$VETDD_ORIGIN_WORDS $VETDD_MODEL_WORDS"
    [ "${#placed[@]}" -eq 0 ] || die "--placed is for the candidate profile; the judge profile scans everything" ;;
  *) die "unknown profile '$profile' (candidate or judge)" ;;
esac
for p in ${placed[@]+"${placed[@]}"}; do
  case "$p" in
    /*|..|../*|*/..|*/../*) die "--placed must be a path inside $dir: $p" ;;
  esac
  [ -e "$dir/$p" ] || [ -L "$dir/$p" ] || die "placed path not found: $dir/$p"
done
for f in ${files[@]+"${files[@]}"}; do
  [ -f "$f" ] || die "file not found: $f"
done

work="$(mktemp -d "${TMPDIR:-/tmp}/vetdd-blind.XXXXXX")" || die "cannot create a temporary directory"
trap 'rm -rf "$work"' EXIT
words="$work/words"
extra_words=()
for f in ${extra_files[@]+"${extra_files[@]}"}; do
  [ -f "$f" ] || die "extra words file not found: $f"
  while IFS= read -r w || [ -n "$w" ]; do extra_words+=("$w"); done < "$f"
done
# shellcheck disable=SC2086 # the default lists are space-separated words
vetdd_word_file "$words" $base_words ${extra_words[@]+"${extra_words[@]}"}
[ -s "$words" ] || die "cannot build the word list (awk, sort, or cut failed)"

# matches_any <path> <glob>...: 0 when the path matches one of the globs ("*" crosses "/").
matches_any() {
  local p="$1" g
  shift
  for g in "$@"; do
    # shellcheck disable=SC2254 # the glob is meant to match
    case "$p" in $g) return 0 ;; esac
  done
  return 1
}
is_allowed() { matches_any "$1" ${allow[@]+"${allow[@]}"}; }
# secret_skip <path>: the secret kinds --allow-secrets drops for the path: "" (none), "all", or a
# space-separated list of kinds.
secret_skip() {
  local i=0 skip=""
  while [ "$i" -lt "${#allow_secrets[@]}" ]; do
    if matches_any "$1" "${allow_secrets[$i]}"; then
      [ "${allow_secret_kinds[$i]}" != all ] || { echo all; return 0; }
      skip="$skip ${allow_secret_kinds[$i]}"
    fi
    i=$((i + 1))
  done
  echo "${skip# }"
}

hits=0
report() {
  [ -n "$1" ] || return 0
  printf '%s\n' "$1" | vetdd_printable
  hits=$((hits + 1))
}

# scan_name <label> <name>
# matched <matcher> <args...>: report what a matcher prints. A matcher that fails (awk missing or
# broken, a word file gone) stops the check with exit 2; it is never read as "no hits".
matched() {
  local out
  out="$("$@")" || die "a matcher failed ($1); nothing below $dir was checked"
  report "$out"
}
name_words() { printf '%s\n' "$3" | vetdd_find_words "$1" "$2" name; }
scan_name() { matched name_words "$words" "$1" "$2"; }
name_secrets() { printf '%s\n' "$2" | vetdd_find_secrets "$1" name "$3"; }
text_words() { vetdd_find_words "$1" "$2" "" < "$3"; }
text_secrets() { vetdd_find_secrets "$1" "" "$3" < "$2"; }
# scan_text <label> <file> <skip>: words, and secrets except the kinds in <skip> (secret_skip; "all"
# checks none). A file that is not text (vetdd_is_text: a NUL byte anywhere in it, so UTF-16 too) is
# skipped, and is a hit in the judge profile unless it is empty.
scan_text() {
  if ! vetdd_is_text "$2"; then
    [ "$profile" != judge ] || [ ! -s "$2" ] || report "$1:binary: not scanned"
    return 0
  fi
  matched text_words "$words" "$1" "$2"
  [ "$3" = all ] || matched text_secrets "$1" "$2" "$3"
}

# scan_tree <start> <mindepth>: names and text contents of <start> (at mindepth 0) and below it.
# The judge profile reports an entry named node_modules or .git without reading below it; the
# candidate profile skips those directories (a symlink of that name is reported as a symlink).
scan_tree() {
  local path rel skip
  while IFS= read -r -d '' path; do
    rel="${path#"$dir"/}"
    is_allowed "$rel" && continue
    skip=all
    [ "$profile" != judge ] || skip="$(secret_skip "$rel")"
    if [ "$profile" = judge ]; then
      case "${rel##*/}" in
        node_modules|.git) report "$rel:name: not allowed in a judge input"; continue ;;
      esac
      # A FIFO, socket, or device: reading it could block the judge forever.
      [ -f "$path" ] || [ -d "$path" ] || [ -L "$path" ] \
        || { report "$rel:special: not allowed in a judge input"; continue; }
    fi
    scan_name "$rel" "${rel##*/}"
    # Names are checked for secrets only in the judge profile: a token-shaped name would reach the judge.
    [ "$skip" = all ] || matched name_secrets "$rel" "${rel##*/}" "$skip"
    [ ! -f "$path" ] || [ -L "$path" ] || scan_text "$rel" "$path" "$skip"
  done < <(if [ "$profile" = judge ]; then
             find "$1" -mindepth "$2" \( -name node_modules -o -name .git \) -prune -print0 -o -print0
           else
             find "$1" -mindepth "$2" -type d \( -name node_modules -o -name .git \) -prune -o -print0
           fi)
}

# Symlinks, in every profile; only a real node_modules or .git directory is not descended into.
while IFS= read -r -d '' path; do
  report "${path#"$dir"/}:symlink: not allowed"
done < <(find "$dir" -mindepth 1 -type d \( -name node_modules -o -name .git \) -prune -o -type l -print0)

if [ "$profile" = judge ]; then
  scan_tree "$dir" 1
else
  root="$(cd "$dir" && pwd)" || die "cannot enter $dir"
  scan_name "${root##*/}" "${root##*/}"
  for p in ${placed[@]+"${placed[@]}"}; do
    p="${p#./}"
    while [ "${p%/}" != "$p" ]; do p="${p%/}"; done
    case "$p" in
      .|"") scan_tree "$dir" 1 ;;
      *) scan_tree "$dir/$p" 0 ;;
    esac
  done
fi
for f in ${files[@]+"${files[@]}"}; do
  scan_text "$f" "$f" "$(secret_skip "$f")"
done

[ "$hits" -eq 0 ] || exit 1
exit 0
