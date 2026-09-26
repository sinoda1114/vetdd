#!/usr/bin/env bash
# Nothing stays running for a CLI; remove a stale pid file if a previous launch left one.
# Never touches .vetdd/artifacts/.
set -u
. "${BASH_SOURCE[0]%/*}/lib.sh"

pid_file="$GIT_ROOT/.vetdd/run/ts-kata.pid"
if [ -f "$pid_file" ]; then
  rm -f "$pid_file" && echo "cleanup: removed stale $pid_file"
else
  echo "cleanup: nothing to do"
fi
exit 0
