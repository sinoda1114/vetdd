#!/usr/bin/env bash
# Record why an oracle's version changed (and, for a change in meaning, the re-agreement).
# Usage: oracle-version.sh <slice-id> --version <v> --change initial|implementation|meaning
#                          --reason <text>
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
    --reason) [ $# -ge 2 ] || die "--reason needs a value"; text_opt --reason "$2"; reason="$2"; have_reason=1; shift 2 ;;
    --agreement-via) [ $# -ge 2 ] || die "--agreement-via needs a value"
      case "$2" in AskUserQuestion|chat) ;; *) die "--agreement-via takes AskUserQuestion or chat" ;; esac
      via="$2"; have_via=1; shift 2 ;;
    --question) [ $# -ge 2 ] || die "--question needs a value"; text_opt --question "$2"; question="$2"; have_question=1; shift 2 ;;
    --answer) [ $# -ge 2 ] || die "--answer needs a value"; text_opt --answer "$2"; answer="$2"; have_answer=1; shift 2 ;;
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

if [ -f "$meta" ]; then
  jq -e --arg s "$slice" '(.slice_id == $s) and (.runs | type == "array") and (.oracle.files | type == "array")
      and ((.oracle_versions // []) | type == "array")' "$meta" >/dev/null 2>&1 \
    || die "$rel is not valid evidence for slice '$slice' (nothing written)"
else
  # The skeleton evidence.sh creates, so the two scripts agree.
  mkdir -p "$dir" || die "cannot create $dir"
  jq -n --arg s "$slice" '{slice_id: $s, oracle: {seam: null, version: null, files: []}, runs: []}' > "$meta" \
    || die "cannot create $meta"
fi

if jq -e --arg v "$version" 'any((.oracle_versions // [])[]; .version == $v)' "$meta" >/dev/null 2>&1; then
  die "version '$version' already has an entry for slice '$slice' (a changed oracle takes a new version)"
fi

after_seq="$(jq '[.runs[].seq | select(type == "number")] | max // 0' "$meta")" || die "could not read $meta"
recorded_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
tmp_meta="$meta.tmp.$$"
jq --arg v "$version" --arg change "$change" --arg reason "$reason" --argjson with_agreement "$((agreement_items == 3))" \
  --arg via "$via" --arg q "$question" --arg a "$answer" \
  --argjson after_seq "$after_seq" --arg at "$recorded_at" '
  .oracle_versions = ((.oracle_versions // []) + [{
    version: $v, change: $change, reason: $reason,
    agreement: (if $with_agreement == 1 then {via: $via, question: $q, answer: $a} else null end),
    after_seq: $after_seq, recorded_at: $at
  }])' < "$meta" > "$tmp_meta" && mv "$tmp_meta" "$meta" || {
  rm -f "$tmp_meta"; die "could not update $meta"
}
printf 'oracle-version.sh: recorded version %s (%s) for %s after run %s\n' "$version" "$change" "$slice" "$after_seq"
