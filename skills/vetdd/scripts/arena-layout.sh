#!/usr/bin/env bash
# Lay out an arena's lanes for the judge (parallel/arena.md): each lane is a runner's branch
# vetdd/<lane>, already checked (worktree.sh check) and brought back (worktree.sh remove <lane>
# --keep-branch), with its design note at .vetdd/notes/<lane>-design.md.
# Usage: arena-layout.sh --out <new dir> --base <ref> [--allow-secrets <glob>[:<kind>,...]]...
#                        [--allow-binary <path>]... <lane>...
#   For each lane: worktree.sh check again, then, in a worktree the parent makes (worktree.sh review,
#   never the runner's own), check-evidence.sh --before-close <lane> is the gate (exit 1: the lane is
#   not green and stays out, named in <out>/gate.txt; any other failure stops the build); a green lane
#   gets judge-layout.sh --before-close with its design note as the reply (--allow-secrets and
#   --allow-binary go to it: write a secret glob as c*/..., since the label changes). The green lanes
#   go side by side as <out>/candidates/c1..cN in an order drawn from /dev/urandom; inside each, the
#   lane id becomes a neutral one (cand<k>: directory names, slice_id, check-evidence output, logs),
#   and <out>/variants.json keeps the map ({"c1": "<lane>", ...}): the judge never sees which lane, or
#   which runner, a label is. The review worktrees are removed again (also when the build stops); the
#   lanes' branches stay for the merge and the grafts.
#   <out> must be outside the repository or under its .vetdd/.
# Exit 0 built (it prints the judge.sh command with references/arena-rubric.md); 1 a local step
# failed; 2 usage error (nothing is written); 4 a lane's layout is not blind; 5 no lane is green
# (a stall: no candidates are written).
set -u
unset CDPATH
umask 077

die() { printf 'arena-layout.sh: %s\n' "$1" >&2; exit "${2:-2}"; }

here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
. "$here/lib/common.sh"
vetdd_require_jq arena-layout.sh
p() { printf '%s' "$1" | vetdd_printable; }

out=""; base=""; lanes=(); jl_args=(); allow=()
while [ $# -gt 0 ]; do
  case "$1" in
    --out) [ $# -ge 2 ] || die "--out needs a directory"; out="$2"; shift 2 ;;
    --base) [ $# -ge 2 ] || die "--base needs a git ref"; base="$2"; shift 2 ;;
    --allow-secrets) [ $# -ge 2 ] || die "--allow-secrets needs <glob>[:<kind>,...]"; allow+=("$2"); jl_args+=(--allow-secrets "$2"); shift 2 ;;
    --allow-binary) [ $# -ge 2 ] || die "--allow-binary needs a repository path"; jl_args+=(--allow-binary "$2"); shift 2 ;;
    -*) die "unknown option: $(p "$1")" ;;
    *) lanes+=("$1"); shift ;;
  esac
