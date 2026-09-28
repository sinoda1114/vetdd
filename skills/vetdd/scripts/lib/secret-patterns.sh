# Secret-shaped strings that must not reach the judge (an outside model), for check-blind.sh.
# This is a safety net for known shapes only, not a complete search. What leaves the machine is
# decided by the Q4 agreement in SKILL.md and by what sanitize leaves out; a clean result here does
# not mean the text holds no secret.
#
# bash 3.2 compatible; the matcher is POSIX awk run byte-wise (LC_ALL=C), with no {n,m} intervals
# (older awks lack them), so each repeat is spelled out.
#
# Each line is matched as a copy in which JSON escapes (\n \r \t \uXXXX) and ANSI color codes
# (a raw ESC, or the text \033 \x1b \e \u001b, then [ digits ; m) are spaces, so a token that
# follows one ("...token\nghp_...") still has a non-alphanumeric character before it. The report
# gives the original line number.
#
# Kinds, in report order:
#   private-key    -----BEGIN ... PRIVATE KEY----- and -----BEGIN PGP PRIVATE KEY BLOCK-----
#   aws-key        AKIA and 16 upper-case letters or digits
#   github-token   gh[pousr]_ and 20 or more letters or digits
#   github-pat     github_pat_ and 22 or more letters, digits, or _
#   slack-token    xox[abprs]- and 10 or more letters, digits, or -
#   openai-key     sk- and 20 or more of [A-Za-z0-9_-] (not sk-ant-, which is the next kind)
#   anthropic-key  sk-ant- and 20 or more of [A-Za-z0-9_-]
#   npm-token      npm_ and 36 letters or digits
#   google-api-key AIza and 35 of [0-9A-Za-z_-]
#   stripe-key     sk_live_, rk_live_, sk_test_, or rk_test_ and 16 or more letters or digits
#   gitlab-token   glpat- and 20 of [0-9A-Za-z_-]
#   jwt            eyJ, 10 or more of [A-Za-z0-9_-], ".", 10 or more, "."
#   bearer-token   bearer (any case), blanks, and 20 or more of [A-Za-z0-9._~+/-]
#   basic-auth     authorization (any case, as a header, a JSON or YAML key, or an assignment),
#                  then basic and 16 or more of [A-Za-z0-9+/] (Authorization: Basic dXNl...)
#   url-credentials ://user:password@ in a URL (postgres://app:...@localhost/db; the user may be
#                  empty, as redis://:...@ has it). Neither part holds "/", ":", "@", or a blank.
#                  Not a password that starts with $ (${DB_PASSWORD}, $DB_PASSWORD), <,
#                  [redacted], or ***.
#   email          an address, except noreply@, the reserved example.com, example.org,
#                  example.net, .example, .invalid, .test, and localhost domains, and a "domain"
#                  that ends in a file extension that is not also a country code (icon@2x.png,
#                  pkg@1.0.0.min.js). person@company.md and person@startup.sh are addresses.
#                  Nor is an SSH remote: user@host followed by ":" and ~/, /, a name then /, or a
#                  name ending in .git (git@github.com:org/repo.git, git@host:org/repo,
#                  deploy@host:~/app, git@host:/srv/repo.git: the scp form), or user@host right
#                  after ssh:// (ssh://git@host/x, git+ssh://...). "alice@corp.io: hi" and
#                  "alice@corp.io:S3cretPass" (curl -u) are still addresses.
#   assignment     a key, then ":" or "=", then a value of 8 or more characters. The key is
#                  password, passwd, secret, token, or api_key / api-key / apikey, then any
#                  [a-z0-9_] (any case, after a non-alphanumeric or at the start:
#                  aws_secret_access_key, client_secret, auth_token), or a camelCase name that
#                  ends in Secret, Token, Password, Passwd, or ApiKey (clientSecret, authToken,
#                  _authToken).
#                  A value that starts with {{, $, <, REDACTED, [redacted], xxx, or your is a
#                  placeholder, quoted or not. Otherwise a quoted value counts
#                  (password: "john.smith2024", secret = "Pa(ss)w0rd99"); unquoted, a plain key's
#                  value counts only when it is 16 or more characters that mix letters and digits
#                  (token=ab12cd34ef56gh78), and a camelCase key's only in the .npmrc form
#                  _authToken=... . So an unquoted identifier (token: accessToken,
#                  password = hashPassword), call (getToken(req)), or member access
#                  (req.headers.authorization, process.env.token) is not a secret.
# The token kinds need a non-alphanumeric character (or the line start) before them, so "task-..."
# is not an sk- key. No kind can be turned off everywhere: check-blind.sh --allow-secrets exempts a
# path, from every kind or only from the kinds named after it (<glob>:email,assignment); judge.sh
# and sanitize-candidates.sh pass it through.

