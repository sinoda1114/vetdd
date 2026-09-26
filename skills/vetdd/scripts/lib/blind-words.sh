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

# vetdd_find_words <word-file> <label> <tag>: read text on stdin; print "<label>:<tag or line>: <word>"
# for each word found on a line. Whole-word: no letter or digit before the word, no letter after it
# (a plural "s" is allowed). A prefix word ("gpt-") needs only the leading boundary.
vetdd_find_words() {
  awk -v label="$2" -v tag="$3" '
    function hit(s, w,   p, off, b, a, n) {
      off = 0
      while ((p = index(substr(s, off + 1), w)) > 0) {
        p += off; n = p + length(w)
        b = (p > 1) ? substr(s, p - 1, 1) : ""
        if (w ~ /-$/) a = ""
        else { a = substr(s, n, 1); if (a == "s") a = substr(s, n + 1, 1) }
        if (b !~ /[[:alnum:]]/ && a !~ /[[:alpha:]]/) return 1
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
# Exit 0 when something changed, 3 when nothing did, anything else on error.
vetdd_redact() {
  awk '
    # One segment that holds no "[redacted]"; its edges count as boundaries.
    function seg(s, w,   low, out, p, m, n, b, a, ok, prev) {
      out = ""; low = tolower(s); prev = ""
      while ((p = index(low, w)) > 0) {
        m = p + length(w); n = m
        b = (p > 1) ? substr(low, p - 1, 1) : prev
        if (w ~ /-$/) {
          ok = (b !~ /[[:alnum:]]/)
          if (ok) {
            while (substr(s, n, 1) ~ /[A-Za-z0-9_.-]/) n++
            while (n > m && substr(s, n - 1, 1) == ".") n--
          }
        } else {
          a = substr(low, m, 1)
          if (a == "s" && substr(low, m + 1, 1) !~ /[[:alpha:]]/) { n = m + 1; a = substr(low, n, 1) }
          ok = (b !~ /[[:alnum:]]/ && a !~ /[[:alpha:]]/)
        }
        if (ok) { out = out substr(s, 1, p - 1) "[redacted]"; changed = 1 }
        else { n = p + 1; out = out substr(s, 1, p) }
        prev = substr(low, n - 1, 1)
        s = substr(s, n); low = substr(low, n)
      }
      return out s
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
