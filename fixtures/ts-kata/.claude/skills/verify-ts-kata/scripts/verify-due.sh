#!/usr/bin/env bash
# Drive: `due 2026-01-10` and compare stdout line 1 with the expectation.
# Usage: verify-due.sh [--expect <line>]   default "closing: 2026-01-31" (January has 31 days)
# Exit 0 observed and met, 1 observed and not met, 2 could not observe.
set -u
. "${BASH_SOURCE[0]%/*}/lib.sh"

expect="closing: 2026-01-31"
while [ $# -gt 0 ]; do
  case "$1" in
    --expect) [ $# -ge 2 ] || { printf '%s: --expect needs a value\n' "${0##*/}" >&2; exit 2; }; expect="$2"; shift 2 ;;
    *) printf 'verify-due.sh: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done

d="$(artifact_dir due)" || exit 2
drive "$d" due 2026-01-10 || exit 2
actual="$(head -n 1 "$d/stdout.txt")"
printf 'expected: %s\nactual:   %s\n' "$expect" "$actual"
[ "$actual" = "$expect" ] && exit 0
exit 1
