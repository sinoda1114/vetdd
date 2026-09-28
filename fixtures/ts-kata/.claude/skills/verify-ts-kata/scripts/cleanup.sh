#!/usr/bin/env bash
# Nothing stays running for a CLI; remove a stale pid file if a previous launch left one.
# Never touches .vetdd/artifacts/. Exit 1 when the pid file cannot be removed.
set -u
unset CDPATH  # cd prints the directory it found through CDPATH, which breaks $(cd ... && pwd)
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

pid_file="$GIT_ROOT/.vetdd/run/ts-kata.pid"
if [ ! -e "$pid_file" ]; then
  echo "cleanup: nothing to do"
  exit 0
fi
err="$(rm -f "$pid_file" 2>&1)" || { echo "cleanup: could not remove $pid_file: $err"; exit 1; }
echo "cleanup: removed stale $pid_file"
exit 0
