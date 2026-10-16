#!/usr/bin/env bash
# Install the vetdd skill from this checkout into Claude Code's skills directory.
# Usage: install.sh [--dest <dir>]
#   --dest   where the skill goes (default: ${CLAUDE_CONFIG_DIR:-~/.claude}/skills/vetdd); a relative
#            path is taken from the current directory. Its parent must be the user's and not writable
#            by others (a shared place such as /tmp), so nobody can swap a directory in between the
#            steps below.
# Steps: check the tools the scripts need (bash, git, jq, perl, node; all missing ones are named);
# copy the files git tracks under skills/vetdd (all of them when the checkout is not a git
# repository) into a private temporary directory beside <dest>; leave an install that matches that
# copy (content, execute bits, links) alone; otherwise move the existing one (a directory, or a link
# to a development checkout) to ${CLAUDE_CONFIG_DIR:-~/.claude}/skills-backup/vetdd-<time> and put
# the copy in its place, moving the old one back when that fails. codex is not required to install,
# but the separate judge needs it with a file login: a missing codex or login is reported, not fatal.
# Exit: 0 installed or up to date; 1 a required tool is missing or a step failed (the install in
# place is kept); 2 usage error.
set -u
unset CDPATH

die() { printf 'install.sh: %s\n' "$1" >&2; exit "${2:-1}"; }
say() { printf 'install.sh: %s\n' "$1"; }

# Run from standard input there is no checkout to copy from: never fall back to the current directory.
case "${BASH_SOURCE[0]:-}" in
  */*) here="${BASH_SOURCE[0]%/*}" ;;
  "") die "run install.sh from a checkout (git clone, then <checkout>/install.sh), not from standard input" 2 ;;
  *) here=. ;;
esac
[ -f "$here/install.sh" ] || die "run install.sh from a checkout, not from standard input" 2
here="$(cd "$here" && pwd -P)" || die "cannot find the checkout"
src="$here/skills/vetdd"
[ -n "${HOME:-}" ] || [ -n "${CLAUDE_CONFIG_DIR:-}" ] || die "neither HOME nor CLAUDE_CONFIG_DIR is set" 2
conf="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
dest="$conf/skills/vetdd"

while [ $# -gt 0 ]; do
  case "$1" in
    --dest) [ $# -ge 2 ] || die "--dest needs a directory" 2; dest="$2"; shift 2 ;;
    *) die "unknown argument: $1 (usage: install.sh [--dest <dir>])" 2 ;;
  esac
done
dest="${dest%/}"
[ -n "$dest" ] || die "--dest needs a directory other than /" 2
case "$dest" in /*) ;; *) dest="$PWD/$dest" ;; esac
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

parent="${dest%/*}"; [ -n "$parent" ] || parent=/
mkdir -p "$parent" || die "cannot create $parent"
[ -n "$(find "$parent" -maxdepth 0 -user "$(id -u)" ! -perm -o+w 2>/dev/null)" ] \
  || die "$parent is not yours or others can write to it; give a --dest under a directory only you can change"

tmp="$(mktemp -d "$parent/.vetdd-install.XXXXXX")" || die "cannot create a temporary directory in $parent"
trap 'rm -rf "$tmp"' EXIT
new="$tmp/vetdd"
if git -C "$here" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # Only what git tracks: no .DS_Store or scratch file of the checkout goes along.
  mkdir "$new" || die "cannot create $new"
  (cd "$src" && git ls-files -z -- .) | (cd "$src" && while IFS= read -r -d '' f; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    mkdir -p "$new/$(dirname -- "$f")" && cp -P -p -- "$f" "$new/$f" || exit 1
  done) || die "cannot copy $src"
else
  cp -R "$src" "$new" || die "cannot copy $src"
fi

# What "the same" means: content, and which files are executable or links.
shape() { (cd "$1" && find . \( -type l -o -perm -u+x \) ! -type d -print | LC_ALL=C sort); }
if [ -d "$dest" ] && [ ! -L "$dest" ] && diff -r "$new" "$dest" >/dev/null 2>&1 \
   && [ "$(shape "$new")" = "$(shape "$dest")" ]; then
  say "$dest is up to date"
else
  b=""
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    backups="$conf/skills-backup"
    mkdir -p "$backups" || die "cannot create $backups"
    b="$backups/vetdd-$(date +%Y%m%d-%H%M%S)"
    [ ! -e "$b" ] && [ ! -L "$b" ] || b="$b-$$"
    mv "$dest" "$b" || die "cannot move the existing install to $b"
    say "moved the existing install to $b"
  fi
  if ! mv "$new" "$dest"; then
    [ -z "$b" ] || mv "$b" "$dest" || die "cannot put the new copy at $dest, nor move the old one back from $b"
    die "cannot put the new copy at $dest; the install in place is kept"
  fi
  say "installed $dest"
fi
say "next: in each project, run $dest/scripts/setup-project.sh"
