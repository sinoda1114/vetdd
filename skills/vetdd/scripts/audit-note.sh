#!/usr/bin/env bash
# Record why an audit does not apply to a slice.
# Usage: audit-note.sh <slice-id> --kind undefined-imports|mutation --not-applicable --reason-file <path>
# Appends {kind, status: "not_applicable", reason, recorded_at, after_seq} to audits[] in
# .vetdd/evidence/<slice>/meta.json. The audits themselves are `calibrate.sh stub` (undefined-imports)
# and `evidence.sh --audit mutation` (mutation); this note is for a slice where one cannot apply (a
# verify slice that drives the running app, a test with no product import, a language with no mutation
# tool). check-evidence rules 10b and 10c accept the note when it was recorded after the final oracle
# first ran. The reason is one line in a file (a regular file, no control characters, 4096 bytes at
# most), so text from outside never passes through the shell. A second entry of the same kind is a
# usage error until a run starts after the last one (a new oracle version needs a new note). Rules 10b and 10c are tripwires, not boundaries: they check that the note exists, not
# that the reason is true.
# Exit 0 on success, 2 on usage errors (nothing is written).
set -u

die() { printf 'audit-note.sh: %s\n' "$1" >&2; exit 2; }

unset CDPATH
. "${BASH_SOURCE[0]%/*}/lib/common.sh"
. "${BASH_SOURCE[0]%/*}/lib/text.sh"
vetdd_require_jq audit-note.sh

usage="usage: audit-note.sh <slice-id> --kind undefined-imports|mutation --not-applicable --reason-file <path>"
[ $# -ge 1 ] || die "$usage"
slice="$1"; shift
vetdd_is_slice_id "$slice" || die "invalid slice id (letters, digits, . _ -; starting with a letter or digit)"

kind=""; have_na=0; reason=""; have_reason=0
while [ $# -gt 0 ]; do
  case "$1" in
    --kind) [ $# -ge 2 ] || die "--kind needs a value"; [ -z "$kind" ] || die "--kind given twice"
      case "$2" in undefined-imports|mutation) kind="$2" ;; *) die "--kind takes undefined-imports or mutation" ;; esac
      shift 2 ;;
    --not-applicable) have_na=1; shift ;;
    --reason-file) [ $# -ge 2 ] || die "--reason-file needs a path"; [ "$have_reason" -eq 0 ] || die "--reason-file given twice"
      vetdd_text_file --reason-file "$2"; reason="$TEXT_FILE_VALUE"; have_reason=1; shift 2 ;;
    *) die "unexpected argument '$(printf '%s' "$1" | vetdd_printable)' ($usage)" ;;
  esac
done
[ -n "$kind" ] || die "--kind is required"
[ "$have_na" -eq 1 ] || die "--not-applicable is required (it is the only status there is; calibrate.sh stub and evidence.sh --audit mutation record the audits themselves)"
[ "$have_reason" -eq 1 ] || die "--reason-file is required"

root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
root="$(cd "$root" && pwd -P)"
rel=".vetdd/evidence/$slice/meta.json"
vetdd_inside_repo "$root" "$rel" || die "$rel is a symbolic link or outside the repository"
dir="$root/.vetdd/evidence/$slice"
meta="$root/$rel"
# vetdd_inside_repo passes a path whose directory does not exist yet, so a link higher up would take
# the new directory and file outside the repository: refuse a link at each level before anything is made.
for c in "$root/.vetdd" "$root/.vetdd/evidence" "$dir"; do
  [ ! -L "$c" ] || die "$c is a symbolic link"
done

[ ! -e "$meta" ] || [ -f "$meta" ] || die "$rel is not a regular file (nothing written)"

# The evidence to extend: the file, or the skeleton evidence.sh creates (so the two scripts agree).
# Nothing is written until the whole new document is built.
if [ -f "$meta" ]; then
  in_json="$(cat "$meta")" || die "cannot read $meta"
  printf '%s' "$in_json" | jq -e --arg s "$slice" '(.slice_id == $s) and (.runs | type == "array") and (.oracle.files | type == "array")
      and ((.audits // []) | type == "array" and all(.[]; type == "object"))' >/dev/null 2>&1 \
    || die "$rel is not valid evidence for slice '$slice' (nothing written)"
else
  in_json="$(jq -n --arg s "$slice" '{slice_id: $s, oracle: {seam: null, version: null, files: []}, runs: []}')" \
    || die "cannot build the evidence for slice '$slice'"
fi

# The note records after_seq, the last run number when it was written: it counts only for an oracle
# whose first run is not after it, so a new oracle version needs a new note. A second note of a kind is
# refused until a run comes after the last one (a note from before after_seq existed: by its time).
after_seq="$(printf '%s' "$in_json" | jq '[.runs[].seq | numbers] | max // 0')" || die "could not read the runs of $rel"
dup="$(printf '%s' "$in_json" | jq -r --arg k "$kind" --argjson last "$after_seq" '
  ([.runs[].started_at | strings] | max) as $lt
  | any((.audits // [])[]; .kind == $k and
      (if (.after_seq | type) == "number" then .after_seq >= $last
       else ($lt == null or ((.recorded_at | strings) // "") >= $lt) end))')" \
  || die "could not read the audits of $rel"
[ "$dup" != true ] || die "slice '$slice' already has an audit entry of kind $kind and no run has started since (one per kind and oracle)"

recorded_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
created=0; [ -d "$dir" ] || created=1
mkdir -p "$dir" || die "cannot create $dir"
# Created after the directory, and checked by where it really is: a link made in between would not
# be followed out of the repository.
phys="$(cd -P "$dir" 2>/dev/null && pwd -P)" || phys=""
if [ "$phys" != "$root/.vetdd/evidence/$slice" ]; then
  [ "$created" -eq 1 ] && rmdir "$dir" 2>/dev/null
  die "$dir resolves outside the repository (nothing written)"
fi
# A name nobody can predict, made with O_EXCL: a planted link at a guessed name is never followed.
tmp_meta="$(mktemp "$dir/meta.json.XXXXXX")" || { [ "$created" -eq 1 ] && rmdir "$dir" 2>/dev/null; die "cannot create a temporary file in $dir"; }
printf '%s' "$in_json" | jq --arg k "$kind" --arg reason "$reason" --arg at "$recorded_at" --argjson after "$after_seq" '
  .audits = ((.audits // []) + [{kind: $k, status: "not_applicable", reason: $reason, recorded_at: $at, after_seq: $after}])' > "$tmp_meta" \
  && chmod "$(vetdd_file_mode)" "$tmp_meta" && mv "$tmp_meta" "$meta" || {
  rm -f "$tmp_meta"; [ "$created" -eq 1 ] && rmdir "$dir" 2>/dev/null; die "could not update $meta"
}
printf 'audit-note.sh: recorded %s as not_applicable for %s\n' "$kind" "$slice"
