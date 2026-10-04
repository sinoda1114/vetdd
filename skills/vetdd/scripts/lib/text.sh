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

# vetdd_text_file <option> <path>: the one line of text in a regular file (not a link, at most 4096 bytes),
# so text that came from outside never has to pass through the shell's quoting.
vetdd_text_file() {
  local opt="$1" path="$2" content
  [ -f "$path" ] && [ ! -L "$path" ] || die "$opt: $(printf '%s' "$path" | vetdd_printable) is not a regular file"
  [ "$(wc -c < "$path" | tr -d ' ')" -le 4096 ] || die "$opt: the file is larger than 4096 bytes"
  # A NUL byte would be dropped by the command substitution below, leaving a different text.
  [ "$(LC_ALL=C tr -d '\000' < "$path" | wc -c | tr -d ' ')" -eq "$(wc -c < "$path" | tr -d ' ')" ] \
    || die "$opt: the file holds a NUL byte"
  # Read through a redirection: a name of - is this file, not standard input.
  content="$(cat < "$path")" || die "$opt: cannot read the file"
  case "$content" in *$'\n'*) die "$opt: the file must hold one line" ;; esac
  vetdd_text_opt "$opt" "$content"
  TEXT_FILE_VALUE="$content"
}

# vetdd_text_opt <option> <value>: a non-empty value without control characters.
vetdd_text_opt() {
  [ -n "$2" ] || die "$1 must not be empty"
  if vetdd_has_control "$2"; then die "$1 must not contain control characters (newline, tab, escape, ...)"; fi
}
