#!/usr/bin/env bash
# Record why an oracle's version changed (and, for a change in meaning, the re-agreement).
# Usage: oracle-version.sh <slice-id> --version <v> --change initial|implementation|meaning
#                          --reason <text>|--reason-file <path>
#                          [--agreement-via AskUserQuestion|chat --question <q> --answer <a>]
# Appends {version, change, reason, agreement, after_seq, recorded_at} to oracle_versions[] in
# .vetdd/evidence/<slice>/meta.json. after_seq is the highest run seq recorded so far (0 when none):
# the new version's first red must come after it (check-evidence rule 8d). A change in the meaning
# of the agreed behavior (principle 1a) needs all three agreement items. Run it BEFORE the red of
# the new version. Rule 8d is a tripwire, not a boundary: it checks that the record exists and is
# in order, not that the reason is true or that the agreement really happened.
# Exit 0 on success, 2 on usage errors (nothing is written).
set -u

die() { printf 'oracle-version.sh: %s\n' "$1" >&2; exit 2; }

unset CDPATH
. "${BASH_SOURCE[0]%/*}/lib/common.sh"
vetdd_require_jq oracle-version.sh

# has_control <text>: true when the text holds a control character (C0, DEL, newline, tab, or a
# UTF-8 C1 control); the recorded text reaches the terminal through check-evidence.
has_control() {
  case "$1" in *[[:cntrl:]]*) return 0 ;; esac
  printf '%s' "$1" | LC_ALL=C grep -q -e "$(printf '[\001-\037\177]')" -e "$(printf '\302[\200-\237]')"
}

# text_file <option> <path>: the one line of text in a regular file (not a link, at most 4096 bytes),
# so text that came from outside never has to pass through the shell's quoting.
text_file() {
  local opt="$1" path="$2" content
  [ -f "$path" ] && [ ! -L "$path" ] || die "$opt: $(printf '%s' "$path" | vetdd_printable) is not a regular file"
  [ "$(wc -c < "$path" | tr -d ' ')" -le 4096 ] || die "$opt: the file is larger than 4096 bytes"
  # A NUL byte would be dropped by the command substitution below, leaving a different text.
  [ "$(LC_ALL=C tr -d '\000' < "$path" | wc -c | tr -d ' ')" -eq "$(wc -c < "$path" | tr -d ' ')" ] \
    || die "$opt: the file holds a NUL byte"
  # Read through a redirection: a name of - is this file, not standard input.
  content="$(cat < "$path")" || die "$opt: cannot read the file"
  case "$content" in *$'\n'*) die "$opt: the file must hold one line" ;; esac
  text_opt "$opt" "$content"
  TEXT_FILE_VALUE="$content"
}

# text_opt <option> <value>: a non-empty value without control characters.
text_opt() {
  [ -n "$2" ] || die "$1 must not be empty"
  if has_control "$2"; then die "$1 must not contain control characters (newline, tab, escape, ...)"; fi
}

[ $# -ge 1 ] || die "usage: oracle-version.sh <slice-id> --version <v> --change initial|implementation|meaning --reason <text> [--agreement-via AskUserQuestion|chat --question <q> --answer <a>]"
slice="$1"; shift
vetdd_is_slice_id "$slice" || die "invalid slice id (letters, digits, . _ -; starting with a letter or digit)"

version=""; change=""; reason=""; via=""; question=""; answer=""
have_version=0; have_change=0; have_reason=0; have_via=0; have_question=0; have_answer=0
while [ $# -gt 0 ]; do
  case "$1" in
    --version) [ $# -ge 2 ] || die "--version needs a value"
      vetdd_is_slice_id "$2" || die "--version takes letters, digits, and . _ - (got an unsupported value)"
      version="$2"; have_version=1; shift 2 ;;
    --change) [ $# -ge 2 ] || die "--change needs a value"
      case "$2" in initial|implementation|meaning) ;; *) die "--change takes initial, implementation, or meaning" ;; esac
      change="$2"; have_change=1; shift 2 ;;
    --reason) [ $# -ge 2 ] || die "--reason needs a value"; [ "$have_reason" -eq 0 ] || die "--reason given twice (or with --reason-file)"
      text_opt --reason "$2"; reason="$2"; have_reason=1; shift 2 ;;
    --reason-file) [ $# -ge 2 ] || die "--reason-file needs a path"; [ "$have_reason" -eq 0 ] || die "--reason given twice (or with --reason-file)"
      text_file --reason-file "$2"; reason="$TEXT_FILE_VALUE"; have_reason=1; shift 2 ;;
    --agreement-via) [ $# -ge 2 ] || die "--agreement-via needs a value"
      case "$2" in AskUserQuestion|chat) ;; *) die "--agreement-via takes AskUserQuestion or chat" ;; esac
      via="$2"; have_via=1; shift 2 ;;
    --question) [ $# -ge 2 ] || die "--question needs a value"; [ "$have_question" -eq 0 ] || die "--question given twice (or with --question-file)"
      text_opt --question "$2"; question="$2"; have_question=1; shift 2 ;;
    --question-file) [ $# -ge 2 ] || die "--question-file needs a path"; [ "$have_question" -eq 0 ] || die "--question given twice (or with --question-file)"
      text_file --question-file "$2"; question="$TEXT_FILE_VALUE"; have_question=1; shift 2 ;;
    --answer) [ $# -ge 2 ] || die "--answer needs a value"; [ "$have_answer" -eq 0 ] || die "--answer given twice (or with --answer-file)"
      text_opt --answer "$2"; answer="$2"; have_answer=1; shift 2 ;;
    --answer-file) [ $# -ge 2 ] || die "--answer-file needs a path"; [ "$have_answer" -eq 0 ] || die "--answer given twice (or with --answer-file)"
      text_file --answer-file "$2"; answer="$TEXT_FILE_VALUE"; have_answer=1; shift 2 ;;
    *) die "unexpected argument '$(printf '%s' "$1" | vetdd_printable)'" ;;
  esac
