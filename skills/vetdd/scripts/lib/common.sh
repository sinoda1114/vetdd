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

# vetdd_printable: copy stdin to stdout without control characters (tab and newline stay), so text
# that came from a candidate, a verdict, or a file name cannot drive the operator's terminal.
vetdd_printable() {
  # Line by line, so a long-running producer's output shows as it comes. Per line: C0 and DEL by
  # byte; invalid UTF-8 next when iconv works (a lone C1 byte); then the C1 controls
  # (U+0080-U+009F), repeated so a removal cannot rejoin one. Valid UTF-8 stays.
  local line more use_iconv=0
  if [ "$(printf a | iconv -c -f UTF-8 -t UTF-8 2>/dev/null)" = a ]; then use_iconv=1; fi
  while :; do
    more=1
    IFS= read -r line || { more=0; [ -n "$line" ] || break; }
    printf '%s' "$line" | LC_ALL=C tr -d '\000-\010\013-\037\177' |
      if [ "$use_iconv" -eq 1 ]; then iconv -c -f UTF-8 -t UTF-8 2>/dev/null; else cat; fi |
      LC_ALL=C sed -e ':a' -e $'s/\xc2[\x80-\x9f]//' -e 'ta' | LC_ALL=C tr -d '\n'
    [ "$more" -eq 1 ] || break
    printf '\n'
  done
}

# vetdd_disk_name <dir> <path>: print the name <path> has on disk inside <dir> (its own directory),
# so another letter case on a case-insensitive file system resolves to one spelling. An entry with
# exactly the given name wins; otherwise only an entry whose name matches ignoring case counts, so a
# hard or symbolic link under another name is never taken for it. Falls back to the name as given.
# Only ASCII letter case is folded: a name the file system treats as the same through non-ASCII case
# or Unicode normalization (NFC/NFD) keeps the spelling given, so name such a file the same way on
# every run.
vetdd_disk_name() {
  local d="$1" p="$2" e given want
  given="${p##*/}"
  for e in "$d"/* "$d"/.[!.]* "$d"/..?*; do
    [ "${e##*/}" = "$given" ] && [ "$e" -ef "$p" ] && { printf '%s\n' "$given"; return 0; }
  done
  want="$(printf '%s' "$given" | tr 'A-Z' 'a-z')"
  for e in "$d"/* "$d"/.[!.]* "$d"/..?*; do
    # Builtins first: only a name of the same length can match ignoring case.
    [ "${#e}" -eq $(( ${#d} + 1 + ${#given} )) ] || continue
    [ "$(printf '%s' "${e##*/}" | tr 'A-Z' 'a-z')" = "$want" ] || continue
    if [ "$e" -ef "$p" ]; then printf '%s\n' "${e##*/}"; return 0; fi
  done
  printf '%s\n' "$given"
}

# vetdd_disk_path <root> <relative path>: the path under <root> with every component under its
# on-disk spelling (vetdd_disk_name), so Tests/a.sh and tests/a.sh are one path.
vetdd_disk_path() {
  local d="$1" rest="$2" comp out="" name
  while [ -n "$rest" ]; do
    case "$rest" in */*) comp="${rest%%/*}"; rest="${rest#*/}" ;; *) comp="$rest"; rest="" ;; esac
    [ -n "$comp" ] || continue
    name="$(vetdd_disk_name "$d" "$d/$comp")"
    out="${out:+$out/}$name"; d="$d/$name"
  done
  printf '%s\n' "$out"
}

# vetdd_inside_repo <root> <relative path>: true when the path has no control characters (paths
# travel one per line), no . or .. component, its last component is not a symbolic link, and its
# directory resolves under <root> (as given by pwd -P). A path whose directory does not exist opens
# nothing, so it passes; the caller reports the file missing.
vetdd_inside_repo() {
  local root="$1" rel="$2" parent dir
  case "$rel" in ''|/*|*$'\n'*|*$'\t'*|*[[:cntrl:]]*) return 1 ;; esac
  # By byte, without the display filter: C0, DEL, and the UTF-8 C1 controls.
  if printf '%s' "$rel" | LC_ALL=C grep -q -e "$(printf '[\001-\037\177]')" -e "$(printf '\302[\200-\237]')"; then
    return 1
  fi
  case "/$rel/" in */../*|*/./*) return 1 ;; esac
  [ ! -L "$root/$rel" ] || return 1
  parent="$(dirname -- "$root/$rel")"
  [ -e "$parent" ] || [ -L "$parent" ] || return 0
  dir="$(CDPATH='' cd -P -- "$parent" 2>/dev/null && pwd -P)" || return 1
  case "$dir/" in "$root"/*) return 0 ;; esac
  return 1
}
