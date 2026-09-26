# Shared by the verify-ts-kata scripts. bash 3.2 compatible.
# APP_ROOT: fixtures/ts-kata. ARTIFACTS: <git root>/.vetdd/artifacts unless VETDD_ARTIFACTS is set.

APP_ROOT="$(cd "${BASH_SOURCE[0]%/*}/../../../.." && pwd)"
GIT_ROOT="$(git -C "$APP_ROOT" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$APP_ROOT")"
ARTIFACTS="${VETDD_ARTIFACTS:-$GIT_ROOT/.vetdd/artifacts}"

# artifact_dir <feature>: create and print a timestamped artifact directory.
artifact_dir() {
  local d="$ARTIFACTS/$1/$(date -u +%Y%m%dT%H%M%SZ)-$$"
  mkdir -p "$d" && printf '%s\n' "$d"
}

# drive <artifact dir> <args...>: run the CLI from APP_ROOT, save stdout, stderr, exit code.
# Exit 2 (could not observe) when tsx is not installed.
drive() {
  local d="$1"; shift
  [ -x "$APP_ROOT/node_modules/.bin/tsx" ] || { printf 'could not observe: tsx is not installed (run npm ci)\n' >&2; return 2; }
  # The app's own tsx, never npx: npx may fetch a package from the registry when resolution fails.
  ( cd "$APP_ROOT" && ./node_modules/.bin/tsx src/cli.ts "$@" > "$d/stdout.txt" 2> "$d/stderr.txt" )
  local code=$?
  printf '%s\n' "$code" > "$d/exit_code.txt"
  printf 'command: ./node_modules/.bin/tsx src/cli.ts %s\n' "$*" > "$d/command.txt"
  printf 'artifacts: %s\n' "$d"
  return 0
}
