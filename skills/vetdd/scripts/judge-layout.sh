#!/usr/bin/env bash
# Build the final judge's directory that references/final-judge-rubric.md "Layout" defines (test and
# verify modes, Close), so it is never assembled by hand.
# Usage: judge-layout.sh --out <dir> --reply <file> --base <git ref> <slice-id>...
#   <dir>/c1/artifact/diff.patch          git diff --no-ext-diff --binary <base> on the working tree, with
#                                         untracked files outside .vetdd/ added through a temporary index
#                                         (the repository's own index is never touched)
#   <dir>/c1/artifact/reply.md            the reply draft (<file>)
#   <dir>/c1/artifact/check-evidence.txt  check-evidence.sh <slices>, then a last line "exit <code>"
#   <dir>/c1/artifact/tests/<path>        each file in the slices' oracle.files, as it is now
#   <dir>/c1/evidence/<slice>/meta.json   each slice's record
#   <dir>/c1/evidence/<slice>/runs/...    its red-run logs (accepted before or calibration runs that ended
#                                         target_failure, the undefined-imports audit included) and the
#                                         copy of its latest usable mutation report; green logs stay here
# Every copied text file has the repository's absolute path replaced with <repo>; then
# check-blind.sh --profile judge runs on <dir>. Run it after check-evidence, on the delivered tree.
# Exit 0 built (it prints the judge.sh command); 1 a local step failed; 2 usage error (nothing is
# written); 4 the result is not blind (check-blind.sh's hits are printed; <dir> is left to inspect).
set -u
unset CDPATH

die() { printf 'judge-layout.sh: %s\n' "$1" >&2; exit "${2:-2}"; }

here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
. "$here/lib/common.sh"
vetdd_require_jq judge-layout.sh
. "$here/lib/tree-hash.sh"

out=""; reply=""; base=""; slices=()
while [ $# -gt 0 ]; do
  case "$1" in
    --out) [ $# -ge 2 ] || die "--out needs a directory"; out="$2"; shift 2 ;;
    --reply) [ $# -ge 2 ] || die "--reply needs a file"; reply="$2"; shift 2 ;;
    --base) [ $# -ge 2 ] || die "--base needs a git ref"; base="$2"; shift 2 ;;
    -*) die "unknown option: $(printf '%s' "$1" | vetdd_printable)" ;;
    *) slices+=("$1"); shift ;;
  esac
