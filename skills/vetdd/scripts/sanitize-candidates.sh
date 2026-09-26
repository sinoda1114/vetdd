#!/usr/bin/env bash
# Copy one candidate workspace into a judge-ready, origin-free label directory (modes/eval.md, step 5).
# Usage: sanitize-candidates.sh --src <workspace> --label <cN> --dest <run-dir>/candidates
#                               [--strip <word>]... [--variants <variants.json>] [--transcript <file>]
#   <dest>/<label>/artifact/          the workspace without .git, node_modules, and .vetdd
#   <dest>/<label>/evidence/          the workspace's .vetdd/evidence, when present
#   <dest>/<label>/transcript.jsonl   a copy of --transcript, when given
# Every case-insensitive, whole-word occurrence of a strip word (the same boundaries check-blind.sh
# uses) in text contents, file names, and directory names under <dest>/<label> becomes "[redacted]".
# Strip words: the model names in lib/blind-words.sh, the workspace's basename, its git branch when
# the workspace is a repository root, every variant name (the values) in --variants, and every
# --strip word. A strip word must have at least 4 characters, and main, master, HEAD, and git's
# init.defaultBranch are never strip words (an explicit one is refused, a derived one skipped).
# The source must not contain a symlink (outside .git and node_modules); it is refused, not copied.
# Rerunning replaces <dest>/<label>. Prints <dest>/<label>.
# Exit: 0 done, 1 copy or rewrite failed, 2 usage error (including a refused source or strip word).
set -u

. "${BASH_SOURCE[0]%/*}/lib/common.sh"
die() { printf 'sanitize-candidates.sh: %s\n' "$1" | vetdd_printable >&2; exit "${2:-2}"; }

. "${BASH_SOURCE[0]%/*}/lib/blind-words.sh"

MIN_STRIP_LEN=4

src=""; label=""; dest=""; strip=(); variants=""; transcript=""
while [ $# -gt 0 ]; do
  case "$1" in
    --src) [ $# -ge 2 ] || die "--src needs a value"; src="$2"; shift 2 ;;
    --label) [ $# -ge 2 ] || die "--label needs a value"; label="$2"; shift 2 ;;
    --dest) [ $# -ge 2 ] || die "--dest needs a value"; dest="$2"; shift 2 ;;
    --strip) [ $# -ge 2 ] || die "--strip needs a value"; strip+=("$2"); shift 2 ;;
    --variants) [ $# -ge 2 ] || die "--variants needs a file"; variants="$2"; shift 2 ;;
    --transcript) [ $# -ge 2 ] || die "--transcript needs a file"; transcript="$2"; shift 2 ;;
    *) die "unexpected argument '$1'" ;;
  esac
done
[ -n "$src" ] && [ -n "$label" ] && [ -n "$dest" ] \
  || die "usage: sanitize-candidates.sh --src <workspace> --label <cN> --dest <dir> [--strip <word>]... [--variants <file>] [--transcript <file>]"
case "$label" in c[0-9]*) ;; *) die "invalid label '$label' (c1, c2, ...)" ;; esac
case "${label#c}" in ""|*[!0-9]*) die "invalid label '$label' (c followed by digits: c1, c2, ...)" ;; esac
[ -d "$src" ] || die "workspace not found: $src"
if [ -n "$transcript" ]; then
  [ ! -L "$transcript" ] || die "the transcript is a symlink; pass the file itself: $transcript"
  [ -f "$transcript" ] || die "transcript not found: $transcript"
fi

