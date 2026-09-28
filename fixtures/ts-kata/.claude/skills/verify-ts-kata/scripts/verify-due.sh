#!/usr/bin/env bash
# Drive: `due 2026-01-10`; expect exit 0 and exactly two stdout lines.
# Usage: verify-due.sh [--expect <line 1>] [--expect-due <line 2>]
#   defaults "closing: 2026-01-31" (January has 31 days) and "due: 2026-03-02" (31 + 30 days)
# Exit 0 observed and met, 1 observed and not met, 2 could not observe or usage error.
set -u
unset CDPATH  # cd prints the directory it found through CDPATH, which breaks $(cd ... && pwd)
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

expect="closing: 2026-01-31"
expect_due="due: 2026-03-02"
while [ $# -gt 0 ]; do
  case "$1" in
    --expect|--expect-due)
      [ $# -ge 2 ] || { printf '%s: %s needs a value\n' "${0##*/}" "$1" >&2; exit 2; }
      if [ "$1" = --expect ]; then expect="$2"; else expect_due="$2"; fi
      shift 2 ;;
    *) printf 'verify-due.sh: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done

can_drive || exit 2
d="$(artifact_dir due)" || exit 2
drive "$d" due 2026-01-10 || exit 2
code="$(cat "$d/exit_code.txt")"
count=0; line1=""; line2=""
while IFS= read -r line || [ -n "$line" ]; do
  count=$((count + 1))
  [ "$count" -eq 1 ] && line1="$line"
  [ "$count" -eq 2 ] && line2="$line"
done < "$d/stdout.txt"

printf 'expected line 1: %s\nactual line 1:   %s\n' "$expect" "$line1"
printf 'expected line 2: %s\nactual line 2:   %s\n' "$expect_due" "$line2"
printf 'expected lines:  2\nactual lines:    %s\n' "$count"
printf 'expected exit:   0\nactual exit:     %s\n' "$code"
[ "$code" = 0 ] && [ "$count" -eq 2 ] && [ "$line1" = "$expect" ] && [ "$line2" = "$expect_due" ] && exit 0
exit 1
