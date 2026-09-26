#!/usr/bin/env bash
# Read-only: is this checkout worth driving? Exit 0 yes, 1 no (message says why).
set -u
. "${BASH_SOURCE[0]%/*}/lib.sh"

command -v node >/dev/null || { echo "doctor: node is not on PATH"; exit 1; }
[ -x "$APP_ROOT/node_modules/.bin/tsx" ] || { echo "doctor: tsx is not installed; run npm ci in $APP_ROOT"; exit 1; }
[ -f "$APP_ROOT/src/cli.ts" ] || { echo "doctor: src/cli.ts is missing in $APP_ROOT"; exit 1; }
echo "doctor: ok (node $(node --version), app root $APP_ROOT)"
exit 0