# The kinds as reported, in report order (assignment-camel is reported as assignment). check-blind.sh
# accepts only these after --allow-secrets <glob>:, and vetdd_find_secrets fails when a pattern's
# kind is missing here or a name here has no pattern.
VETDD_SECRET_KINDS="private-key aws-key github-token github-pat slack-token openai-key anthropic-key npm-token google-api-key stripe-key gitlab-token jwt bearer-token basic-auth url-credentials email assignment"

# vetdd_allow_secret_error <value>: check one --allow-secrets value, <glob> or
# <glob>:<kind>[,<kind>]... (split at the last ":"). Print why it is wrong and return 1, or return 0.
# check-blind.sh and sanitize-candidates.sh both call it, so a typo is a usage error in either.
vetdd_allow_secret_error() {
  local v="$1" glob list rest k
  case "$v" in *:*) ;; *) return 0 ;; esac
  glob="${v%:*}"; list="${v##*:}"
  [ -n "$glob" ] || { printf "%s\n" "--allow-secrets '$v' has no glob before ':'"; return 1; }
  rest="$list,"
  while [ -n "$rest" ]; do
    k="${rest%%,*}"; rest="${rest#*,}"
    [ -n "$k" ] || { printf "%s\n" "--allow-secrets '$v' has an empty kind (<glob>:<kind>[,<kind>]...)"; return 1; }
    case " $VETDD_SECRET_KINDS " in
      *" $k "*) ;;
      *) printf "%s\n" "--allow-secrets '$v': unknown secret kind '$k' (one of: $VETDD_SECRET_KINDS)"; return 1 ;;
    esac
  done
  return 0
}

