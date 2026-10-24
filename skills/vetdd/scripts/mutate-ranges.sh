#!/usr/bin/env bash
# Print the value for StrykerJS's --mutate: the lines a slice added or changed, in current line numbers.
# Usage: mutate-ranges.sh <slice-id> [--file <path>]...
#   npx --no-install stryker run <config> --mutate "$(mutate-ranges.sh <slice>)"
# Prints one line, `file:a-b,file:c-d` (each range a run of contiguous lines; one line is `a-a`), with
# paths relative to the current directory, where Stryker runs.
# The lines are attributed with git blame, not a diff from a base: three throwaway commits are made,
# c0 of the tree of the slice's first `before` run, c1 of the tree of its last accepted `after` run with
# outcome pass (parent c0), and c2 of the working tree now (parent c1, with untracked files, as
# evidence.sh hashes it), and the lines `git blame c2` gives to c1 are the slice's. So a later slice or
# a refactor moves them without adding its own lines (blame -w -M -C: a line only moved, reindented,
# or moved to another file named with --file stays the slice's), and two slices in one file each get
# only their own. The commits are never referenced by a ref (unreachable objects); HEAD, the index, and the
# working tree are not touched.
# Without --file: every file the slice changed except its oracle files (every oracle file its evidence
# names) and .vetdd/. --file (relative to the current directory, repeatable) limits the output to
# the files named, in that order; name a file's new path with it when a later change moved the file.
# The ranges are the changed lines only: widening them to whole statements stays with the caller
# (modes/test.md, Audits › Mutation). A file the slice deleted, or in which it only removed lines,
# has nothing to mutate: it is named on stderr and left out, as is a changed file outside the current
# directory. A path Stryker would split or read as a pattern (a comma, : * ? [ ] { } ( ) \, a leading
# !), one a shell reads (' " ` $ ; & | < >), or one with a control, bidirectional, or zero-width
# character is refused (exit 2), so the value is safe inside single quotes.
# Exit 0 when ranges were printed; 2 on usage errors and when the evidence cannot be attributed (no
# before run, no passing after, a tree object git gc removed); 3 when there is nothing to mutate
# (nothing printed: a slice that changed only its oracle files, or no line of the slice is left).
set -u

unset CDPATH
. "${BASH_SOURCE[0]%/*}/lib/common.sh"
. "${BASH_SOURCE[0]%/*}/lib/tree-hash.sh"

say() { printf 'mutate-ranges.sh: %s\n' "$1" | vetdd_printable >&2; }
die() { say "$1"; exit 2; }

vetdd_require_jq mutate-ranges.sh

usage="usage: mutate-ranges.sh <slice-id> [--file <path>]..."
[ $# -ge 1 ] || die "$usage"
slice="$1"; shift
vetdd_is_slice_id "$slice" || die "invalid slice id (letters, digits, . _ -; starting with a letter or digit)"
file_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --file) [ $# -ge 2 ] || die "--file needs a path"; file_args+=("$2"); shift 2 ;;
    *) die "unexpected argument '$1' ($usage)$(vetdd_split_hint "$1")" ;;
  esac
done

root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
root="$(cd "$root" && pwd -P)" || die "cannot enter the repository root"
prefix="$(git rev-parse --show-prefix)" || die "cannot read the current directory inside the repository"

rel=".vetdd/evidence/$slice/meta.json"
vetdd_inside_repo "$root" "$rel" || die "$rel is a symbolic link or outside the repository"
for c in "$root/.vetdd" "$root/.vetdd/evidence" "$root/.vetdd/evidence/$slice"; do
  [ ! -L "$c" ] || die "${c#"$root"/} is a symbolic link"
done
meta="$root/$rel"
[ -f "$meta" ] || die "slice '$slice' has no evidence ($rel); record its before and after runs with evidence.sh first"
jq -e --arg s "$slice" '(.slice_id == $s) and (.runs | type == "array") and all(.runs[]; type == "object")' \
  "$meta" >/dev/null 2>&1 || die "$rel is not valid evidence for slice '$slice'"

