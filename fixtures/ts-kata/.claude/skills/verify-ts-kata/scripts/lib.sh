# Shared by the verify-ts-kata scripts. bash 3.2 compatible.
# APP_ROOT: fixtures/ts-kata. ARTIFACTS: <git root>/.vetdd/artifacts unless VETDD_ARTIFACTS is set;
# outside git, <app root>/.vetdd/artifacts.

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$LIB_DIR/../../../.." && pwd)"
GIT_ROOT="$(git -C "$APP_ROOT" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$APP_ROOT")"
ARTIFACTS="${VETDD_ARTIFACTS:-$GIT_ROOT/.vetdd/artifacts}"
# drive redirects after cd to the app root, so a relative path must be made absolute here, from
# the caller's directory.
case "$ARTIFACTS" in /*) ;; *) ARTIFACTS="$PWD/$ARTIFACTS" ;; esac
# The app's own tsx, never npx: npx may fetch a package from the registry when resolution fails.
TSX="$APP_ROOT/node_modules/.bin/tsx"

# artifact_dir <feature>: create and print a new timestamped artifact directory. The last level is
# created with plain mkdir, so an existing directory (possibly holding planted links) is never reused.
artifact_dir() {
  local d="$ARTIFACTS/$1/$(date -u +%Y%m%dT%H%M%SZ)-$$"
  { mkdir -p "${d%/*}" && mkdir "$d"; } 2>/dev/null \
    || { printf 'could not observe: cannot create the artifact directory %s\n' "$d" >&2; return 2; }
  printf '%s\n' "$d"
}

# can_drive: node is on PATH, the app's tsx is installed, and probe.ts runs through tsx and esbuild.
# Otherwise print "could not observe: <reason>" on stderr and return 2.
can_drive() {
  local out code
  command -v node >/dev/null 2>&1 || { printf 'could not observe: node is not on PATH\n' >&2; return 2; }
  [ -x "$TSX" ] || { printf 'could not observe: tsx is not installed; run npm ci in %s\n' "$APP_ROOT" >&2; return 2; }
  out="$(cd "$APP_ROOT" && "$TSX" "$LIB_DIR/probe.ts" 2>&1)"
  code=$?
  [ "$code" -eq 0 ] && return 0
  out="$(printf '%s\n' "$out" | head -n 3)"
  printf 'could not observe: tsx probe failed (exit %s)%s\n' "$code" "${out:+: $out}" >&2
  return 2
}

# drive <artifact dir> <args...>: run the CLI from APP_ROOT, save stdout, stderr, exit code.
# Call can_drive before artifact_dir, so could-not-observe creates no directory at all.
# Return 2 (could not observe) when the artifacts cannot be written, and remove <artifact dir>
# (artifact_dir just made it): a failed redirect would otherwise look like the app exiting 1.
drive() {
  local d="$1" code; shift
  { : > "$d/stdout.txt" && : > "$d/stderr.txt"; } 2>/dev/null \
    || { printf 'could not observe: cannot write the artifacts in %s\n' "$d" >&2; rm -rf "$d" 2>/dev/null; return 2; }
  ( cd "$APP_ROOT" && "$TSX" src/cli.ts "$@" > "$d/stdout.txt" 2> "$d/stderr.txt" )
  code=$?
  { printf '%s\n' "$code" > "$d/exit_code.txt" \
      && printf 'command: ./node_modules/.bin/tsx src/cli.ts %s\n' "$*" > "$d/command.txt"; } 2>/dev/null \
    || { printf 'could not observe: cannot write the artifacts in %s\n' "$d" >&2; rm -rf "$d" 2>/dev/null; return 2; }
  printf 'artifacts: %s\n' "$d"
  return 0
}