# vetdd_find_secrets <label> [<tag>] [<skip>]: read text on stdin; print
# "<label>:<tag or line>: secret: <kind>" for each kind found on a line (check-blind.sh passes the tag
# "name" for a file or directory name), except the kinds in <skip> (space-separated).
vetdd_find_secrets() {
  LC_ALL=C awk -v label="$1" -v tag="${2:-}" -v skip="${3:-}" -v kinds="${VETDD_SECRET_KINDS:-}" '
    function rep(c, n,   s) { s = ""; while (n-- > 0) s = s c; return s }
    function add(kind, re) { K[++nk] = kind; R[nk] = re }
    # reported(kind): the name a kind is reported (and skipped) by.
    function reported(kind) { return (kind == "assignment-camel") ? "assignment" : kind }
    function fail(msg) { print "vetdd_find_secrets: " msg > "/dev/stderr"; exit 2 }
    BEGIN {
      WIN = 4096; OVL = 512; CTX = 512
      HEX = "0123456789abcdef"
      w = "[A-Za-z0-9_-]"; an = "[A-Za-z0-9]"
      # After the key of an assignment: an optional closing quote, ":" or "=", an optional opening
      # quote, and 8 value characters.
      # A quoted value may hold spaces (a passphrase); an unquoted one ends at the first space.
      val = "[\\\\]?[\"'\'']?[ \t]*[:=][ \t]*([\\\\]?[\"'\'']" rep("[^\"'\''\\\\]", 8) \
            "|" rep("[^ \t\"'\''\\\\]", 8) ")"
      add("private-key", "-----BEGIN [A-Z ]*PRIVATE KEY( BLOCK)?-----")
      add("aws-key", "AKIA" rep("[0-9A-Z]", 16))
      add("github-token", "gh[pousr]_" rep(an, 20))
      add("github-pat", "github_pat_" rep("[A-Za-z0-9_]", 22))
      add("slack-token", "xox[abprs]-" rep("[0-9A-Za-z-]", 10))
      add("openai-key", "sk-" rep(w, 20))
      add("anthropic-key", "sk-ant-" rep(w, 20))
      add("npm-token", "npm_" rep(an, 36))
      add("google-api-key", "AIza" rep(w, 35))
      add("stripe-key", "[sr]k_(live|test)_" rep(an, 16))
      add("gitlab-token", "glpat-" rep(w, 20))
      # The header, a dot, and the first 10 characters of the payload (any: "{ " encodes as "eyA"): a
      # short shape, so a JWT with a long payload still lies whole inside one search window.
      add("jwt", "eyJ" rep(w, 10) w "*[.]" rep(w, 10))
      # Matched against the lower-cased line.
      add("bearer-token", "bearer[ \t]+" rep("[a-z0-9._~+/-]", 20))
      # Matched against the lower-cased line.
      add("basic-auth", "authorization[\\\\]?[\"'\'']?[ \t]*[:=][ \t]*[\\\\]?[\"'\'']?basic[ \t]+" rep("[a-z0-9+/]", 16))
      add("url-credentials", "://[^/:@ \t]*:[^/:@ \t]+@")
      add("email", "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z][A-Za-z]+")
      # Matched against the lower-cased line.
      add("assignment", "(password|passwd|secret|token|api[_-]?key)(_[a-z0-9]+)*" val)
      # A camelCase key, matched against the line as it is and reported as an assignment.
      add("assignment-camel", "[A-Za-z0-9_]*[a-z0-9](Secret|Token|Password|Passwd|ApiKey)" val)
      # Escapes that stand between a token and the text before it (see the top of this file).
      ESC_ANSI = "(\033|[\\\\](033|x1[bB]|e|u001[bB]))[[][0-9;]*m"
      ESC_U = "[\\\\]u" rep("[0-9A-Fa-f]", 4)
      ESC_C = "[\\\\][nrt]"
      LOWER["assignment"] = 1; LOWER["bearer-token"] = 1; LOWER["basic-auth"] = 1
      # The pattern kinds and VETDD_SECRET_KINDS must name the same kinds.
      nn = split(kinds, KN, " ")
      for (j = 1; j <= nn; j++) KNOWN[KN[j]] = 1
      for (i = 1; i <= nk; i++) {
        if (!(reported(K[i]) in KNOWN)) fail("kind " reported(K[i]) " is not in VETDD_SECRET_KINDS")
        HAS[reported(K[i])] = 1
      }
      for (j = 1; j <= nn; j++) if (!(KN[j] in HAS)) fail("VETDD_SECRET_KINDS names " KN[j] ", which has no pattern")
      ns = split(skip, SK, " ")
      for (j = 1; j <= ns; j++) SKIP[SK[j]] = 1
    }
    # unescape(s): s with the escapes above turned into spaces.
    function unescape(s,   c, h, lo, up, rx, ch) {
      # First give back what JSON may write escaped: "\/", and every printable ASCII character written
      # as \u00XX (gh\u0070_... is ghp_...). One gsub per character code, and only on a line that has
      # such an escape, so a long line stays linear.
      gsub("[\\\\]/", "/", s)
      if (index(s, "\\u00") || index(s, "\\U00")) {
        for (c = 32; c < 127; c++) {
          h = substr(HEX, int(c / 16) + 1, 1); lo = substr(HEX, c % 16 + 1, 1); up = toupper(lo)
          rx = "[\\\\][uU]00" h ((lo == up) ? lo : "[" lo up "]")
          ch = sprintf("%c", c)
          if (ch == "&" || ch == "\\") ch = "\\" ch
          gsub(rx, ch, s)
        }
      }
      gsub(ESC_ANSI, " ", s); gsub(ESC_U, " ", s); gsub(ESC_C, " ", s)
      return s
    }
    # exempt(kind, m, head, tail): 1 when the match m is not a secret; head is the line before it,
    # tail the line from the match on.
    function exempt(kind, m, head, tail,   before, at, lp, domain, v, quoted) {
      before = substr(head, length(head), 1)
      if (kind != "private-key" && kind != "email" && kind != "url-credentials" && before ~ /[A-Za-z0-9]/) return 1
      if (kind == "openai-key") return (m ~ /^sk-ant-/)
      if (kind == "url-credentials") {
        v = substr(m, 4, length(m) - 4); sub(/^[^:]*:/, "", v)
        return (tolower(v) ~ /^([$]|<|[[]redacted|[*][*][*])/)
      }
      if (kind == "email") {
        # An SSH remote in the scp form (git@host:org/repo.git, git@host:org/repo, git@host:repo.git,
        # deploy@host:~/app, git@host:/srv/repo.git) or after ssh:// (ssh://git@host/x). Not an
        # address then ":password" (curl -u alice@corp.io:S3cretPass).
        v = substr(tail, length(m) + 1)
        if (v ~ /^:(~?\/|[A-Za-z0-9_.-]+\/)/ || v ~ /^:[A-Za-z0-9_.-]+[.]git([^A-Za-z0-9]|$)/) return 1
        if (tolower(head) ~ /ssh:\/\/$/) return 1
        m = tolower(m); at = index(m, "@")
        lp = substr(m, 1, at - 1); domain = substr(m, at + 1)
        if (lp == "" || lp == "noreply") return 1
        # A file name such as icon@2x.png or pkg@1.0.0.min.js. Only extensions that are not also
        # country codes: .md, .sh, .py, .rs, and .pl are real domains.
        if (domain ~ /[.](png|jpe?g|gif|svg|webp|ico|css|js|mjs|cjs|ts|tsx|jsx|json|jsonl|lock|map|txt|log|ya?ml|toml|html?|xml)$/) return 1
        if (domain ~ /(^|[.])(example[.](com|org|net)|localhost)$/) return 1
        return (domain ~ /[.](example|invalid|test|localhost)$/)
      }
      if (kind == "assignment" || kind == "assignment-camel") {
        v = tail; sub(/^[^:=]*[:=][ \t]*/, "", v)
        quoted = (v ~ /^[\\]?["'\'']/)
        sub(/^[\\]?["'\'']/, "", v)
        if (match(v, /[ \t"'\''\\]/)) v = substr(v, 1, RSTART - 1)
        v = tolower(v)
        if (v ~ /^([{][{]|[$]|<|redacted|[[]redacted|xxx|your)/) return 1
        # A quoted value is a string, even with a dot or a parenthesis ("john.smith2024").
        if (quoted) return 0
        # Unquoted: a call such as getToken(req), or a member access such as req.headers.authorization
        # or process.env.token.
        if (index(v, "(") > 0 || v ~ /^[a-z_][a-z0-9_]*[.][a-z_]/) return 1
        # Unquoted: an identifier is not a secret. A camelCase key counts only as .npmrc has it.
        if (kind == "assignment-camel") return (m !~ /^_authToken=/)
        if (match(v, /^[a-z0-9_+\/=-]+/)) v = substr(v, 1, RLENGTH); else v = ""
        return !(length(v) >= 16 && v ~ /[0-9]/ && v ~ /[a-z]/)
      }
      return 0
    }
    # found(s, i): 1 when s (the global CTXS from position CBASE + 1 on) holds a match of kind i that
    # is not exempt. After an exempt address the
    # search goes on after it, not inside it ("oreply@..." is not a new address); after any other
    # exempt match it goes on one character later, so a match that starts inside it is still found
    # ("mysecret_token = ..." is exempt as "secret_token", then found as "token").
    function found(s, i,   off, p, n, a) {
      off = 0
      while (match(substr(s, off + 1), R[i])) {
        p = off + RSTART; n = RLENGTH
        # The context exempt() reads comes from CTXS, the window with CTX more characters of the line
        # on each side, so a window edge never cuts it.
        a = CBASE + p
        if (!exempt(K[i], substr(s, p, n), substr(CTXS, (a > CTX) ? a - CTX : 1, (a > CTX) ? CTX : a - 1),
                    substr(CTXS, a, n + CTX))) return 1
        off = (K[i] == "email") ? p + n - 1 : p
      }
      return 0
    }
    # found_windowed(s, i): found() over windows of WIN characters that overlap by OVL. found()
    # copies the rest of the line on every exempt match, so on a long line full of look-alikes
    # (a bundle, a transcript line) it grows with the square of the length; windows keep it linear.
    # Every kind matches a short local shape, so a secret up to OVL characters long that crosses a
    # window edge still lies whole inside the next window.
    function found_windowed(s, i,   len, start, cs) {
      len = length(s)
      # CTXS and CBASE are globals, cut once per window: the substr of this awk walks the whole string it is
      # given, so exempt() must never slice the full line.
      if (len <= WIN) { CTXS = s; CBASE = 0; return found(s, i) }
      for (start = 1; ; start += WIN - OVL) {
        cs = (start > CTX) ? start - CTX : 1
        CTXS = substr(s, cs, WIN + 2 * CTX); CBASE = start - cs
        if (found(substr(s, start, WIN), i)) return 1
        if (start + WIN - 1 >= len) return 0
      }
    }
    {
      line = unescape($0); low = tolower(line); split("", seen)
      for (i = 1; i <= nk; i++) {
        kind = reported(K[i])
        if (!(kind in seen) && !(kind in SKIP) && found_windowed((K[i] in LOWER) ? low : line, i)) {
          seen[kind] = 1; print label ":" ((tag != "") ? tag : FNR) ": secret: " kind
        }
      }
    }
  '
}
