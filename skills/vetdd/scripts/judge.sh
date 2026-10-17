#!/usr/bin/env bash
# Run the blinded judge (a different model family, via codex) over a sanitized candidates directory.
# Usage: judge.sh --rubric <file> --candidates <dir> --out <json> --eval-id <id> --run-id <id>
#                 --rubric-version <n> [--conditions <file>] [--model <m>] [--effort <e>]
#                 [--extra-layout <text>] [--extra-words <file>] [--allow-secrets <glob>[:<kind>,...]]...
# Steps: copy the label directories (c1/, c2/, ...) of <candidates> and the rubric (as rubric.md)
# into a fresh private temporary directory outside any repository; refuse unless check-blind.sh
# (judge profile, plus --extra-words and, in an A/B eval (variants.json in the run directory above
# <candidates>), the absolute paths of <candidates>, of the run directory, and of its git root, each
# also with "/" as "\/") passes on that copy and on the conditions, the extra layout, the eval id,
# and the run id. A final verdict (no variants.json) has no label-to-variant map to hide, so no
# absolute path is refused there. Render references/judge-prompt.md; run `codex exec` read-only with
# -C set to the copy and schemas/verdict.schema.json, isolated from the user's codex setup: CODEX_HOME
# is a second private temporary directory holding only a link to the user's auth.json (from
# $CODEX_HOME, else ~/.codex; a refreshed token is written back; a keyring login stops with exit 3),
# also its HOME (a codex that cannot start there, such as one behind a node version manager's shim,
# stops with exit 3 before exec), the
# login is kept in that file whatever codex's default store, and exec runs --ephemeral
# --ignore-user-config --ignore-rules with web search off and the core environment only, so the user's
# config (MCP servers, tools, a model provider of their own), AGENTS.md, personal skills, rules, and
# sessions never reach the judge; refuse the reply if it holds a secret-shaped
# string (lib/secret-patterns.sh, every kind: --allow-secrets covers input only); write the reply verbatim to
# <out>, the judge metadata to <out>.meta.json, and codex's own output to
# <git root>/.vetdd/judge-logs/<eval-id>-<run-id>.log (the git root of <out>'s directory, else of the
# current directory; the path is printed); run check-verdict.sh with the labels, the rubric, and the
# ids. <candidates> itself is never written.
# --allow-secrets <glob>[:<kind>,...] is passed to check-blind.sh: paths of the copy that match the
# glob (c1/artifact/..., relative to the copy; a --conditions file by its path as given) skip the
# secret check for the kinds named, or for every kind when none is named. It never applies to the
# reply's secret check, which covers every kind.
# Use it only for test data a human confirmed, naming only the kinds confirmed; the values are
# recorded in <out>.meta.json (allowed_secrets).
# --allow-words <glob>:<word>[,<word>]... is passed to check-blind.sh: product words a human confirmed
# (an SDK named after a model's maker), recorded in <out>.meta.json (allowed_words). A final verdict
# (no variants.json) also passes --final: the origin words (variant, baseline, winner) are product
# words there.
# Defaults: --model `models.sh judge`, --effort `models.sh judge-effort`; both are validated by
# models.sh. VETDD_CODEX_BIN overrides the codex binary (tests use a fake). codex runs with an
# allowlisted environment (PATH, user, locale, terminal, proxy, and CA variables, plus the names in
# VETDD_JUDGE_KEEP_ENV), with HOME and CODEX_HOME the private ones.
# Exit: 0 verdict written and checked; 1 a local step failed (temporary directory, copy, write);
#       2 usage error; 3 codex missing, unable to start with the private HOME, without the isolation
#       flags, or not logged in; 4 the judge's input is not blind;
#       5 the verdict failed its checks (left at <out>); 6 codex exec failed;
#       7 check-verdict.sh could not run (the verdict is left at <out>, unchecked);
#       8 the judge's reply holds a secret-shaped string (not written to <out>; read the judge log).
set -u
unset CDPATH

die() { printf 'judge.sh: %s\n' "$1" >&2; exit "${2:-2}"; }

here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
skill="${here%/*}"
. "$here/lib/common.sh"
. "$here/lib/secret-patterns.sh"
vetdd_require_jq judge.sh

