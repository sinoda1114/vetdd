#!/usr/bin/env bash
# Record the diagnosis a stall leaves for the next design (references/stall.md).
# Usage: handover.sh <slice-id> --file <draft.md>
# The draft holds each of these headings on a line of its own: ## Unmet requirement, ## Expected and
# actual, ## Minimal reproduction, ## Hypotheses tried, ## Why it failed, ## Reusable results. It is
# copied to .vetdd/evidence/<slice>/handover-<n>.md (n = 1, 2, ...); the slice's meta.json is not
# changed. check-evidence.sh rule 11 asks for one handover per stall in the record.
# Exit 0 recorded (the path is printed); 1 the copy failed; 2 usage error, a missing heading, or no
# evidence for the slice (nothing is written).
set -u
unset CDPATH

die() { printf 'handover.sh: %s\n' "$1" >&2; exit "${2:-2}"; }

here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
. "$here/lib/common.sh"
. "$here/lib/stall.sh"

[ $# -eq 3 ] && [ "$2" = --file ] || die "usage: handover.sh <slice-id> --file <draft.md>"
slice="$1"; draft="$3"
vetdd_is_slice_id "$slice" || die "invalid slice id"
[ -f "$draft" ] && [ ! -L "$draft" ] || die "--file must be a regular file"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
root="$(cd "$root" && pwd -P)"
dir="$root/.vetdd/evidence/$slice"
for d in "$root/.vetdd" "$root/.vetdd/evidence" "$dir"; do
  [ ! -L "$d" ] || die "${d#"$root"/} is a symbolic link; a handover is written only inside the repository"
done
[ -f "$dir/meta.json" ] && [ ! -L "$dir/meta.json" ] || die "no evidence for slice $slice"
missing=""
while IFS= read -r h; do
  tr -d '\r' < "$draft" | grep -qxF -- "$h" || missing="$missing ${h#\#\# };"
done <<EOF_H
$VETDD_HANDOVER_HEADINGS
EOF_H
[ -z "$missing" ] || die "the draft lacks the heading(s):$missing each goes on a line of its own"
n=1
while [ -e "$dir/handover-$n.md" ] || [ -L "$dir/handover-$n.md" ]; do n=$((n + 1)); done
# Written beside it first, then moved without overwriting: a name taken in between is never written through.
tmp="$(mktemp "$dir/.handover.XXXXXX")" || die "cannot write in $dir" 1
cp -- "$draft" "$tmp" && mv -n -- "$tmp" "$dir/handover-$n.md" && [ ! -e "$tmp" ] \
  || { rm -f -- "$tmp"; die "cannot write $dir/handover-$n.md (the name was taken)" 1; }
printf '%s\n' "$dir/handover-$n.md"
