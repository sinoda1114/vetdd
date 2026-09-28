# Text-file test shared by check-blind.sh and sanitize-candidates.sh (bash 3.2 compatible).

# vetdd_is_text <file>: 0 when <file> holds no NUL byte anywhere (UTF-16 has NULs in ASCII text),
# 1 otherwise or when it cannot be read. An empty file is text. The whole file is read: grep -I
# stops at its first match, so a NUL after a long run of text would go unseen.
vetdd_is_text() {
  local n
  [ -r "$1" ] || return 1
  n="$(LC_ALL=C tr -cd '\000' < "$1" | wc -c)" || return 1
  [ "$n" -eq 0 ]
}