rubric=""; cand=""; out=""; eval_id=""; run_id=""; version=""; conditions=""; model=""; effort=""
extra_layout=""; extra_words=""; allow_secrets=(); allow_words=()
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || die "$1 needs a value"
  case "$1" in
    --rubric) rubric="$2" ;;
    --candidates) cand="$2" ;;
    --out) out="$2" ;;
    --eval-id) eval_id="$2" ;;
    --run-id) run_id="$2" ;;
    --rubric-version) version="$2" ;;
    --conditions) conditions="$2" ;;
    --model) model="$2" ;;
    --effort) effort="$2" ;;
    --extra-layout) extra_layout="$2" ;;
    --extra-words) extra_words="$2" ;;
    --allow-secrets) allow_secrets+=("$2") ;;
    --allow-words) allow_words+=("$2") ;;
    *) die "unexpected argument '$1'" ;;
  esac
  shift 2
done
for pair in "--rubric:$rubric" "--candidates:$cand" "--out:$out" "--eval-id:$eval_id" \
            "--run-id:$run_id" "--rubric-version:$version"; do
  [ -n "${pair#*:}" ] || die "${pair%%:*} is required"
done
case "$version" in *[!0-9]*|0*) die "--rubric-version must be a positive integer" ;; esac
# The ids name the log file, so they must stay plain names.
vetdd_is_slice_id "$eval_id" || die "--eval-id must be letters, digits, . _ - (got '$eval_id')"
vetdd_is_slice_id "$run_id" || die "--run-id must be letters, digits, . _ - (got '$run_id')"
[ -f "$rubric" ] || die "rubric not found: $rubric"
[ -d "$cand" ] || die "candidates directory not found: $cand"
[ -z "$conditions" ] || [ -f "$conditions" ] || die "conditions file not found: $conditions"
[ -z "$extra_words" ] || [ -f "$extra_words" ] || die "extra words file not found: $extra_words"
if [ -n "$model" ]; then
  model="$(VETDD_MODEL_JUDGE="$model" "$here/models.sh" judge)" || die "invalid --model"
else
  model="$("$here/models.sh" judge)" || die "models.sh judge failed"
fi
if [ -n "$effort" ]; then
  effort="$(VETDD_MODEL_JUDGE_EFFORT="$effort" "$here/models.sh" judge-effort)" || die "invalid --effort"
else
  effort="$("$here/models.sh" judge-effort)" || die "models.sh judge-effort failed"
fi

cand="$(cd "$cand" && pwd)"
labels=""
for d in "$cand"/c[0-9]*; do
  [ -d "$d" ] || continue
  l="${d##*/}"
  case "${l#c}" in ""|*[!0-9]*) continue ;; esac
  labels="$labels${labels:+,}$l"
done
[ -n "$labels" ] || die "no label directories (c1, c2, ...) in $cand"

# The judge's transcript is a record of the verdict (principle 3). It goes outside the run
# directory, to the gitignored .vetdd/ at the git root, never beside the candidates.
out_dir="$(dirname "$out")"
mkdir -p "$out_dir" || die "cannot create $out_dir" 1
out_dir="$(cd "$out_dir" && pwd)"
if cdup="$(git -C "$out_dir" rev-parse --show-cdup 2>/dev/null)"; then
  root="$(cd "$out_dir/$cdup" && pwd)"
elif cdup="$(git rev-parse --show-cdup 2>/dev/null)"; then
  root="$(cd "./$cdup" && pwd)"
else
  die "--out must be inside a git repository (the judge log goes to <git root>/.vetdd/judge-logs)"
fi
log="$root/.vetdd/judge-logs/$eval_id-$run_id.log"

codex="${VETDD_CODEX_BIN:-codex}"
# VETDD_JUDGE_KEEP_ENV names more variables codex keeps (a proxy or CA bundle of one's own): split
# without pathname expansion and checked here, before anything about codex itself.
read -r -a keep_extra <<< "${VETDD_JUDGE_KEEP_ENV:-}"
for n in ${keep_extra[@]+"${keep_extra[@]}"}; do
  case "$n" in
    HOME|CODEX_HOME) die "VETDD_JUDGE_KEEP_ENV cannot keep $n: the judge's is always the private one" 2 ;;
    # Names that would undo the isolation: codex's own settings, a model provider, a version manager's
    # settings, or code loaded into a process.
    CODEX_*|OPENAI_*|XDG_*|MISE_*|ASDF_*|VOLTA_*|NVM_*|NODE_*|LD_*|DYLD_*|BASH_ENV|ENV)
      die "VETDD_JUDGE_KEEP_ENV cannot keep $n: it would undo the judge's isolation from your setup" 2 ;;
    [0-9]*|*[!A-Za-z0-9_]*) die "VETDD_JUDGE_KEEP_ENV holds $(printf '%s' "$n" | vetdd_printable), which is not a variable name" 2 ;;
  esac
