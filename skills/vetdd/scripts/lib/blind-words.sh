# Blinding word lists and matchers shared by check-blind.sh and sanitize-candidates.sh.
# bash 3.2 compatible; the matchers are POSIX awk. Word files hold one lower-case word per line.

# modes/eval.md rule 1: words that reveal an evaluation to a candidate.
VETDD_FORBIDDEN_WORDS="eval test judge experiment rubric score compare benchmark candidate arena variant baseline"
# Model and vendor names; a word ending in "-" is a prefix (gpt-6-sol).
VETDD_MODEL_WORDS="claude opus sonnet haiku fable codex gpt- grok anthropic openai"
# Words that reveal a candidate's origin or the expected outcome to the judge (principle 6).
# The judge knows it is judging, so the evaluation words above are not hidden from it.
VETDD_ORIGIN_WORDS="variant baseline winner"

# vetdd_word_file <file> <word>...: write the words, lower-cased, longest first (so a longer word
# that contains a shorter one is redacted whole).
vetdd_word_file() {
  local f="$1"; shift
  printf '%s\n' "$@" | awk '{ gsub(/^[ \t]+|[ \t\r]+$/, ""); if ($0 != "" && $0 !~ /^#/) print length($0) "\t" tolower($0) }' \
    | sort -rn -k1,1 | cut -f2- | awk '!seen[$0]++' > "$f"
}

# VETDD_AWK_LEAD: the awk function lead(s, p), shared by both matchers: 1 when the text before
# position p of s (lower-cased) ends at a word boundary. That is the line start, a character that
# is not a letter or digit, or the end of an escape that a transcript or a log puts before a word:
# \n \r \t (a backslash and the letter), \uXXXX (four hex digits), or an ANSI color code (a raw
# ESC, or the text \033 \x1b \e \u001b, then "[", digits and ";", and "m"). So
# {"text":"ok\n/Users/..."} and "\u001b[2m/Users/..." both have a boundary before "/Users".
# The matchers skip lead() for a word that starts with "/" or "\/" (an absolute path): a path
# may follow a URL prefix (/@fs/Users/..., file://localhost/Users/...), and a false hit there only
# redacts or refuses more.
# Plain POSIX awk: fixed-length substrings, no {n} intervals.
VETDD_AWK_LEAD='
  function lead(s, p,   b, q) {
    if (p <= 1) return 1
    b = substr(s, p - 1, 1)
    if (b !~ /[[:alnum:]]/) return 1
    if (b ~ /[nrt]/ && p > 2 && substr(s, p - 2, 1) == "\\") return 1
    if (p > 6 && substr(s, p - 6, 2) == "\\u" \
        && substr(s, p - 4, 4) ~ /^[0-9a-f][0-9a-f][0-9a-f][0-9a-f]$/) return 1
    if (b != "m") return 0
    q = p - 2
    while (q > 0 && substr(s, q, 1) ~ /[0-9;]/) q--
    if (q < 1 || substr(s, q, 1) != "[") return 0
    q--
    if (q >= 1 && substr(s, q, 1) == "\033") return 1
    if (q >= 2 && substr(s, q - 1, 2) == "\\e") return 1
    if (q >= 4 && (substr(s, q - 3, 4) == "\\033" || substr(s, q - 3, 4) == "\\x1b")) return 1
    return (q >= 6 && substr(s, q - 5, 6) == "\\u001b")
  }'

# vetdd_find_words <word-file> <label> <tag>: read text on stdin; print "<label>:<tag or line>: <word>"
# for each word found on a line. Whole-word: a boundary before the word (lead() above: no letter or
# digit, unless it ends an escape), no letter after it (a plural "s" is allowed). A prefix word
# ("gpt-") needs only the leading boundary. Byte-wise (LC_ALL=C): the words are ASCII, and an
# invalid UTF-8 byte must not make awk drop the line.
vetdd_find_words() {
  LC_ALL=C awk -v label="$2" -v tag="$3" "$VETDD_AWK_LEAD"'
    function hit(s, w,   p, off, a, n) {
      off = 0
      while ((p = index(substr(s, off + 1), w)) > 0) {
        p += off; n = p + length(w)
        if (w ~ /-$/) a = ""
        else { a = substr(s, n, 1); if (a == "s") a = substr(s, n + 1, 1) }
        if ((w ~ /^(\/|\\\/)/ || lead(s, p)) && a !~ /[[:alpha:]]/) return 1
        off = p
      }
      return 0
    }
    FNR == NR { W[++nw] = $0; next }
    { s = tolower($0); for (i = 1; i <= nw; i++) if (hit(s, W[i])) print label ":" (tag != "" ? tag : FNR) ": " W[i] }
  ' "$1" -
}

# vetdd_redact <word-file> <file>: print <file> with every case-insensitive, whole-word occurrence
# of each word replaced by [redacted], using the same boundaries as vetdd_find_words (a plural "s"
# is redacted with its word); a prefix word ("gpt-") also takes the version that follows it. Text
# already inside "[redacted]" is never matched again.
# Byte-wise (LC_ALL=C), like vetdd_find_words.
# Exit 0 when something changed, 3 when nothing did, anything else on error.
vetdd_redact() {
  LC_ALL=C awk "$VETDD_AWK_LEAD"'
    # One segment that holds no "[redacted]"; its edges count as boundaries. The escape before a
    # word stays (ok\n[redacted]).
    function seg(s, w,   low, out, p, m, n, a, ok, off, done) {
      out = ""; low = tolower(s); off = 0; done = 0
      while ((p = index(substr(low, off + 1), w)) > 0) {
        p += off; m = p + length(w); n = m
        ok = (w ~ /^(\/|\\\/)/ || lead(low, p))
        if (w ~ /-$/) {
          if (ok) {
            while (substr(s, n, 1) ~ /[A-Za-z0-9_.-]/) n++
            while (n > m && substr(s, n - 1, 1) == ".") n--
          }
        } else {
          a = substr(low, m, 1)
          if (a == "s" && substr(low, m + 1, 1) !~ /[[:alpha:]]/) { n = m + 1; a = substr(low, n, 1) }
          ok = ok && a !~ /[[:alpha:]]/
        }
        if (ok) {
          out = out substr(s, done + 1, p - 1 - done) "[redacted]"; changed = 1
          done = n - 1; off = n - 1
        } else off = p
      }
      return out substr(s, done + 1)
    }
    function redact(s,   i, out, rest, q) {
      for (i = 1; i <= nw; i++) {
        out = ""; rest = s
        while ((q = index(rest, "[redacted]")) > 0) {
          out = out seg(substr(rest, 1, q - 1), W[i]) "[redacted]"
          rest = substr(rest, q + 10)
        }
        s = out seg(rest, W[i])
      }
      return s
    }
    FNR == NR { W[++nw] = $0; next }
    { print redact($0) }
    END { exit changed ? 0 : 3 }
  ' "$1" "$2"
}
