#!/usr/bin/env bash
# Drive: `due` with no date; expect exit code 2 and a stderr line starting with "usage".
# Usage: verify-usage.sh [--expect <exit code>]   default 2
# Exit 0 observed and met, 1 observed and not met, 2 could not observe.
set -u
. "${BASH_SOURCE[0]%/*}/lib.sh"

expect=2
while [ $# -gt 0 ]; do
  case "$1" in
    --expect) [ $# -ge 2 ] || { printf '%s: --expect needs a value\n' "${0##*/}" >&2; exit 2; }; expect="$2"; shift 2 ;;
    *) printf 'verify-usage.sh: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done

d="$(artifact_dir usage)" || exit 2
drive "$d" due || exit 2
code="$(cat "$d/exit_code.txt")"
usage_line="$(grep -im1 '^usage' "$d/stderr.txt" || true)"
printf 'expected exit: %s\nactual exit:   %s\nusage line:    %s\n' "$expect" "$code" "${usage_line:-<none>}"
[ "$code" = "$expect" ] && [ -n "$usage_line" ] && exit 0
exit 1
