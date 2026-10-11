#!/usr/bin/env bash
# Is the slice stalled (references/stall.md)? Reads .vetdd/evidence/<slice>/meta.json.
# Usage: stall.sh <slice-id> [--k <n>]   (K, default 2: K+1 failed attempts in a row whose failure
#                                         counts never fall are a stall)
# Prints the failure counts of the attempts since the last green (or the last stall) and the verdict.
# Exit 0 not stalled; 3 stalled (write a handover with handover.sh, then take one of the two exits);
# 2 usage error, or a record that cannot be read.
set -u
unset CDPATH

die() { printf 'stall.sh: %s\n' "$1" >&2; exit "${2:-2}"; }

here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
. "$here/lib/common.sh"
vetdd_require_jq stall.sh
. "$here/lib/stall.sh"

[ $# -ge 1 ] || die "usage: stall.sh <slice-id> [--k <n>]"
slice="$1"; shift
vetdd_is_slice_id "$slice" || die "invalid slice id"
k=2
while [ $# -gt 0 ]; do
  case "$1" in
    --k) [ $# -ge 2 ] || die "--k needs a number"; k="$2"; shift 2 ;;
    *) die "unknown argument: $(printf '%s' "$1" | vetdd_printable)" ;;
  esac
done
case "$k" in [1-9]|[1-9][0-9]) ;; *) die "--k takes a whole number from 1 to 99, without a leading zero" ;; esac
root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
meta="$root/.vetdd/evidence/$slice/meta.json"
[ -f "$meta" ] && [ ! -L "$meta" ] || die "no evidence for slice $slice"
res="$(jq -c --argjson k "$k" "$VETDD_STALL_JQ"' stall_walk($k)' "$meta" 2>/dev/null)" || die "cannot read the evidence of slice $slice"
counts="$(printf '%s' "$res" | jq -r '.trailing | map(tostring) | join(" ")')"
n="$(printf '%s' "$res" | jq -r '.stalls')"
if [ "$(printf '%s' "$res" | jq -r '.stalled')" = true ]; then
  printf 'stall.sh: %s is stalled: failure counts %s over %s attempts (K=%s); %s stalls so far; write a handover (handover.sh), then redesign or go back to 1a (references/stall.md)\n' "$slice" "$counts" "$((k + 1))" "$k" "$n"
  exit 3
fi
printf 'stall.sh: %s is not stalled: failure counts since the last green: %s; %s stalls so far\n' "$slice" "${counts:-none}" "$n"
