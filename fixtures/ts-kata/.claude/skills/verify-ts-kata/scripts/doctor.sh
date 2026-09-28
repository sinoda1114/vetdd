#!/usr/bin/env bash
# Read-only: is this checkout worth driving? Exit 0 yes, 1 no (message says why).
# Runs the same check as every drive (can_drive), including the tsx probe.
set -u
unset CDPATH  # cd prints the directory it found through CDPATH, which breaks $(cd ... && pwd)
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

[ -f "$APP_ROOT/src/cli.ts" ] || { echo "doctor: src/cli.ts is missing in $APP_ROOT"; exit 1; }
reason="$(can_drive 2>&1)" || { echo "doctor: ${reason#could not observe: }"; exit 1; }
echo "doctor: ok (node $(node --version), tsx probe: ok, app root $APP_ROOT)"
exit 0