# tree_of <jq filter of a run> first|last: "<tree hash> <seq>" of the first or last run it selects, empty when none (check_tree checks the hash).
tree_of() {
  local t
  t="$(jq -r "[.runs[] | select($1)] | $2 | if . == null then \"\" else (.tree.tree_hash | tostring) + \" \" + (.seq | tostring) end" "$meta")" \
    || die "cannot read the runs of $rel"
  printf '%s\n' "$t"
}
check_tree() {  # <hash> <run description>
  case "$1" in
    *[!0-9a-f]*|'') die "the $2 of slice '$slice' has no usable tree hash; record the run again with evidence.sh" ;;
  esac
  [ ${#1} -eq 40 ] || [ ${#1} -eq 64 ] || die "the $2 of slice '$slice' has no usable tree hash; record the run again with evidence.sh"
  [ "$(git -C "$root" cat-file -t "$1" 2>/dev/null)" = tree ] \
    || die "tree $1 of the $2 of slice '$slice' is not in the repository (removed by git gc?): its lines cannot be attributed"
}
run0="$(tree_of '.kind == "before"' 'first')" || exit 2
read -r t0 s0 <<EOF
$run0
EOF
[ -n "${s0:-}" ] || die "slice '$slice' has no before run: nothing to attribute the lines against"
run1="$(tree_of '.kind == "after" and .accepted != false and .outcome == "pass"' 'last')" || exit 2
read -r t1 s1 <<EOF
$run1
EOF
[ -n "${s1:-}" ] || die "slice '$slice' has no accepted after run with outcome pass: its change is not on file"
check_tree "$t0" "before run (run $s0)"
check_tree "$t1" "after run (run $s1)"

# Every oracle file the evidence names, of any version: tests are not mutated.
oracles=()
while IFS= read -r p; do oracles+=("$p"); done < <(jq -r '[.oracle.files[]?.path, .runs[].oracle.files[]?.path]
  | map(strings) | unique | .[]' "$meta")
is_oracle() {
  local o
  for o in ${oracles[@]+"${oracles[@]}"}; do [ "$o" = "$1" ] && return 0; done
  return 1
}

# --file paths, resolved to repository-relative ones before anything is made.
files=()
for f in ${file_args[@]+"${file_args[@]}"}; do
  case "$f" in -*) f="./$f" ;; esac  # dirname would read it as an option
  [ -f "$f" ] && [ ! -L "$f" ] || die "--file: not a regular file: $f$(vetdd_split_hint "$f")"
  fdir="$(cd "$(dirname -- "$f")" && pwd -P)" || die "--file: cannot enter the directory of $f"
  abs="$fdir/$(vetdd_disk_name "$fdir" "$f")"
  case "$abs" in
    "$root"/*) r="$(vetdd_disk_path "$root" "${abs#"$root"/}")" ;;
    *) die "--file: outside the repository: $f" ;;
  esac
  vetdd_inside_repo "$root" "$r" || die "--file: a symbolic link or outside the repository: $f"
  case "$r" in .vetdd/*) die "--file: $r is under .vetdd/, which is not product code" ;; esac
  is_oracle "$r" && die "--file: $r is an oracle file of slice '$slice'; tests are not mutated"
  dup=0
  for g in ${files[@]+"${files[@]}"}; do [ "$g" = "$r" ] && dup=1; done
  [ "$dup" -eq 1 ] || files+=("$r")
done

cd "$root" || die "cannot enter the repository root"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/vetdd-ranges.XXXXXX")" || die "cannot create a temporary directory"
trap 'rm -rf "$tmp"' EXIT

t2="$(vetdd_tree_hash "$root")" || die "could not hash the working tree"

# throwaway <commit-tree arguments>: an unsigned commit with a fixed identity and date, so it needs no
# git identity, never asks for a signature, and the same trees give the same commits.
throwaway() {
  GIT_AUTHOR_NAME=vetdd GIT_AUTHOR_EMAIL=vetdd@invalid GIT_AUTHOR_DATE='1000000000 +0000' \
  GIT_COMMITTER_NAME=vetdd GIT_COMMITTER_EMAIL=vetdd@invalid GIT_COMMITTER_DATE='1000000000 +0000' \
    git -c commit.gpgsign=false commit-tree --no-gpg-sign "$@" < /dev/null
}
c0="$(throwaway -m "vetdd mutate-ranges $slice: before (run $s0)" "$t0")" || die "could not make the before commit"
c1="$(throwaway -p "$c0" -m "vetdd mutate-ranges $slice: after (run $s1)" "$t1")" || die "could not make the after commit"
c2="$(throwaway -p "$c1" -m "vetdd mutate-ranges $slice: working tree" "$t2")" || die "could not make the working-tree commit"

# mode_in <tree-ish> <path>: the entry's mode, empty when the path is not in it.
mode_in() {
  git --literal-pathspecs ls-tree -z --full-tree "$1" -- "$2" > "$tmp/ls" || return 1
  [ -s "$tmp/ls" ] || return 0
  cut -d' ' -f1 < "$tmp/ls" | head -n 1
}

# The files the slice changed (c0 to c1), without its oracle files and .vetdd/.
git diff-tree -r -z --no-renames --raw "$t0" "$t1" > "$tmp/changed" || die "could not compare the slice's trees"
product=0
changed=()
while IFS= read -r -d '' rec && IFS= read -r -d '' p; do
  case "$p" in .vetdd/*) continue ;; esac
  is_oracle "$p" && continue
  product=$((product + 1))
  read -r _ nmode _ _ st <<EOF
$rec
EOF
  case "$st" in
    D) say "$p: the slice deleted it, so there is nothing to mutate there" ;;
    *) case "$nmode" in
         100644|100755) changed+=("$p") ;;
         *) say "$p: not a regular file in the slice's tree (a symbolic link or a submodule): left out" ;;
       esac ;;
  esac
done < "$tmp/changed"

if [ "$product" -eq 0 ]; then
  [ "$t0" != "$t1" ] || say "the before run (run $s0) and the after run (run $s1) of slice '$slice' recorded the same tree"
  say "slice '$slice' changed no product file (only its oracle files): there is nothing to mutate; record why with audit-note.sh $slice --kind mutation --not-applicable --reason-file <path> (modes/test.md, Audits › Mutation: a slice that only adds tests)"
  exit 3
fi

if [ ${#files[@]} -gt 0 ]; then
  for r in "${files[@]}"; do
    case "$(mode_in "$c2" "$r")" in
      100644|100755) ;;
      *) die "--file: $r is not in the working tree as evidence.sh hashes it (gitignored?)" ;;
    esac
  done
  targets=("${files[@]}")
else
  targets=(${changed[@]+"${changed[@]}"})
fi

# A path Stryker reads safely: its --mutate is split at commas, a range is the last :a-b, and the
# file part is a minimatch pattern (a leading ! negates it). A path that a shell would read (a quote,
# $, ;, &, |, <, >) is refused too, so the value can be pasted into a quoted command line, and so is
# one with a character that hides or reorders text (bidirectional controls, zero-width characters).
stryker_safe() {
  case "$1" in
    *,*) die "$1: the path holds a comma, which splits Stryker's --mutate list; rename the file or mutate it on its own config" ;;
    *:*|*\**|*\?*|*\[*|*\]*|*\{*|*\}*|*\(*|*\)*|*\\*|!*) die "$1: Stryker reads the file part of --mutate as a glob pattern (: * ? [ ] { } ( ) \\ and a leading ! are special); rename the file or name it in the Stryker config" ;;
    *\'*|*\"*|*\`*|*\$*|*\;*|*\&*|*\|*|*\<*|*\>*) die "$1: the path holds a character a shell reads (' \" \` \$ ; & | < >); rename the file" ;;
  esac
  # By byte: C0 and DEL, the UTF-8 C1 controls, U+200B-U+200F, U+202A-U+202E, U+2066-U+2069.
  printf '%s' "$1" | LC_ALL=C grep -q -e "$(printf '[\001-\037\177]')" -e "$(printf '\302[\200-\237]')" \
      -e "$(printf '\342\200[\213-\217\252-\256]')" -e "$(printf '\342\201[\246-\251]')" \
    && die "$(printf '%s' "$1" | LC_ALL=C tr -c '[:print:]' '?'): the path holds a control, bidirectional, or zero-width character (shown as ?); rename it"
  return 0
}

out=""
for r in ${targets[@]+"${targets[@]}"}; do
  shown="$r"
  if [ -n "$prefix" ]; then
    case "$r" in
      "$prefix"*) shown="${r#"$prefix"}" ;;
      *) say "$r: outside the current directory, below which Stryker mutates: left out (run from the repository root to include it)"; continue ;;
    esac
  fi
  case "$(mode_in "$c2" "$r")" in
    100644|100755) ;;
    '') say "$r: the slice changed it, but it is no longer in the working tree at this path (moved or deleted since); name its current path with --file"; continue ;;
    *) say "$r: no longer a regular file: left out"; continue ;;
  esac
  git blame --porcelain --no-textconv --no-ignore-revs-file -w -M -C "$c2" -- "$r" > "$tmp/blame" 2> "$tmp/blame.err" \
    || die "git blame failed on $r: $(head -n 1 "$tmp/blame.err")"
  ranges="$(awk -v c="$c1" '
    substr($0, 1, 1) == "\t" { next }
    $1 == c && NF >= 3 {
      n = $3 + 0
      if (have && n == last + 1) { last = n }
      else { if (have) printf "%d-%d\n", first, last; first = n; last = n; have = 1 }
    }
    END { if (have) printf "%d-%d\n", first, last }' "$tmp/blame")" || die "could not read the blame of $r"
  if [ -z "$ranges" ]; then
    say "$r: no line the slice added or changed is in it now (it only removed lines, or later edits replaced them): nothing to mutate there"
    continue
  fi
  stryker_safe "$shown"
  while IFS= read -r g; do out="${out:+$out,}$shown:$g"; done <<EOF
$ranges
EOF
done

if [ -z "$out" ]; then
  say "no line of slice '$slice' to mutate in the files above; if that is right, record why with audit-note.sh $slice --kind mutation --not-applicable --reason-file <path> (modes/test.md, Audits › Mutation)"
  exit 3
fi
printf '%s\n' "$out"
