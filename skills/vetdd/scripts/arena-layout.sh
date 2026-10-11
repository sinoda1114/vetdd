#!/usr/bin/env bash
# Lay out an arena's lanes for the judge (parallel/arena.md): each lane is a runner's branch
# vetdd/<lane>, already checked (worktree.sh check) and brought back (worktree.sh remove <lane>
# --keep-branch), with its design note at .vetdd/notes/<lane>-design.md.
# Usage: arena-layout.sh --out <new dir> --base <ref> <lane>...
#   For each lane, in a worktree the parent makes (worktree.sh review, never the runner's own):
#   check-evidence.sh --before-close <lane> is the gate (a lane that is not OK stays out, named in
#   <out>/gate.txt); a green lane gets judge-layout.sh with its design note as the reply. The green
#   lanes go side by side as <out>/candidates/c1..cN in a shuffled order, kept in <out>/variants.json
#   ({"c1": "<lane>", ...}: the judge never sees which lane, or which runner, a label is). The review
#   worktrees are removed again; the lanes' branches stay for the merge and the grafts.
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

out=""; base=""; lanes=()
while [ $# -gt 0 ]; do
  case "$1" in
    --out) [ $# -ge 2 ] || die "--out needs a directory"; out="$2"; shift 2 ;;
    --base) [ $# -ge 2 ] || die "--base needs a git ref"; base="$2"; shift 2 ;;
    -*) die "unknown option: $(p "$1")" ;;
    *) lanes+=("$1"); shift ;;
  esac
done
[ -n "$out" ] && [ -n "$base" ] && [ ${#lanes[@]} -gt 0 ] || die "usage: arena-layout.sh --out <new dir> --base <ref> <lane>..."
[ ! -e "$out" ] && [ ! -L "$out" ] || die "--out $(p "$out") exists; give a new directory"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
root="$(cd "$root" && pwd -P)"
wtroot="${root%/*}/${root##*/}.vetdd-wt"
git -C "$root" rev-parse -q --verify "$base^{commit}" >/dev/null || die "--base is not a commit: $(p "$base")"
for l in "${lanes[@]}"; do
  vetdd_is_slice_id "$l" || die "invalid lane id: $(p "$l")"
  git -C "$root" rev-parse -q --verify "refs/heads/vetdd/$l" >/dev/null || die "no branch vetdd/$(p "$l")"
  [ ! -e "$wtroot/$l" ] && [ ! -L "$wtroot/$l" ] \
    || die "lane $(p "$l") is still in a worktree; check it and bring it back first (worktree.sh check $(p "$l"), then remove $(p "$l") --keep-branch)"
  [ -f "$root/.vetdd/notes/$l-design.md" ] && [ ! -L "$root/.vetdd/notes/$l-design.md" ] \
    || die "lane $(p "$l") has no design note (.vetdd/notes/$(p "$l")-design.md)"
done

mkdir -m 700 -- "$out" || die "cannot create $(p "$out")" 1
out="$(cd "$out" && pwd -P)"
mkdir -m 700 -- "$out/lanes" || die "cannot create $(p "$out")/lanes" 1
: > "$out/gate.txt"
green=()
for l in "${lanes[@]}"; do
  rv="$("$here/worktree.sh" review "$l")" || die "cannot make a review worktree for $(p "$l")" 1
  gate="$(cd "$rv" && "$here/check-evidence.sh" --before-close "$l" 2>&1)"; grc=$?
  if [ "$grc" -eq 0 ]; then
    printf '%s: green\n' "$l" >> "$out/gate.txt"
    jl_rc=0
    (cd "$rv" && "$here/judge-layout.sh" --before-close --out "$out/lanes/$l" --reply "$rv/.vetdd/notes/$l-design.md" --base "$base" "$l") >/dev/null 2>"$out/lanes/$l.err" || jl_rc=$?
    if [ "$jl_rc" -ne 0 ]; then
      "$here/worktree.sh" remove "$l" --keep-branch >/dev/null 2>&1
      vetdd_printable < "$out/lanes/$l.err" >&2
      [ "$jl_rc" -eq 4 ] && die "the layout of lane $(p "$l") is not blind (above)" 4
      die "judge-layout.sh failed for lane $(p "$l") (exit $jl_rc)" 1
    fi
    green+=("$l")
  else
    printf '%s: not green\n' "$l" >> "$out/gate.txt"
    printf '%s\n' "$gate" | vetdd_printable | sed 's/^/  /' >> "$out/gate.txt"
  fi
  "$here/worktree.sh" remove "$l" --keep-branch >/dev/null || die "cannot remove the review worktree of $(p "$l")" 1
done

if [ ${#green[@]} -eq 0 ]; then
  rm -rf -- "$out/lanes"
  printf 'arena-layout.sh: no lane is green: a stall (gate: %s)\n' "$(p "$out/gate.txt")" >&2
  exit 5
fi

# A shuffled order: the label says nothing about the lane, the runner, or the order they ran in.
mkdir -m 700 -- "$out/candidates" || die "cannot create $(p "$out")/candidates" 1
map='{}'; k=0
while IFS= read -r l; do
  [ -n "$l" ] || continue
  k=$((k + 1))
  mv -- "$out/lanes/$l/c1" "$out/candidates/c$k" || die "cannot place lane $(p "$l")" 1
  map="$(printf '%s' "$map" | jq --arg k "c$k" --arg l "$l" '. + {($k): $l}')"
done < <(printf '%s\n' "${green[@]}" | awk 'BEGIN { srand() } { printf "%.12f\t%s\n", rand(), $0 }' | LC_ALL=C sort | cut -f2-)
rm -rf -- "$out/lanes"
printf '%s\n' "$map" > "$out/variants.json"

printf 'arena-layout.sh: built %s (%d of %d lanes green; the label-to-lane map is variants.json)\n' "$(p "$out/candidates")" "${#green[@]}" "${#lanes[@]}"
printf 'next: %q --rubric %q --candidates %q --out <judge.json> --eval-id <id> --run-id <id> --rubric-version 1\n' \
  "$here/judge.sh" "${here%/scripts}/references/arena-rubric.md" "$out/candidates"
