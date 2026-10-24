#!/usr/bin/env bash
# Print the value for StrykerJS's --mutate: the lines a slice added or changed, in current line numbers.
# Usage: mutate-ranges.sh <slice-id> [--file <path>]...
#   npx --no-install stryker run <config> --mutate "$(mutate-ranges.sh <slice>)"
# Prints one line, `file:a-b,file:c-d` (each range a run of contiguous lines; one line is `a-a`), with
# paths relative to the current directory, where Stryker runs.
# The lines are attributed with git blame, not a diff from a base, over a chain of throwaway commits:
# for each oracle version of the slice in seq order, the tree of the version's earliest run (the first
# `before`; for a later version, its red calibration), then the tree of its first accepted passing
# `after`; last the working tree now (with untracked files, as evidence.sh hashes it). The lines
# `git blame` gives to an `after` commit are the slice's; lines that arrived between versions or since
# are not, and an `after` recorded again within a version moves nothing. A slice without a `before`
# (a refactor, a behavior-preserving change) has one step, its first passing `after` to its last. So a
# later slice or a refactor moves the lines without adding its own (blame -w -M -C: a line only moved,
# reindented, or moved to another file named with --file stays the slice's), and two slices in one
# file each get only their own. The commits are never referenced by a ref (unreachable objects);
# HEAD, the index, and the working tree are not touched.
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
# before run and fewer than two passing afters, no passing after after the red, a tree object git gc
# removed); 3 when there is nothing to mutate (nothing printed: a slice that changed only its oracle
# files, or no line of the slice is left).
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

# The segments that bound the slice's own change, one "<start tree> <start seq> <end tree> <end seq>"
# line each, in seq order. With a before: one per oracle version, from the version's earliest run (the
# first before for the first version, the red calibration for a later one) to its first accepted
# passing after; a version with no such after yet has none. Without a before (a refactor or a
# behavior-preserving slice): one, from the first accepted passing after to the last. A first line
# "none" or "nobefore" says why there is none.
segments="$(jq -r '
  def ok: .kind == "after" and .accepted != false and .outcome == "pass";
  def ver: .oracle.version | tojson;
  def line($s; $e): "\($s.tree.tree_hash | tostring) \($s.seq | tostring) \($e.tree.tree_hash | tostring) \($e.seq | tostring)";
  (.runs | sort_by(.seq)) as $r
  | ([$r[] | select(.kind == "before")] | first) as $b
  | if $b == null then
      [$r[] | select(ok)] as $a
      | if ($a | length) < 2 then "nobefore" else line($a[0]; $a[-1]) end
    else
      [$r[] | select(.seq >= $b.seq)] as $rs
      | (reduce ($rs[] | ver) as $v ([]; if any(.[]; . == $v) then . else . + [$v] end)) as $vs
      | [ $vs[] as $v
          | (if $v == ($b | ver) then $b else ([$rs[] | select(ver == $v)] | first) end) as $start
          | ([$rs[] | select(ok and ver == $v and .seq > $start.seq)] | first) as $end
          | select($end != null) | line($start; $end) ]
      | if length == 0 then "none" else .[] end
    end' "$meta")" || die "cannot read the runs of $rel"
case "$segments" in
  nobefore) die "slice '$slice' has no before run and fewer than two passing after runs: a slice without a before (a refactor, a behavior-preserving change) needs a passing after before its change and another after it" ;;
  none) die "slice '$slice' has no accepted after run with outcome pass after its red: its change is not on file" ;;