done
command -v "$codex" >/dev/null 2>&1 \
  || die "codex CLI not found ($codex); install it (npm install -g @openai/codex) or set VETDD_CODEX_BIN" 3
# The judge runs with a CODEX_HOME of its own that holds only a link to the user's auth.json: the
# user's config (MCP servers, tools), instructions (AGENTS.md), rules, and sessions never reach it.
# It keeps no secret from the judge: the read-only sandbox reads the whole disk, the link included, as
# it could read the user's auth.json before; the reply's secret check covers what the judge quotes.
# A login kept in the OS keyring is filed under the user's CODEX_HOME and cannot be lent this way.
user_home="${CODEX_HOME:-}"
[ -n "$user_home" ] || { [ -n "${HOME:-}" ] || die "neither CODEX_HOME nor HOME is set; cannot find the codex login" 3; user_home="$HOME/.codex"; }
case "$user_home" in /*) ;; *) user_home="$PWD/$user_home" ;; esac
[ -f "$user_home/auth.json" ] \
  || die "the judge needs codex's file login, and $user_home/auth.json is missing (a keyring login cannot reach the judge's private CODEX_HOME); set cli_auth_credentials_store = \"file\" in $user_home/config.toml and run \`codex login\`" 3
auth_sum="$(cksum < "$user_home/auth.json")"
jhome="$(mktemp -d "${TMPDIR:-/tmp}/vetdd-codex.XXXXXX")" || die "cannot create a temporary directory" 1
# A token codex refreshes may come back as a file in place of the link (written aside, then renamed):
# write it back, or the user's login keeps the spent token. Only a JSON object, only when the user's
# file is as it was at the start (their own codex may have refreshed it meanwhile), and atomically: a
# private file beside the link's target, renamed over it, so a link the user keeps stays a link.
login_note() { printf 'judge.sh: codex refreshed its login during the judge run; %s. If codex then says you are logged out, run `codex login`\n' "$1" >&2; }
keep_login() {
  [ -f "$jhome/auth.json" ] && [ ! -L "$jhome/auth.json" ] || return 0
  local t="$user_home/auth.json" l n=0
  jq -e 'type == "object"' "$jhome/auth.json" >/dev/null 2>&1 || { login_note "it is not a JSON object, so it was not written back"; return 0; }
  [ "$(cksum < "$t" 2>/dev/null)" = "$auth_sum" ] || { login_note "your auth.json changed meanwhile, so yours was kept"; return 0; }
  while [ -L "$t" ] && [ "$n" -lt 20 ]; do
    l="$(readlink "$t")"; case "$l" in /*) t="$l" ;; *) t="${t%/*}/$l" ;; esac; n=$((n + 1))
  done
  { (umask 077 && cp "$jhome/auth.json" "$t.vetdd.$$") && mv -f "$t.vetdd.$$" "$t"; } \
    || { rm -f "$t.vetdd.$$"; login_note "it could not be written back to $t"; }
}
trap 'keep_login; rm -rf "$jhome"' EXIT
ln -s "$user_home/auth.json" "$jhome/auth.json" || die "cannot link the codex login into $jhome" 1
export CODEX_HOME="$jhome"
# Every codex call from here runs with the private HOME too, so codex is checked to start there before
# exec. A codex that starts through a node version manager's shim (an npm install under mise, asdf,
# Volta) looks for its versions under $HOME and fails there: it stops here with a clear message, not in
# exec as a judge failure. codex gets an allowlisted environment and nothing else of the caller's: a
# variable that points a version manager at the user's settings (MISE_GLOBAL_CONFIG_FILE, XDG_*, ...)
# would let its shim start and apply them, and they may set CODEX_HOME or HOME and undo the isolation.
# Every other exported variable is unset in a subshell before exec, so the kept values stay in the
# environment (never on a command line, where ps and audit logs read them) and a path with = in it
# runs as it is. HOME and CODEX_HOME are always the private ones.
keep_names=" PATH USER LOGNAME SHELL TMPDIR TERM LANG LC_ALL LC_CTYPE LC_MESSAGES TZ HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY http_proxy https_proxy all_proxy no_proxy SSL_CERT_FILE SSL_CERT_DIR ${keep_extra[*]+${keep_extra[*]}} "
compgen -e > /dev/null 2>&1 || die "this bash has no compgen, which judge.sh needs to clear codex's environment" 1
codex_private() (
  for n in $(compgen -e); do
    case "$keep_names" in *" $n "*) ;; *) unset "$n" 2>/dev/null ;; esac
  done
  export HOME="$jhome" CODEX_HOME="$jhome"
  exec "$codex" "$@"
)
started="$(codex_private --version < /dev/null 2>&1)" \
  || die "codex ($codex) does not start with the judge's private HOME ($(printf '%s' "$started" | tail -n 1 | vetdd_printable)); a codex started through a node version manager's shim needs HOME. Install the standalone codex, or set VETDD_CODEX_BIN to a codex that starts without HOME" 3
# The flags (codex 0.159 and later) are checked on the codex that runs, so an older one stops here, not in exec.
help="$(codex_private exec --help < /dev/null 2>/dev/null)"; missing=""
for f in --ephemeral --ignore-user-config --ignore-rules; do
  printf '%s\n' "$help" | grep -qe "$f" || missing="$missing $f"
done
[ -z "$missing" ] \
  || die "codex ($codex) has no exec$missing, which the judge's isolation needs; update it (npm install -g @openai/codex)" 3
# The login stays in the linked auth.json whatever codex's default store (keyring, auto): the user's
# config.toml, where they chose the file store, is not read here.
login="$(codex_private login status -c 'cli_auth_credentials_store="file"' < /dev/null 2>&1)" \
  || die "codex is not logged in ($login); run \`codex login\` first" 3

# Every temporary file lives in one private directory. The judge's working directory is a copy
# inside it, so a relative path from there reaches only the copy and this directory, never the
# run directory (variants.json, synthesis.md). This is not isolation: the read-only sandbox stops
# writes, not reads, and an absolute path still reaches the run directory. Keeping the judge out
# rests on the relative paths, on nothing in the copy naming the original path (the blind check
# below refuses those paths), and on the prompt.
work="$(mktemp -d "${TMPDIR:-/tmp}/vetdd-judge.XXXXXX")" || die "cannot create a temporary directory" 1
trap 'keep_login; rm -rf "$work" "$jhome"' EXIT
jdir="$work/judge"
mkdir "$jdir" "$work/args" || die "cannot create $jdir" 1
! git -C "$jdir" rev-parse --show-toplevel >/dev/null 2>&1 \
  || die "the temporary directory $work is inside a git repository; set TMPDIR to a directory outside any repository" 1
IFS=, read -r -a label_list <<< "$labels"
for l in "${label_list[@]}"; do
  cp -R "$cand/$l" "$jdir/$l" || die "cannot copy $cand/$l" 1
done
cp "$rubric" "$jdir/rubric.md" || die "cannot copy the rubric" 1

# write_path_words <file>: in an A/B eval (variants.json in the run directory above the candidates),
# the absolute paths that would lead the judge from the copy back to variants.json, one per line,
# each as given and with symlinks resolved: the candidates directory, the run directory, and the
# run directory's git root. A final verdict (no variants.json) has no such map to hide, and its
# logs name the project's paths, often the candidates' own; it gets no path words. $HOME is not added
# as such, but it becomes a word when it is the git root (a dotfiles repository), which only refuses
# more. "/" would match every path; it is skipped. Each path is also written with every "/" as
# JSON's "\/" (\/Users\/x\/...). sanitize-candidates.sh collects the same paths.
write_path_words() {
  local run d p top cdup list=""
  : > "$1" || die "cannot write $1" 1
  run="${cand%/*}"; [ -n "$run" ] || run="/"
  [ -f "$run/variants.json" ] || return 0
  # Resolve every form separately and stop on a failure, so a path never drops out of the list.
  for d in "$cand" "$run"; do
    p="$(cd "$d" && pwd -P)" && [ -n "$p" ] || die "cannot resolve $d" 1
    list="$list$d
$p
"
  done
  if top="$(git -C "$run" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$top" ]; then
    p="$(cd "$top" && pwd -P)" && cdup="$(git -C "$run" rev-parse --show-cdup)" && [ -n "$p" ] \
      || die "cannot resolve the git root of $run" 1
    list="$list$top
$p
"
    # The root as the user wrote it: the run directory's path with git's "../" steps, which count
    # from the resolved path. Through a symlink that may land elsewhere ($HOME, "/"); such a form
    # is not the root and is dropped.
    if d="$(cd "$run/$cdup" 2>/dev/null && pwd)" && [ "$(cd "$d" 2>/dev/null && pwd -P)" = "$p" ]; then
      list="$list$d
"
    fi
  fi
  list="$(printf '%s' "$list" | awk '$0 != "/"')" || die "cannot list the paths of $cand" 1
  [ -n "$list" ] || return 0
  { printf '%s\n' "$list"; printf '%s\n' "$list" | sed 's|/|\\/|g'; } > "$1" || die "cannot write $1" 1
}

# The judge's input: the copy, and every value that reaches the prompt besides the rubric.
printf '%s\n' "$eval_id" > "$work/args/eval-id"
printf '%s\n' "$run_id" > "$work/args/run-id"
printf '%s\n' "$extra_layout" > "$work/args/extra-layout"
write_path_words "$work/args/paths"
set -- "$jdir" --profile judge \
  --file "$work/args/eval-id" --file "$work/args/run-id" --file "$work/args/extra-layout" \
  --extra-words "$work/args/paths"
[ -z "$conditions" ] || set -- "$@" --file "$conditions"
[ -z "$extra_words" ] || set -- "$@" --extra-words "$extra_words"
for g in ${allow_secrets[@]+"${allow_secrets[@]}"}; do set -- "$@" --allow-secrets "$g"; done
for g in ${allow_words[@]+"${allow_words[@]}"}; do set -- "$@" --allow-words "$g"; done
# A final verdict (no variants.json) has no variant to hide: product words such as a button variant
# or a CSS baseline do not stop it; model names still do.
# Only one label and no variants.json is a final verdict: a hand-made pair (a calibration) keeps the
# origin words checked.
jrun="${cand%/*}"; [ -n "$jrun" ] || jrun="/"
nlabels="$(find "$jdir" -mindepth 1 -maxdepth 1 -type d -name 'c[0-9]*' | wc -l | tr -d ' ')"
[ -f "$jrun/variants.json" ] || [ "$nlabels" != 1 ] || set -- "$@" --final
blind="$("$here/check-blind.sh" "$@" 2>&1)"
case $? in
  0) ;;
  1) # Name the argument files by their option, not by their temporary path.
     printf '%s\n' "$blind" | awk -v p="$work/args/" '{
       while ((i = index($0, p)) > 0) $0 = substr($0, 1, i - 1) "--" substr($0, i + length(p)); print }'
     die "the judge's input is not blind; sanitize the candidates (sanitize-candidates.sh) and the arguments first" 4 ;;
  *) die "check-blind.sh could not run: $blind" ;;
esac
# The argument files sit next to the judge's working directory and name the paths it must not
# reach (args/paths); they served the check and go before the judge starts.
rm -rf "$work/args" && [ ! -e "$work/args" ] || die "cannot remove $work/args before the judge starts" 1

# Render the first fenced block of the prompt template in one pass, so a value that contains
# "{{slot}}" is never expanded again.
cond_text="none recorded"
[ -z "$conditions" ] || cond_text="$(cat "$conditions")"
V_rubric="$(cat "$jdir/rubric.md")" V_conditions="$cond_text" V_rubric_version="$version" \
V_eval_id="$eval_id" V_run_id="$run_id" V_extra_layout="$extra_layout" awk '
  /^```/ { if (inside) { closed = 1; exit } inside = 1; next }
  inside {
    line = $0; rendered = ""
    while (match(line, /[{][{][a-z_]+[}][}]/)) {
      key = "V_" substr(line, RSTART + 2, RLENGTH - 4)
      rendered = rendered substr(line, 1, RSTART - 1) ((key in ENVIRON) ? ENVIRON[key] : substr(line, RSTART, RLENGTH))
      line = substr(line, RSTART + RLENGTH)
    }
    print rendered line
  }
  END { if (!closed) exit 3 }
' "$skill/references/judge-prompt.md" > "$work/prompt.txt" || die "cannot render references/judge-prompt.md" 1

invoked_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mkdir -p "${log%/*}" || die "cannot create ${log%/*}" 1
# HOME is the private home too: codex finds personal skills under ~/.agents/skills. The judge's shell
# gets the core variables only (HOME, PATH, USER, ...): CODEX_HOME and the caller's own stay out.
# The -c keys are read, not ignored: codex 0.159.1 refuses an unknown value of each (measured).
codex_private exec -s read-only -C "$jdir" -m "$model" -c "model_reasoning_effort=\"$effort\"" \
  --ephemeral --ignore-user-config --ignore-rules -c 'web_search="disabled"' -c 'shell_environment_policy.inherit="core"' \
  -c 'cli_auth_credentials_store="file"' \
  --skip-git-repo-check --output-schema "$skill/schemas/verdict.schema.json" -o "$work/reply.json" \
  < "$work/prompt.txt" > "$log" 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
  # The log is the judge's output; strip control characters so it cannot drive the terminal.
  grep -v 'rmcp::transport' "$log" | tail -n 5 | LC_ALL=C tr -d '\000-\010\013-\037\177' >&2
  die "codex exec failed (exit $rc); full output in $log. codex runs with an allowlisted environment: if it needs a variable of yours (a proxy or CA bundle, say), name it in VETDD_JUDGE_KEEP_ENV" 6
fi
printf 'judge log: %s\n' "$log"

# The reply may quote what the judge read, and a candidate's text can steer it to a file outside the
# copy (~/.aws/credentials). <out> may be committed, so a secret-shaped reply is never written there.
# Every kind, always: --allow-secrets covers input paths a human checked, not what the judge may
# have read outside the copy and quoted.
reply_hits="$(vetdd_find_secrets judge-reply < "$work/reply.json")" \
  || die "the secret check on the judge's reply failed; nothing was written to $out" 1
if [ -n "$reply_hits" ]; then
  printf '%s\n' "$reply_hits" | vetdd_printable >&2
  # Keep the reply beside the log (gitignored, outside the run directory) so a human can read it.
  held="${log%.log}.reply.json"
  cp "$work/reply.json" "$held" || die "cannot keep the reply at $held" 1
  die "the judge's reply holds text shaped like a secret; it was not written to $out (--allow-secrets does not apply to the reply). Read the judge log ($log) and the reply ($held) locally: if the hit only quotes test data you allowed, copy the reply to $out and run $here/check-verdict.sh $out --rubric $rubric --labels $labels --eval-id $eval_id --run-id $run_id --rubric-version $version; otherwise treat the run as blocked" 8
fi

cp "$work/reply.json" "$out" || die "cannot write $out" 1
allowed='[]'
for g in ${allow_secrets[@]+"${allow_secrets[@]}"}; do
  allowed="$(jq -c --arg g "$g" '. + [$g]' <<< "$allowed")" || die "cannot record --allow-secrets" 1
done
awords='[]'
for g in ${allow_words[@]+"${allow_words[@]}"}; do
  awords="$(jq -c --arg g "$g" '. + [$g]' <<< "$awords")" || die "cannot record --allow-words" 1
done
jq -n --arg model "$model" --arg effort "$effort" --arg invoked_at "$invoked_at" --arg log "$log" \
  --argjson allowed "$allowed" --argjson awords "$awords" \
  '{model: $model, effort: $effort, invoked_at: $invoked_at, family: "codex", log: $log,
    allowed_secrets: $allowed, allowed_words: $awords}' > "$out.meta.json" \
  || die "cannot write $out.meta.json" 1

"$here/check-verdict.sh" "$out" --rubric "$jdir/rubric.md" --labels "$labels" \
  --eval-id "$eval_id" --run-id "$run_id" --rubric-version "$version"
rc=$?
case "$rc" in
  0) ;;
  12[6-9]|1[3-9][0-9]|2[0-9][0-9]) die "check-verdict.sh could not run (exit $rc); the verdict is left at $out, unchecked" 7 ;;
  *) die "the verdict failed its checks; left at $out" 5 ;;
esac
