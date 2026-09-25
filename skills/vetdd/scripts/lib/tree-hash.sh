# Shared helpers for evidence.sh and check-evidence.sh (bash 3.2 compatible).

# vetdd_tree_hash <repo-root>
# Hash of the working tree including uncommitted and untracked changes,
# excluding .gitignored paths and .vetdd/. Uses a throwaway index so the
# real index is never touched. .vetdd/ is dropped with `rm --cached` rather
# than an exclude pathspec, which git rejects when .vetdd/ is gitignored.
vetdd_tree_hash() {
  local root="$1" tmp hash status
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/vetdd-index.XXXXXX")" || return 1
  (
    cd "$root" &&
      export GIT_INDEX_FILE="$tmp/index" &&
      git add -A -- . &&
      git rm -r -q --cached --ignore-unmatch -- .vetdd >/dev/null &&
      git write-tree
  ) > "$tmp/out"
  status=$?
  hash="$(cat "$tmp/out")"
  rm -rf "$tmp"
  [ "$status" -eq 0 ] || return "$status"
  printf '%s\n' "$hash"
}

# vetdd_sha256 <file>
vetdd_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}
