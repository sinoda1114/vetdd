#!/usr/bin/env bash
# Drive: `due <date>` (default 2026-01-10); expect exit 0 and exactly two stdout lines.
# Usage: verify-due.sh [--date <YYYY-MM-DD>] [--expect <line 1>] [--expect-due <line 2>]
#   defaults "closing: 2026-01-31" (January has 31 days) and "due: 2026-03-02" (31 + 30 days);
#   with --date, give both expectations too (the defaults are for 2026-01-10)
# Exit 0 observed and met, 1 observed and not met, 2 could not observe or usage error.
set -u
unset CDPATH  # cd prints the directory it found through CDPATH, which breaks $(cd ... && pwd)
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

expect="closing: 2026-01-31"
expect_due="due: 2026-03-02"
date="2026-01-10"; expect_set=0; expect_due_set=0
while [ $# -gt 0 ]; do
  case "$1" in
    --date)
      [ $# -ge 2 ] || { printf '%s: --date needs a value\n' "${0##*/}" >&2; exit 2; }
      case "$2" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) date="$2" ;; *) printf '%s: --date takes YYYY-MM-DD\n' "${0##*/}" >&2; exit 2 ;; esac
      shift 2 ;;
    --expect|--expect-due)
      [ $# -ge 2 ] || { printf '%s: %s needs a value\n' "${0##*/}" "$1" >&2; exit 2; }
      if [ "$1" = --expect ]; then expect="$2"; expect_set=1; else expect_due="$2"; expect_due_set=1; fi
      shift 2 ;;
    *) printf 'verify-due.sh: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done

# The defaults are for 2026-01-10: another date without both expectations would compare against them.
if [ "$date" != 2026-01-10 ] && { [ "$expect_set" -eq 0 ] || [ "$expect_due_set" -eq 0 ]; }; then
  printf '%s: --date %s needs --expect and --expect-due as well\n' "${0##*/}" "$date" >&2; exit 2
fi
can_drive || exit 2
d="$(artifact_dir due)" || exit 2
drive "$d" due "$date" || exit 2
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
# The app's own usage error (exit 2: an impossible date, a bad option) is not an observation of the feature.
[ "$code" = 2 ] && { printf 'could not observe: the app reported a usage error (exit 2)\n'; exit 2; }
[ "$code" = 0 ] && [ "$count" -eq 2 ] && [ "$line1" = "$expect" ] && [ "$line2" = "$expect_due" ] && exit 0
exit 1
