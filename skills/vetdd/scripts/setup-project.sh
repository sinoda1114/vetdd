#!/usr/bin/env bash
# Prepare a project for vetdd. Idempotent.
# Usage: setup-project.sh [--repo <dir>]
# - creates .vetdd/
# - adds .vetdd/ to .gitignore when missing
# - installs the vetdd pre-commit hook into the repository's own hooks dir
#   (a foreign hook is backed up as pre-commit.before-vetdd; core.hooksPath is never changed)
set -u

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
# for the hooksPath pre-commit that runs the installed vetdd hook: code of this install, never a file
# of the repository (a repository unpacked from an archive could carry any hook, whatever it says it
# is). The hook does nothing in a repository without .vetdd/evidence. core.hooksPath is never changed.
hooks_path="$(git -C "$root" config --get core.hooksPath 2>/dev/null || true)"
if [ -n "$hooks_path" ]; then
  case "$hooks_path" in
    "~"*)
      # git expands ~ and ~user itself (--type=path, git 2.18+); ~/ alone is done here for older git.
      expanded="$(git -C "$root" config --type=path --get core.hooksPath 2>/dev/null || true)"
      if [ -n "$expanded" ] && [ "$expanded" != "$hooks_path" ]; then hooks_path="$expanded"
      elif [ -n "${HOME:-}" ]; then case "$hooks_path" in "~/"*) hooks_path="$HOME/${hooks_path#\~/}" ;; "~") hooks_path="$HOME" ;; esac
      fi ;;
  esac
  case "$hooks_path" in /*) ;; *) hooks_path="$root/$hooks_path" ;; esac
  real_hooks="$(cd "$hooks_path" 2>/dev/null && pwd -P || true)"
  # husky (core.hooksPath .husky/_) regenerates .husky/_ and runs .husky/<hook>, executable or not.
  target="$hooks_path/pre-commit"; need_x=1
  case "$hooks_path" in */.husky/_) target="${hooks_path%/_}/pre-commit"; need_x=0 ;; esac
  # Double-quoted for sh, with \ " $ ` escaped inside.
  chain="\"$(printf '%s' "$scripts_dir/hooks/pre-commit" | sed 's/[\\"$`]/\\&/g')\""' "$@" || exit $?'
  has_line() { tr -d '\r' < "$1" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -qxF -- "$2"; }
  if [ -n "$real_hooks" ] && [ "$real_hooks" = "$common/hooks" ]; then
    : # hooksPath is this repository's own hooks directory: git runs the hook as installed.
  elif { [ "$need_x" -eq 0 ] || [ -x "$target" ]; } && has_line "$target" "$chain"; then
    say "core.hooksPath is '$hooks_path'; $target appears to chain the vetdd hook (check that the line comes before any exit)"
  else
    say "WARNING: core.hooksPath is set to '$hooks_path', so git ignores $hook_dst. To run vetdd's check, put this line in $target, before any exit in that file (create it with #!/bin/sh first and make it executable if it does not exist; it runs this install's hook, which does nothing in a repository without .vetdd/evidence; core.hooksPath was not changed):"
    printf '    %s\n' "$chain"
  fi
fi

[ "$changes" -gt 0 ] || say "no changes (already set up)"
exit 0