esac
check_tree() {  # <hash> <run description>
  case "$1" in
    *[!0-9a-f]*|'') die "the $2 of slice '$slice' has no usable tree hash; record the run again with evidence.sh" ;;
  esac
  [ ${#1} -eq 40 ] || [ ${#1} -eq 64 ] || die "the $2 of slice '$slice' has no usable tree hash; record the run again with evidence.sh"
  [ "$(git -C "$root" cat-file -t "$1" 2>/dev/null)" = tree ] \
    || die "tree $1 of the $2 of slice '$slice' is not in the repository (removed by git gc?): its lines cannot be attributed"
}
seg_start=(); seg_sseq=(); seg_end=(); seg_eseq=()
while read -r st ss et es; do
  check_tree "$st" "run $ss"
  check_tree "$et" "run $es"
  seg_start+=("$st"); seg_sseq+=("$ss"); seg_end+=("$et"); seg_eseq+=("$es")
done <<EOF
$segments
EOF

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
# The chain start_1 -> end_1 -> start_2 -> end_2 -> ... -> the working tree. A line blamed on an end
# commit changed inside a red-to-green of the slice; one that arrived between them (another slice, a
# merge) is blamed on a start commit, and one added since on the last commit.
parent=(); ends=""
i=0
while [ "$i" -lt ${#seg_start[@]} ]; do
  c="$(throwaway ${parent[@]+"${parent[@]}"} -m "vetdd mutate-ranges $slice: start (run ${seg_sseq[$i]})" "${seg_start[$i]}")" \
    || die "could not make a throwaway commit"
  c="$(throwaway -p "$c" -m "vetdd mutate-ranges $slice: end (run ${seg_eseq[$i]})" "${seg_end[$i]}")" \
    || die "could not make a throwaway commit"
  ends="$ends $c"; parent=(-p "$c"); i=$((i + 1))
done
c2="$(throwaway "${parent[@]}" -m "vetdd mutate-ranges $slice: working tree" "$t2")" || die "could not make the working-tree commit"

# mode_in <tree-ish> <path>: the entry's mode, empty when the path is not in it.
mode_in() {
  git --literal-pathspecs ls-tree -z --full-tree "$1" -- "$2" > "$tmp/ls" || return 1
  [ -s "$tmp/ls" ] || return 0
  cut -d' ' -f1 < "$tmp/ls" | head -n 1
}

# The files the slice changed (each start to its end), without its oracle files and .vetdd/; a path
# changed in several segments counts once, with the status of its last change.
: > "$tmp/changed"
same=1
i=0
while [ "$i" -lt ${#seg_start[@]} ]; do
  [ "${seg_start[$i]}" = "${seg_end[$i]}" ] || same=0
  git diff-tree -r -z --no-renames --raw "${seg_start[$i]}" "${seg_end[$i]}" >> "$tmp/changed" \
    || die "could not compare the slice's trees"
  i=$((i + 1))
done
product=0
cpath=(); cstat=(); cmode=()
while IFS= read -r -d '' rec && IFS= read -r -d '' p; do
  case "$p" in .vetdd/*) continue ;; esac
  is_oracle "$p" && continue
  read -r _ nmode _ _ st <<EOF
$rec
EOF
  j=0; found=-1
  while [ "$j" -lt ${#cpath[@]} ]; do [ "${cpath[$j]}" = "$p" ] && found=$j; j=$((j + 1)); done
  if [ "$found" -ge 0 ]; then cstat[$found]="$st"; cmode[$found]="$nmode"
  else cpath+=("$p"); cstat+=("$st"); cmode+=("$nmode"); product=$((product + 1)); fi
done < "$tmp/changed"
changed=()
j=0
while [ "$j" -lt ${#cpath[@]} ]; do
  p="${cpath[$j]}"
  case "${cstat[$j]}" in
    D) say "$p: the slice deleted it, so there is nothing to mutate there" ;;
    *) case "${cmode[$j]}" in
         100644|100755) changed+=("$p") ;;
         *) say "$p: not a regular file in the slice's tree (a symbolic link or a submodule): left out" ;;
       esac ;;
  esac
  j=$((j + 1))
done
# One order whatever the segments: by byte, as git sorts paths.
if [ ${#changed[@]} -gt 1 ]; then
  sorted=()
  while IFS= read -r -d '' p; do sorted+=("$p"); done < <(printf '%s\0' "${changed[@]}" | LC_ALL=C sort -z)
  changed=("${sorted[@]}")
fi

if [ "$product" -eq 0 ]; then
  [ "$same" -eq 0 ] || say "each red-to-green of slice '$slice' recorded the same tree at its start and its end"
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
  ranges="$(awk -v ends="$ends" '
    BEGIN { n = split(ends, e, " "); for (k = 1; k <= n; k++) mine[e[k]] = 1 }
    substr($0, 1, 1) == "\t" { next }
    NF >= 3 && ($1 in mine) {
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
