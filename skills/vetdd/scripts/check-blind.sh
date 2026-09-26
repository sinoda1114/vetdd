#!/usr/bin/env bash
# Check that a directory reveals nothing a blinded reader must not see (modes/eval.md, rule 1).
# Usage: check-blind.sh <dir> [--profile candidate|judge] [--placed <rel>]... [--file <path>]...
#                       [--extra-words <file>]... [--allow <glob>]...
# Words: the lists in lib/blind-words.sh, case-insensitive and whole-word ("latest" does not match
# "test"; "test.ts" and "Tests" do). What is scanned depends on the profile:
#   --profile candidate (default)  what the eval harness exposes to a candidate, not the ordinary
#                         project files: the name of <dir> itself (the workspace name), every
#                         --placed item (its own name, the names below it, and its text contents),
#                         and every --file. Words: evaluation words + model names.
#   --profile judge       every name and text file below <dir>, plus every --file.
#                         Words: origin words (variant, baseline, winner) + model names.
#   --placed <rel>        a file or directory the eval placed in the workspace, relative to <dir>
#                         (e.g. .claude/skills/<name>); "." scans everything below <dir>
#   --file <path>         also scan this text file's contents (task.md, the rendered prompt);
#                         it may live outside <dir> and is reported by the path as given
#   --extra-words <file>  more words, one per line (# comments allowed): worktree, branch, variant names
#   --allow <glob>        skip paths (relative to <dir>) matching a shell glob; "*" crosses "/"
#                         e.g. --allow 'rubric.md' --allow '*/evidence/*'
# In every profile, any symlink below <dir> is a hit: a link can reach outside the copy.
# Binaries, node_modules, and .git are skipped.
# Output: one "path:line: word" line per hit ("path:name: word" for a file or directory name,
# "path:symlink: not allowed" for a symlink).
# Exit: 0 clean, 1 any hit, 2 usage error.
set -u

. "${BASH_SOURCE[0]%/*}/lib/common.sh"
die() { printf 'check-blind.sh: %s\n' "$1" | vetdd_printable >&2; exit 2; }

. "${BASH_SOURCE[0]%/*}/lib/blind-words.sh"

dir=""; extra_files=(); allow=(); profile="candidate"; placed=(); files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --extra-words) [ $# -ge 2 ] || die "--extra-words needs a file"; extra_files+=("$2"); shift 2 ;;
    --allow) [ $# -ge 2 ] || die "--allow needs a glob"; allow+=("$2"); shift 2 ;;
    --profile) [ $# -ge 2 ] || die "--profile needs candidate or judge"; profile="$2"; shift 2 ;;
    --placed) [ $# -ge 2 ] || die "--placed needs a path"; placed+=("$2"); shift 2 ;;
    --file) [ $# -ge 2 ] || die "--file needs a path"; files+=("$2"); shift 2 ;;
    -*) die "unknown option '$1'" ;;
    *) [ -z "$dir" ] || die "only one directory is allowed"; dir="$1"; shift ;;
  esac
done
[ -n "$dir" ] || die "usage: check-blind.sh <dir> [--profile candidate|judge] [--placed <rel>]... [--file <path>]... [--extra-words <file>]... [--allow <glob>]..."
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

is_allowed() {
  local g
  for g in ${allow[@]+"${allow[@]}"}; do
    # shellcheck disable=SC2254 # the glob is meant to match
    case "$1" in $g) return 0 ;; esac
  done
  return 1
}

hits=0
report() {
  [ -n "$1" ] || return 0
  printf '%s\n' "$1" | vetdd_printable
  hits=$((hits + 1))
}

# scan_name <label> <name>; scan_text <label> <file>
scan_name() { report "$(printf '%s\n' "$2" | vetdd_find_words "$words" "$1" name)"; }
scan_text() {
  grep -Iq . "$2" 2>/dev/null || return 0
  report "$(vetdd_find_words "$words" "$1" "" < "$2")"
}

# scan_tree <start> <mindepth>: names and text contents of <start> (at mindepth 0) and below it.
scan_tree() {
  local path rel
  while IFS= read -r -d '' path; do
    rel="${path#"$dir"/}"
    is_allowed "$rel" && continue
    scan_name "$rel" "${rel##*/}"
    [ ! -f "$path" ] || [ -L "$path" ] || scan_text "$rel" "$path"
  done < <(find "$1" -mindepth "$2" \( -name node_modules -o -name .git \) -prune -o -print0)
}

# Symlinks, in every profile.
while IFS= read -r -d '' path; do
  report "${path#"$dir"/}:symlink: not allowed"
done < <(find "$dir" -mindepth 1 \( -name node_modules -o -name .git \) -prune -o -type l -print0)

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
  scan_text "$f" "$f"
done

[ "$hits" -eq 0 ] || exit 1
exit 0
