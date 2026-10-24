#!/usr/bin/env bash
# Prepare a project for vetdd. Idempotent.
# Usage: setup-project.sh [--repo <dir>]
# - creates .vetdd/
# - adds .vetdd/ to .gitignore when missing
# - installs the vetdd pre-commit hook into the repository's own hooks dir
#   (a foreign hook is backed up as pre-commit.before-vetdd; core.hooksPath is never changed)
set -u
unset CDPATH

die() { printf 'setup-project.sh: %s\n' "$1" >&2; exit 1; }
say() { printf 'setup-project.sh: %s\n' "$1"; }

repo="."
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] || die "--repo needs a value"; repo="$2"; shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done

root="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || die "not a git repository: $repo"
common="$(cd "$root" && cd "$(git rev-parse --git-common-dir)" && pwd -P)" || die "cannot find the git dir"
scripts_dir="$(cd "${BASH_SOURCE[0]%/*}" && pwd -P)"
. "$scripts_dir/lib/common.sh"
hook_src="$scripts_dir/hooks/pre-commit"
hook_dst="$common/hooks/pre-commit"
backup="$hook_dst.before-vetdd"
marker="vetdd pre-commit hook"
changes=0

# The installed hook points at this checkout's scripts.
render_hook() {
  local line
  line="VETDD_SCRIPTS_DIR=\"\${VETDD_SCRIPTS_DIR:-$(printf '%q' "$scripts_dir")}\""
  awk -v repl="$line" '$0 == "VETDD_SCRIPTS_DIR=\"${VETDD_SCRIPTS_DIR:-}\"" { print repl; next } { print }' "$hook_src"
}

if [ ! -d "$root/.vetdd" ]; then
  mkdir -p "$root/.vetdd" && say "created .vetdd/" && changes=$((changes + 1))
fi

gitignore="$root/.gitignore"
if ! grep -Eqx '/?\.vetdd/?' "$gitignore" 2>/dev/null; then
  if [ -s "$gitignore" ] && [ -n "$(tail -c 1 "$gitignore")" ]; then printf '\n' >> "$gitignore"; fi
  printf '.vetdd/\n' >> "$gitignore" && say "added .vetdd/ to .gitignore" && changes=$((changes + 1))
fi

rendered="$(render_hook)" || die "cannot read $hook_src"
if [ -e "$hook_dst" ] && ! grep -q "$marker" "$hook_dst"; then
  [ ! -e "$backup" ] || die "$hook_dst is not a vetdd hook and $backup already exists; resolve it by hand"
  mv "$hook_dst" "$backup" || die "cannot back up $hook_dst"
  say "WARNING: existing pre-commit hook is not vetdd's; moved it to $backup (chain it by hand if still needed)"
  changes=$((changes + 1))
fi
if [ ! -e "$hook_dst" ] || [ "$(cat "$hook_dst")" != "$rendered" ]; then
  mkdir -p "$common/hooks"
  printf '%s\n' "$rendered" > "$hook_dst" && chmod +x "$hook_dst" || die "cannot write $hook_dst"
  say "installed pre-commit hook at $hook_dst"
  changes=$((changes + 1))
elif [ ! -x "$hook_dst" ]; then
  chmod +x "$hook_dst" && say "made $hook_dst executable" && changes=$((changes + 1))
fi

# A core.hooksPath (often a global one) makes git ignore the repository's own hooks. Print one line
# for the hooksPath pre-commit that runs this install's hook: never a file of the repository, which
# could carry any hook. The line skips with a warning when the install is gone or not executable, so
# a removed vetdd blocks no commit; the hook does nothing in a repository without .vetdd/evidence.
# git expands ~ (--type=path). core.hooksPath is never changed.

# Drops control characters (C0, DEL, C1) from a config value before it goes to the terminal.
printable() { printf '%s' "$1" | vetdd_printable; }
real_root="$(cd "$root" && pwd -P)"

# Succeeds when the path (or, while it does not exist, the nearest directory above it) is under this
# work tree and outside the git dir (a submodule's work tree in it too), is in a work tree of this
# repository in any letter case, or is in the superproject's when this is a submodule. A hooks dir
# there (husky's .husky or .husky/_, a .githooks) may be shared with the team.
in_work_tree() {
  local d="$1" phys top their super
  while [ ! -d "$d" ]; do d="${d%/*}"; [ -n "$d" ] || d=/; done
  phys="$(cd "$d" 2>/dev/null && pwd -P)${1#"$d"}"
  case "$phys/" in "$common"/*) ;; "$real_root"/*) return 0 ;; esac
  top="$(git -c core.fsmonitor= -C "$d" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$top" ] || return 1
  [ "$top" -ef "$root" ] && return 0
  their="$(cd "$d" && cd "$(git rev-parse --git-common-dir)" && pwd -P)" && [ "$their" -ef "$common" ] && return 0
  super="$(git -C "$root" rev-parse --show-superproject-working-tree 2>/dev/null)"
  [ -n "$super" ] && [ "$top" -ef "$super" ]
}

hooks_path="$(git -C "$root" config --type=path --get core.hooksPath 2>/dev/null)"
path_rc=$?
# git reads every value (global, then local), so a ~ in any of them can be the one that fails.
raw_hooks_path=""
if [ "$path_rc" -gt 1 ]; then
  while IFS= read -r v; do
    case "$v" in '~'*|':(optional)~'*) raw_hooks_path="$v"; break ;; esac
  done <<HOOKS_PATHS
$(git -C "$root" config --get-all core.hooksPath 2>/dev/null)
HOOKS_PATHS
fi
if [ -n "$raw_hooks_path" ]; then
  say "WARNING: git cannot expand core.hooksPath '$(printable "$raw_hooks_path")' (an unknown ~user?), and git commit fails on it the same way. Fix or unset core.hooksPath, then run setup-project.sh again."
elif [ -n "$hooks_path" ]; then
  case "$hooks_path" in /*) ;; *) hooks_path="$root/$hooks_path" ;; esac
  shown="$(printable "$hooks_path")"
  # The path goes between double quotes in sh, with \ " $ ` escaped.
  quoted="$(printf '%s' "$hook_src" | sed 's/[\\"$`]/\\&/g')"
  chain="vetdd_hook=\"$quoted\"; if [ -x \"\$vetdd_hook\" ]; then \"\$vetdd_hook\" \"\$@\" || exit \$?; elif [ -e \"\$vetdd_hook\" ]; then echo \"vetdd: \$vetdd_hook not executable; skipped\" >&2; else echo \"vetdd: \$vetdd_hook not found; skipped\" >&2; fi"
  if [ "$hooks_path" -ef "$common/hooks" ]; then
    : # hooksPath is this repository's own hooks directory: git runs the hook as installed.
  elif in_work_tree "$hooks_path"; then
    # This machine's install path does not belong in a file shared with the team. A linked
    # worktree's relative .git/hooks lands here too, under the .git file, and is not a directory.
    note=""; [ -d "$hooks_path" ] || note=" and is not a directory (git runs no hook from it)"
    say "WARNING: core.hooksPath ('$shown') is inside the work tree$note, so git ignores $hook_dst. vetdd prints no line for a hook there (husky's or a tracked hooks dir may be shared with the team); run check-evidence.sh before committing instead."
    if grep -qF -- "$quoted" "$hooks_path/pre-commit" 2>/dev/null; then
      say "WARNING: $shown/pre-commit holds a vetdd line with this machine's install path; take it out of that shared file."
    fi
  elif ! (cd "$hooks_path" 2>/dev/null); then
    what="not a directory"; [ ! -d "$hooks_path" ] || what="a directory this user cannot enter"
    say "WARNING: core.hooksPath is '$shown', which is $what, so git runs no hook from it and ignores $hook_dst. Fix that (or fix or unset core.hooksPath), then run setup-project.sh again for the line to put in its pre-commit."
  elif grep -qF -- "$quoted" "$hooks_path/pre-commit" 2>/dev/null; then
    if [ -x "$hooks_path/pre-commit" ]; then
      say "core.hooksPath is '$shown'; $shown/pre-commit mentions the vetdd hook (check that the line comes before any exit)"
    else
      say "WARNING: core.hooksPath is '$shown'; $shown/pre-commit mentions the vetdd hook but is not executable, so git does not run it (chmod +x it)"
    fi
  else
    say "WARNING: core.hooksPath is set to '$shown', so git ignores $hook_dst. To run vetdd's check, put this line in $shown/pre-commit, before any exit in that file (create it with #!/bin/sh first and make it executable if it does not exist; core.hooksPath was not changed):"
    printf '    %s\n' "$chain"
  fi
fi

[ "$changes" -gt 0 ] || say "no changes (already set up)"
exit 0
