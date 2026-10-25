# Text helpers: the text-file test shared by check-blind.sh and sanitize-candidates.sh, and the checks
# for text recorded in meta.json (oracle-version.sh, audit-note.sh) (bash 3.2 compatible).

# vetdd_is_text <file>: 0 when <file> holds no NUL byte anywhere (UTF-16 has NULs in ASCII text),
# 1 otherwise or when it cannot be read. An empty file is text. The whole file is read: grep -I
# stops at its first match, so a NUL after a long run of text would go unseen.
vetdd_is_text() {
  local n
  [ -r "$1" ] || return 1
  n="$(LC_ALL=C tr -cd '\000' < "$1" | wc -c)" || return 1
  [ "$n" -eq 0 ]
}

# Text that comes from outside (a reason, a question, an answer) and is recorded in meta.json, then
# shown by check-evidence. They call the caller's die() (which must exit) and vetdd_printable (common.sh).

# vetdd_has_control <text>: true when the text holds a control character (C0, DEL, newline, tab, or a
# UTF-8 C1 control); the recorded text reaches the terminal through check-evidence.
vetdd_has_control() {
  case "$1" in *[[:cntrl:]]*) return 0 ;; esac
  printf '%s' "$1" | LC_ALL=C grep -q -e "$(printf '[\001-\037\177]')" -e "$(printf '\302[\200-\237]')"
}

# vetdd_file_id <file>: "<inode>:<links>" of the file (links followed), GNU stat first (BSD stat has no -c).
vetdd_file_id() { stat -L -c '%i:%h' "$1" 2>/dev/null || stat -L -f '%i:%l' "$1" 2>/dev/null; }

# vetdd_text_file <option> <path> <root>: the one line of text in a regular file (not a link, at most 4096
# bytes, no other hard link) in <root>/.vetdd/notes/ or a directory below it (where its directory really
# is, links resolved), so text that came from outside never has to pass through the shell's quoting and no
# other file on the machine is read into meta.json (which goes to the judge). The file is opened once; what
# was opened must be the file the name was checked for (its inode, with a single link: a hard link would
# be another name outside .vetdd/notes/), and every other check is on what was read from it.
vetdd_text_file() {
  local opt="$1" path="$2" root="$3" shown d copy n why="" content="" fd_id
  shown="$(printf '%s' "$path" | vetdd_printable)"
  case "$path" in -*) path="./$path" ;; esac  # dirname would read it as an option
  [ -f "$path" ] && [ ! -L "$path" ] || die "$opt: $shown is not a regular file"
  d="$(CDPATH='' cd -P -- "$(dirname -- "$path")" 2>/dev/null && pwd -P)" || die "$opt: cannot resolve the directory of $shown"
  case "$d/" in
    "$root/.vetdd/notes/"*) ;;
    *) die "$opt: $shown is not in .vetdd/notes/ of this repository; write the text to a file there and pass its path" ;;
  esac
  # Read through a redirection: a name of - is this file, not standard input.
  { exec 7< "$path"; } 2>/dev/null || die "$opt: cannot read the file"
  fd_id="$(vetdd_file_id /dev/fd/7)"
  if [ -z "$fd_id" ] || [ "$fd_id" != "$(vetdd_file_id "$path")" ] || [ -L "$path" ]; then
    exec 7<&-; die "$opt: $shown changed while it was opened"
  fi
  if [ "${fd_id#*:}" != 1 ]; then
    exec 7<&-; die "$opt: $shown has another hard link (a name that may be outside .vetdd/notes/); write the text to a new file there"
  fi
  copy="$(mktemp "${TMPDIR:-/tmp}/vetdd-text.XXXXXX")" || { exec 7<&-; die "$opt: cannot create a temporary file"; }
  # One byte more than the limit is enough to tell a file that is too large.
  if ! head -c 4097 <&7 > "$copy" 2>/dev/null; then why="cannot read the file"
  else
    n="$(wc -c < "$copy" | tr -d ' ')"
    if [ "$n" -gt 4096 ]; then why="the file is larger than 4096 bytes"
    # A NUL byte would be dropped by the command substitution below, leaving a different text.
    elif [ "$(LC_ALL=C tr -d '\000' < "$copy" | wc -c | tr -d ' ')" -ne "$n" ]; then why="the file holds a NUL byte"
    elif ! content="$(cat < "$copy")"; then why="cannot read the file"
    fi
  fi
  exec 7<&-
  rm -f "$copy"
  [ -z "$why" ] || die "$opt: $why"
  case "$content" in *$'\n'*) die "$opt: the file must hold one line" ;; esac
  vetdd_text_opt "$opt" "$content"
  TEXT_FILE_VALUE="$content"
}

# vetdd_text_opt <option> <value>: a non-empty value without control characters.
vetdd_text_opt() {
  [ -n "$2" ] || die "$1 must not be empty"
  if vetdd_has_control "$2"; then die "$1 must not contain control characters (newline, tab, escape, ...)"; fi
}
