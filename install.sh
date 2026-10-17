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
unset CDPATH GIT_DIR GIT_WORK_TREE

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
while :; do case "$dest" in */) dest="${dest%/}" ;; *) break ;; esac; done
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
elif [ -n "$(find -H "$codex_home/auth.json" -maxdepth 0 \( -perm -g+r -o -perm -o+r \) 2>/dev/null)" ]; then
  say "WARNING: your codex login ($codex_home/auth.json) is readable by others; run chmod 600 on it"
fi

# safe_dir <dir>: its real path and every ancestor up to / are the user's or root's and writable by no
# one else: by others only when sticky and root's (/tmp), by the group only when the group is the
# user's own (a user-private group) or the directory is sticky and root's. Sets bad to the first that is not.
uid="$(id -u)"; own_group=""
[ "$(id -gn)" != "$(id -un)" ] || own_group="$(id -g)"
safe_dir() {
  local d
  d="$(cd "$1" 2>/dev/null && pwd -P)" || { bad="$1"; return 1; }
  while :; do
    [ -n "$(find "$d" -maxdepth 0 \( -user "$uid" -o -user 0 \) \
      \( ! -perm -o+w -o \( -perm -1000 -user 0 \) \) \
      \( ! -perm -g+w ${own_group:+-o -group "$own_group"} -o \( -perm -1000 -user 0 \) \) 2>/dev/null)" ] \
      || { bad="$d"; return 1; }
    [ "$d" != / ] || return 0
    d="$(dirname -- "$d")"
  done
}

parent="${dest%/*}"; [ -n "$parent" ] || parent=/
mkdir -p "$parent" || die "cannot create $parent"
safe_dir "$parent" \
  || die "$bad is not yours (or root's), or someone else can write to it; give a --dest under directories only you can change"
# From here on the real path: a link in --dest is resolved once, after it was checked.
dest="$(cd "$parent" && pwd -P)/${dest##*/}"; parent="${dest%/*}"; [ -n "$parent" ] || parent=/
# A directory that is not a vetdd install (--dest naming the skills directory itself, say) is never moved away.
if [ -d "$dest" ] && [ ! -L "$dest" ] && ! grep -qx 'name: vetdd' "$dest/SKILL.md" 2>/dev/null; then
  die "$dest exists and is not a vetdd install; give --dest the vetdd directory itself (e.g. ~/.claude/skills/vetdd)"
fi

tmp="$(mktemp -d "$parent/.vetdd-install.XXXXXX")" || die "cannot create a temporary directory in $parent"
trap 'rm -rf "$tmp"' EXIT
new="$tmp/vetdd"
# The checkout itself is a git repository: only what git tracks goes (no .DS_Store or scratch file).
# A copy that is not one (an unpacked archive, even inside another repository) goes whole.
top="$(git -C "$here" rev-parse --show-toplevel 2>/dev/null)" && top="$(cd "$top" && pwd -P)" || top=""
if [ "$top" = "$here" ]; then
  list="$tmp/files"
  git -C "$here" ls-files -z -- skills/vetdd > "$list" \
    || die "git cannot list the files of $here; the install in place is kept"
  tr '\0' '\n' < "$list" | grep -qx 'skills/vetdd/SKILL.md' \
    || die "skills/vetdd/SKILL.md is not tracked in $here; the install in place is kept"
  mkdir "$new" || die "cannot create $new"
  while IFS= read -r -d '' f; do
    r="${f#skills/vetdd/}"
    # A tracked file the working tree lacks (an unstaged deletion, a sparse checkout) would leave a
    # skill that fails later: stop now.
    [ -e "$here/$f" ] || [ -L "$here/$f" ] \
      || die "$f is tracked but missing from $here (restore it with git checkout -- $f); the install in place is kept"
    # No -p: the copy belongs to whoever runs this (as root, never to the checkout's owner); the
    # mode, execute bits included, comes from the source through the umask.
    mkdir -p "$new/$(dirname -- "$r")" && cp -P -- "$here/$f" "$new/$r" || die "cannot copy $f"
  done < "$list"
else
  cp -R "$src" "$new" || die "cannot copy $src"
fi
[ -f "$new/SKILL.md" ] && [ -x "$new/scripts/setup-project.sh" ] \
  || die "the copy of $src is incomplete; the install in place is kept"
# Nobody else may change what Claude Code will run, whatever the checkout's modes.
chmod -R go-w "$new" || die "cannot set the modes of the copy"

# What "the same" means: content, and, each listed on its own, the links, the executable files, and
# anything the group or others can write.
shape() {
  (cd "$1" && { find . -type l | sed 's/^/l /'; find . -type f -perm -u+x | sed 's/^/x /'
                find . ! -type l \( -perm -g+w -o -perm -o+w \) | sed 's/^/w /'; } | LC_ALL=C sort)
}
if [ -d "$dest" ] && [ ! -L "$dest" ] && diff -r "$new" "$dest" >/dev/null 2>&1 \
   && [ "$(shape "$new")" = "$(shape "$dest")" ]; then
  say "$dest is up to date"
else
  b=""
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    backups="$conf/skills-backup"
    mkdir -p "$backups" || die "cannot create $backups"
    safe_dir "$backups" || die "$bad is not yours (or root's), or someone else can write to it; the install in place is kept"
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