src_abs="$(cd "$src" && pwd -P)" || die "cannot enter $src"
mkdir -p "$dest" || die "cannot create $dest"
dest_abs="$(cd "$dest" && pwd -P)" || die "cannot enter $dest"
case "$dest_abs/" in "$src_abs"/*) die "--dest must be outside the workspace" ;; esac
out="${dest%/}/$label"

[ ! -L "$src_abs/.vetdd" ] || die ".vetdd is a symlink; the evidence must be a directory inside the workspace"
# A symlink can point outside the workspace; copying it would carry the target, or the link, into
# the judge's input. Refuse instead of guessing.
links="$(
  find "$src_abs" \( -name .git -o -name node_modules -o -name .vetdd \) -prune -o -type l -print
  [ ! -e "$src_abs/.vetdd/evidence" ] && [ ! -L "$src_abs/.vetdd/evidence" ] \
    || find "$src_abs/.vetdd/evidence" -type l -print
)"
if [ -n "$links" ]; then
  msg="the workspace contains symlinks; replace them with regular files first:"
  while IFS= read -r l; do msg="$msg
  ${l#"$src_abs"/}"; done <<< "$links"
  die "$msg"
fi

# Words that must never be stripped: redacting them would mangle ordinary git text.
default_branch="$(git config --get init.defaultBranch 2>/dev/null || true)"
is_protected() {
  local w
  w="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
  case "$w" in main|master|head) return 0 ;; esac
  [ -n "$default_branch" ] && [ "$w" = "$(printf '%s' "$default_branch" | tr 'A-Z' 'a-z')" ]
}
# check_strip <word> <where>: refuse a word that is protected or too short.
check_strip() {
  ! is_protected "$1" || die "refusing to strip '$1' ($2): main, master, HEAD, and init.defaultBranch are never strip words"
  [ "${#1}" -ge "$MIN_STRIP_LEN" ] \
    || die "refusing to strip '$1' ($2): strip words need at least $MIN_STRIP_LEN characters"
}

for w in ${strip[@]+"${strip[@]}"}; do check_strip "$w" "--strip"; done
if [ -n "$variants" ]; then
  [ -f "$variants" ] || die "variants file not found: $variants"
  command -v jq >/dev/null 2>&1 || die "jq is required for --variants but not found"
  names="$(jq -r 'if type == "object" and all(.[]; type == "string" and (test("\n") | not))
                  then .[] else error("must be an object of one-line variant names") end' "$variants" 2>&1)" \
    || die "invalid variants file $variants: $names"
  while IFS= read -r w; do
    [ -z "$w" ] && continue
    check_strip "$w" "variant name in $variants"
    strip+=("$w")
  done <<< "$names"
fi
# Derived words: the workspace basename, its branch (only when src is the repository root).
base="${src_abs##*/}"
is_protected "$base" || { check_strip "$base" "the workspace name; rename the workspace"; strip+=("$base"); }
if [ "$(git -C "$src_abs" rev-parse --show-toplevel 2>/dev/null)" = "$src_abs" ]; then
  branch="$(git -C "$src_abs" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [ -n "$branch" ] && ! is_protected "$branch"; then
    check_strip "$branch" "the workspace's branch; rename the branch"
    strip+=("$branch")
  fi
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/vetdd-strip.XXXXXX")" || die "cannot create a temporary directory" 1
trap 'rm -rf "$work"' EXIT
words="$work/words"
# shellcheck disable=SC2086 # the default list is space-separated words
vetdd_word_file "$words" $VETDD_MODEL_WORDS ${strip[@]+"${strip[@]}"}

rm -rf "${dest_abs:?}/$label"
mkdir -p "$out/artifact" || die "cannot create $out/artifact" 1
# pipefail, so a file the archiver cannot read fails the copy instead of leaving it short.
( set -o pipefail
  (cd "$src_abs" && tar --exclude .git --exclude node_modules --exclude .vetdd -cf - .) \
    | (cd "$out/artifact" && tar -xf -) ) || die "copying $src failed" 1
if [ -d "$src_abs/.vetdd/evidence" ]; then
  cp -R "$src_abs/.vetdd/evidence" "$out/evidence" || die "copying the evidence failed" 1
fi
if [ -n "$transcript" ]; then
  cp "$transcript" "$out/transcript.jsonl" || die "copying the transcript failed" 1
fi

# Contents: text files only, rewritten in place (mode kept) only when something changed.
while IFS= read -r -d '' f; do
  grep -Iq . "$f" 2>/dev/null || continue
  vetdd_redact "$words" "$f" > "$work/redacted"
  case $? in
    0) cat "$work/redacted" > "$f" || die "cannot rewrite $f" 1 ;;
    3) ;;
    *) die "redacting $f failed" 1 ;;
  esac
done < <(find "$out" -type f -print0)

# Names: deepest first, so a parent is renamed after its children.
while IFS= read -r -d '' p; do
  base="${p##*/}"
  printf '%s\n' "$base" > "$work/name"
  new="$(vetdd_redact "$words" "$work/name")"
  case $? in 0) ;; 3) continue ;; *) die "redacting the name $p failed" 1 ;; esac
  [ ! -e "${p%/*}/$new" ] || die "cannot rename $p: ${p%/*}/$new exists" 1
  mv "$p" "${p%/*}/$new" || die "cannot rename $p" 1
done < <(find "$out" -mindepth 1 -depth -print0)

printf '%s\n' "$out"
