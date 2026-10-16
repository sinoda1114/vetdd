#!/usr/bin/env bash
# Install the vetdd skill from this checkout into Claude Code's skills directory.
# Usage: install.sh [--dest <dir>]
#   --dest   where the skill goes (default: ${CLAUDE_CONFIG_DIR:-~/.claude}/skills/vetdd)
# Steps: check the tools the scripts need (bash, git, jq, perl, node; all missing ones are named);
# leave an install that already matches this checkout alone; otherwise move the existing one (a
# directory, or a link to a development checkout) to ${CLAUDE_CONFIG_DIR:-~/.claude}/skills-backup/
# vetdd-<time> and put a fresh copy of skills/vetdd in its place. codex is not required to install,
# but the separate judge needs it with a file login: a missing codex or login is reported, not fatal.
# Exit: 0 installed or up to date; 1 a required tool is missing or a step failed (nothing is
# replaced); 2 usage error.
set -u
unset CDPATH

die() { printf 'install.sh: %s\n' "$1" >&2; exit "${2:-1}"; }
say() { printf 'install.sh: %s\n' "$1"; }

case "${BASH_SOURCE[0]}" in */*) here="${BASH_SOURCE[0]%/*}" ;; *) here=. ;; esac
here="$(cd "$here" && pwd -P)" || die "cannot find the checkout"
src="$here/skills/vetdd"
[ -n "${HOME:-}" ] || [ -n "${CLAUDE_CONFIG_DIR:-}" ] || die "neither HOME nor CLAUDE_CONFIG_DIR is set" 2
conf="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
dest="$conf/skills/vetdd"

while [ $# -gt 0 ]; do
  case "$1" in
    --dest) [ $# -ge 2 ] || die "--dest needs a directory" 2; dest="${2%/}"; shift 2 ;;
    *) die "unknown argument: $1 (usage: install.sh [--dest <dir>])" 2 ;;
  esac
done
[ -f "$src/SKILL.md" ] || die "cannot find skills/vetdd next to install.sh ($src)"

missing=""
for t in bash git jq perl node; do
  command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
done
[ -z "$missing" ] \
  || die "missing required tools:$missing (macOS: brew install$missing; Debian/Ubuntu: apt-get install$missing, node from nodejs.org)"

# The separate judge (judge.sh) runs codex with a file login it can lend to a private CODEX_HOME.
codex_home="${CODEX_HOME:-${HOME:-}/.codex}"
if ! command -v codex >/dev/null 2>&1; then
  say "WARNING: codex not found: the separate judge cannot run, so test and verify modes end blocked. Install it (npm install -g @openai/codex) and log in with a file login (below)"
elif [ ! -f "$codex_home/auth.json" ]; then
  say "WARNING: no codex file login ($codex_home/auth.json): the judge cannot use a keyring login. Set cli_auth_credentials_store = \"file\" in $codex_home/config.toml and run \`codex login\`"
fi

if [ -d "$dest" ] && [ ! -L "$dest" ] && diff -r "$src" "$dest" >/dev/null 2>&1; then
  say "$dest is up to date"
else
  parent="${dest%/*}"
  mkdir -p "$parent" || die "cannot create $parent"
  tmp="$(mktemp -d "$parent/.vetdd-install.XXXXXX")" || die "cannot create a temporary directory in $parent"
  trap 'rm -rf "$tmp"' EXIT
  cp -R "$src" "$tmp/vetdd" || die "cannot copy $src"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    backups="$conf/skills-backup"
    mkdir -p "$backups" || die "cannot create $backups"
    b="$backups/vetdd-$(date +%Y%m%d-%H%M%S)"
    [ ! -e "$b" ] && [ ! -L "$b" ] || b="$b-$$"
    mv "$dest" "$b" || die "cannot move the existing install to $b"
    say "moved the existing install to $b"
  fi
  mv "$tmp/vetdd" "$dest" || die "cannot put the new copy at $dest"
  say "installed $dest"
fi
say "next: in each project, run $dest/scripts/setup-project.sh"