done
[ "$have_version" -eq 1 ] || die "--version is required"
[ "$have_change" -eq 1 ] || die "--change is required"
[ "$have_reason" -eq 1 ] || die "--reason is required"

# An agreement is all three items or none; a change in meaning needs it (principle 1a).
agreement_items=$((have_via + have_question + have_answer))
if [ "$agreement_items" -ne 0 ] && [ "$agreement_items" -ne 3 ]; then
  die "an agreement needs --agreement-via, --question, and --answer together"
fi
if [ "$change" = meaning ] && [ "$agreement_items" -ne 3 ]; then
  die "--change meaning needs the re-agreement: --agreement-via AskUserQuestion|chat, --question, --answer (principle 1a)"
fi

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
      and ((.oracle_versions // []) | type == "array" and all(.[]; type == "object"))' >/dev/null 2>&1 \
    || die "$rel is not valid evidence for slice '$slice' (nothing written)"
else
  in_json="$(jq -n --arg s "$slice" '{slice_id: $s, oracle: {seam: null, version: null, files: []}, runs: []}')" \
    || die "cannot build the evidence for slice '$slice'"
fi

# An initial agreement is the first one: a later change is implementation or meaning.
if [ "$change" = initial ] && [ "$(printf '%s' "$in_json" | jq -r '((.oracle_versions // []) | length) > 0')" = true ]; then
  die "--change initial is only for the first version of a slice; this slice already has an entry, so use implementation or meaning (bump --oracle-version and record the new version before its red)"
fi

dup="$(printf '%s' "$in_json" | jq -r --arg v "$version" 'any((.oracle_versions // [])[]; .version == $v)')" \
  || die "could not read the version log of $rel"
[ "$dup" != true ] || die "version '$version' already has an entry for slice '$slice' (a changed oracle takes a new version)"

after_seq="$(printf '%s' "$in_json" | jq '[.runs[].seq | select(type == "number")] | max // 0')" || die "could not read the runs of $rel"
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
printf '%s' "$in_json" | jq --arg v "$version" --arg change "$change" --arg reason "$reason" --argjson with_agreement "$((agreement_items == 3))" \
  --arg via "$via" --arg q "$question" --arg a "$answer" \
  --argjson after_seq "$after_seq" --arg at "$recorded_at" '
  .oracle_versions = ((.oracle_versions // []) + [{
    version: $v, change: $change, reason: $reason,
    agreement: (if $with_agreement == 1 then {via: $via, question: $q, answer: $a} else null end),
    after_seq: $after_seq, recorded_at: $at
  }])' > "$tmp_meta" && chmod "$(vetdd_file_mode)" "$tmp_meta" && mv "$tmp_meta" "$meta" || {
  rm -f "$tmp_meta"; [ "$created" -eq 1 ] && rmdir "$dir" 2>/dev/null; die "could not update $meta"
}
printf 'oracle-version.sh: recorded version %s (%s) for %s after run %s\n' "$version" "$change" "$slice" "$after_seq"