done
[ -n "$out" ] && [ -n "$reply" ] && [ -n "$base" ] && [ ${#slices[@]} -gt 0 ] \
  || die "usage: judge-layout.sh --out <dir> --reply <file> --base <git ref> <slice-id>..."
[ -f "$reply" ] && [ ! -L "$reply" ] || die "--reply must be a regular file"
[ ! -e "$out" ] && [ ! -L "$out" ] || die "--out $out exists; give a new directory"

root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
root="$(cd "$root" && pwd -P)"
# The spellings the repository's path can take in a log: its physical path, the same without a /private
# prefix (macOS links /var, /tmp, and /etc there), and the logical path the caller's shell shows.
prefix="$(git rev-parse --show-prefix 2>/dev/null)"; prefix="${prefix%/}"
logical_root="${PWD%/}"; [ -z "$prefix" ] || logical_root="${logical_root%/"$prefix"}"
short_root="${root#/private}"
git -C "$root" rev-parse --verify -q "$base^{commit}" >/dev/null || die "--base is not a commit: $(printf '%s' "$base" | vetdd_printable)"
for s in "${slices[@]}"; do
  vetdd_is_slice_id "$s" || die "invalid slice id"
  [ -f "$root/.vetdd/evidence/$s/meta.json" ] && [ ! -L "$root/.vetdd/evidence/$s/meta.json" ] \
    || die "no evidence for slice $s"
done

C="$out/c1"
mkdir -p "$C/artifact/tests" || die "cannot create $out" 1

# The diff, with new files: a temporary index holds HEAD plus intent-to-add entries for them.
idx="$(mktemp "${TMPDIR:-/tmp}/judge-layout-index.XXXXXX")" || die "cannot create a temporary index" 1
trap 'rm -f "$idx"' EXIT
rm -f "$idx"
if git -C "$root" rev-parse --verify -q HEAD >/dev/null; then
  GIT_INDEX_FILE="$idx" git -C "$root" read-tree HEAD || die "could not read HEAD into a temporary index" 1
else
  GIT_INDEX_FILE="$idx" git -C "$root" read-tree --empty || die "could not make a temporary index" 1
fi
while IFS= read -r -d '' f; do
  case "$f" in .vetdd|.vetdd/*) continue ;; esac
  GIT_INDEX_FILE="$idx" git -C "$root" add --intent-to-add -- "$f" || die "could not add $(printf '%s' "$f" | vetdd_printable) to the temporary index" 1
done < <(git -C "$root" ls-files --others --exclude-standard -z)
GIT_INDEX_FILE="$idx" git -C "$root" diff --no-ext-diff --binary "$base" -- . ':(exclude).vetdd' > "$C/artifact/diff.patch" \
  || die "git diff failed" 1

cp -- "$reply" "$C/artifact/reply.md" || die "cannot copy the reply" 1

ce_rc=0
(cd "$root" && "$here/check-evidence.sh" "${slices[@]}") > "$C/artifact/check-evidence.txt" 2>&1 || ce_rc=$?
printf 'exit %s\n' "$ce_rc" >> "$C/artifact/check-evidence.txt"

for s in "${slices[@]}"; do
  meta="$root/.vetdd/evidence/$s/meta.json"
  mkdir -p "$C/evidence/$s/runs" || die "cannot create $C/evidence/$s" 1
  cp -- "$meta" "$C/evidence/$s/meta.json" || die "cannot copy the evidence of $s" 1
  # Oracle files, as they are now.
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    vetdd_inside_repo "$root" "$p" && [ -f "$root/$p" ] || die "oracle file of $s is missing, a link, or outside the repository: $(printf '%s' "$p" | vetdd_printable)" 1
    mkdir -p "$C/artifact/tests/$(dirname -- "$p")" && cp -- "$root/$p" "$C/artifact/tests/$p" || die "cannot copy an oracle file" 1
  done < <(jq -r '.oracle.files[]?.path | strings' "$meta")
  # Red-run logs and the latest usable mutation copy, named only by the runs/<seq>-<kind> pattern.
  while IFS= read -r rel; do
    case "$rel" in runs/[0-9][0-9][0-9]*-*.log|runs/[0-9][0-9][0-9]*-mutation.json) ;; *) continue ;; esac
    case "$rel" in */../*|*/./*) continue ;; esac
    src="$root/.vetdd/evidence/$s/$rel"
    [ -f "$src" ] && [ ! -L "$src" ] || continue
    cp -- "$src" "$C/evidence/$s/$rel" || die "cannot copy $rel of $s" 1
  done < <(jq -r '
    ([.runs[] | select(.accepted != false and (.kind == "before" or .kind == "calibration") and .outcome == "target_failure") | .log | strings]
     + [[.runs[] | select(.accepted != false and .audit.kind? == "mutation" and .audit.report.status? == "ok")] | last | .audit.report.copy? | strings])
    | .[]' "$meta")
done

# Absolute paths of this machine never go to the judge.
find "$out" -type f -print0 | while IFS= read -r -d '' f; do
  LC_ALL=C grep -Iq . "$f" 2>/dev/null || continue
  ROOT="$root" LROOT="$logical_root" SROOT="$short_root" perl -pi -e 's/\Q$ENV{ROOT}\E/<repo>/g; s/\Q$ENV{LROOT}\E/<repo>/g; s/\Q$ENV{SROOT}\E/<repo>/g' "$f" || exit 1
done || die "could not replace the repository path" 1

if ! blind="$("$here/check-blind.sh" "$out" --profile judge 2>&1)"; then
  printf '%s\n' "$blind" | vetdd_printable >&2
  die "the layout is not blind (check-blind.sh above); fix the reply or the logs and build it again in a new directory" 4
fi

printf 'judge-layout.sh: built %s\n' "$out"
printf 'next: "%s/judge.sh" --rubric "%s/references/final-judge-rubric.md" --candidates "%s" --out <judge.json> --eval-id <id> --run-id <id> --rubric-version <n>\n' \
  "$here" "${here%/scripts}" "$out"
