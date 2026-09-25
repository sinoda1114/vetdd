# Shared helpers for vetdd scripts (bash 3.2 compatible; builtins only until jq is confirmed).

# vetdd_require_jq <script-name>: exit 2 with an install hint when jq is missing.
vetdd_require_jq() {
  command -v jq >/dev/null 2>&1 && return 0
  printf '%s: jq is required but not found; install it (macOS: brew install jq, Debian/Ubuntu: apt-get install jq)\n' "$1" >&2
  exit 2
}

# vetdd_is_slice_id <id>: letters, digits, . _ - ; must start with a letter or digit
# (keeps every slice inside .vetdd/evidence/).
vetdd_is_slice_id() {
  case "$1" in [A-Za-z0-9]*) ;; *) return 1 ;; esac
  case "$1" in *[!A-Za-z0-9._-]*) return 1 ;; esac
  return 0
}