done
[ -n "$out" ] && [ -n "$base" ] && [ ${#lanes[@]} -gt 0 ] \
  || die "usage: arena-layout.sh --out <new dir> --base <ref> [--allow-secrets <glob>[:<kind>,...]]... [--allow-binary <path>]... <lane>..."
[ ! -e "$out" ] && [ ! -L "$out" ] || die "--out $(p "$out") exists; give a new directory"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
root="$(cd "$root" && pwd -P)"
wtroot="${root%/*}/${root##*/}.vetdd-wt"
od="$(cd -P -- "$(dirname -- "$out")" 2>/dev/null && pwd -P)" || die "--out: its parent directory does not exist"
abs="${od%/}/${out##*/}"
case "$abs/" in
  "$root"/.vetdd/*) ;;
  "$root"/*) die "--out must be outside the repository or under its .vetdd/: the next layout would take the candidates in as new files" ;;
esac
git -C "$root" rev-parse -q --verify "$base^{commit}" >/dev/null || die "--base is not a commit: $(p "$base")"
seen=" "
for l in "${lanes[@]}"; do
  vetdd_is_slice_id "$l" || die "invalid lane id: $(p "$l")"
  case "$seen" in *" $l "*) die "lane $(p "$l") is named twice" ;; esac
  seen="$seen$l "
  git -C "$root" rev-parse -q --verify "refs/heads/vetdd/$l" >/dev/null || die "no branch vetdd/$(p "$l")"
  [ ! -e "$wtroot/$l" ] && [ ! -L "$wtroot/$l" ] \
    || die "lane $(p "$l") is still in a worktree; check it and bring it back first (worktree.sh check $(p "$l"), then remove $(p "$l") --keep-branch)"
  [ -f "$root/.vetdd/notes/$l-design.md" ] && [ ! -L "$root/.vetdd/notes/$l-design.md" ] \
    || die "lane $(p "$l") has no design note (.vetdd/notes/$(p "$l")-design.md)"
done

mkdir -m 700 -- "$abs" || die "cannot create $(p "$abs")" 1
out="$abs"
mkdir -m 700 -- "$out/lanes" "$out/errs" || die "cannot create the work directories in $(p "$out")" 1
# A review worktree left by a stop is removed on the way out.
cur=""
trap 'if [ -n "$cur" ]; then "$here/worktree.sh" remove "$cur" --keep-branch >/dev/null 2>&1; fi' EXIT

: > "$out/gate.txt"
green=()
for l in "${lanes[@]}"; do
  "$here/worktree.sh" check "$l" >/dev/null 2>"$out/errs/$l.check" \
    || { vetdd_printable < "$out/errs/$l.check" >&2; die "worktree.sh check refused lane $(p "$l") (above)" 1; }
  rv="$("$here/worktree.sh" review "$l" 2>"$out/errs/$l.review")" \
    || { vetdd_printable < "$out/errs/$l.review" >&2; die "cannot make a review worktree for $(p "$l")" 1; }
  cur="$l"
  grc=0
  gate="$(cd "$rv" && "$here/check-evidence.sh" --before-close "$l" 2>&1)" || grc=$?
  case "$grc" in
    0)
      printf '%s: green\n' "$l" >> "$out/gate.txt"
      jl_rc=0
      (cd "$rv" && "$here/judge-layout.sh" --before-close ${jl_args[@]+"${jl_args[@]}"} --out "$out/lanes/$l" \
        --reply "$rv/.vetdd/notes/$l-design.md" --base "$base" "$l") >/dev/null 2>"$out/errs/$l.layout" || jl_rc=$?
      if [ "$jl_rc" -ne 0 ]; then
        vetdd_printable < "$out/errs/$l.layout" >&2
        [ "$jl_rc" -eq 4 ] && die "the layout of lane $(p "$l") is not blind (above)" 4
        die "judge-layout.sh failed for lane $(p "$l") (exit $jl_rc)" 1
      fi
      green+=("$l") ;;
    1)
      printf '%s: not green\n' "$l" >> "$out/gate.txt"
      printf '%s\n' "$gate" | vetdd_printable | sed 's/^/  /' >> "$out/gate.txt" ;;
    *)
      printf '%s\n' "$gate" | vetdd_printable >&2
      die "check-evidence.sh could not judge lane $(p "$l") (exit $grc)" 1 ;;
  esac
  "$here/worktree.sh" remove "$l" --keep-branch >/dev/null || die "cannot remove the review worktree of $(p "$l")" 1
  cur=""
done

if [ ${#green[@]} -eq 0 ]; then
  rm -rf -- "$out/lanes" "$out/errs"
  printf 'arena-layout.sh: no lane is green: a stall (gate: %s)\n' "$(p "$out/gate.txt")" >&2
  exit 5
fi

# An order drawn from /dev/urandom: the label says nothing about the lane, the runner, or the order
# they ran in.
mkdir -m 700 -- "$out/candidates" || die "cannot create $(p "$out")/candidates" 1
map='{}'; k=0
while IFS= read -r l; do
  [ -n "$l" ] || continue
  k=$((k + 1)); tok="cand$k"; c="$out/lanes/$l/c1"
  # The lane id becomes the neutral one everywhere inside the candidate.
  mv -- "$c/evidence/$l" "$c/evidence/$tok" || die "cannot rename the evidence of lane $(p "$l")" 1
  find "$c" -type f -print0 | while IFS= read -r -d '' f; do
    LC_ALL=C grep -Iq . "$f" 2>/dev/null || continue
    LANE="$l" TOK="$tok" perl -pi -e 's{(?<![\w.-])\Q$ENV{LANE}\E(?![\w-]|\.\w)}{$ENV{TOK}}g' "$f" || exit 1
  done || die "cannot hide the lane id of $(p "$l")" 1
  mv -- "$c" "$out/candidates/c$k" || die "cannot place lane $(p "$l")" 1
  map="$(printf '%s' "$map" | jq --arg k "c$k" --arg l "$l" '. + {($k): $l}')"
done < <(for l in "${green[@]}"; do printf '%s\t%s\n' "$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')" "$l"; done \
         | LC_ALL=C sort -n | cut -f2-)
rm -rf -- "$out/lanes" "$out/errs"
printf '%s\n' "$map" > "$out/variants.json"

printf 'arena-layout.sh: built %s (%d of %d lanes green; the label-to-lane map is variants.json)\n' "$(p "$out/candidates")" "${#green[@]}" "${#lanes[@]}"
printf 'next: %q --rubric %q --candidates %q --out <judge.json> --eval-id <id> --run-id <id> --rubric-version 1' \
  "$here/judge.sh" "${here%/scripts}/references/arena-rubric.md" "$out/candidates"
for a in ${allow[@]+"${allow[@]}"}; do printf ' --allow-secrets %q' "$a"; done
printf '\n'
