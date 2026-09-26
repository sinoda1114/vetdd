#!/usr/bin/env bash
# Run the blinded judge (a different model family, via codex) over a sanitized candidates directory.
# Usage: judge.sh --rubric <file> --candidates <dir> --out <json> --eval-id <id> --run-id <id>
#                 --rubric-version <n> [--conditions <file>] [--model <m>] [--effort <e>]
#                 [--extra-layout <text>] [--extra-words <file>]
# Steps: copy the label directories (c1/, c2/, ...) of <candidates> and the rubric (as rubric.md)
# into a fresh private temporary directory outside any repository; refuse unless check-blind.sh
# (judge profile, plus --extra-words) passes on that copy and on the conditions, the extra layout,
# the eval id, and the run id; render references/judge-prompt.md; run `codex exec` read-only with
# -C set to the copy and schemas/verdict.schema.json; write the reply verbatim to <out>, the judge
# metadata to <out>.meta.json, and codex's own output to <git root>/.vetdd/judge-logs/<eval-id>-<run-id>.log
# (the git root of <out>'s directory, else of the current directory; the path is printed); run
# check-verdict.sh with the labels, the rubric, and the ids. <candidates> itself is never written.
# Defaults: --model `models.sh judge`, --effort `models.sh judge-effort`; both are validated by
# models.sh. VETDD_CODEX_BIN overrides the codex binary (tests use a fake).
# Exit: 0 verdict written and checked; 1 a local step failed (temporary directory, copy, write);
#       2 usage error; 3 codex missing or not logged in; 4 the judge's input is not blind;
#       5 the verdict failed its checks (left at <out>); 6 codex exec failed;
#       7 check-verdict.sh could not run (the verdict is left at <out>, unchecked).
set -u

die() { printf 'judge.sh: %s\n' "$1" >&2; exit "${2:-2}"; }

here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
skill="${here%/*}"
. "$here/lib/common.sh"
vetdd_require_jq judge.sh

rubric=""; cand=""; out=""; eval_id=""; run_id=""; version=""; conditions=""; model=""; effort=""
extra_layout=""; extra_words=""
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
command -v "$codex" >/dev/null 2>&1 \
  || die "codex CLI not found ($codex); install it (npm install -g @openai/codex) or set VETDD_CODEX_BIN" 3
login="$("$codex" login status 2>&1)" \
  || die "codex is not logged in ($login); run \`codex login\` first" 3

# Every temporary file lives in one private directory. The judge's working directory is a copy
# inside it, so a relative path from there reaches only the copy and this directory, never the
# run directory (variants.json, synthesis.md).
work="$(mktemp -d "${TMPDIR:-/tmp}/vetdd-judge.XXXXXX")" || die "cannot create a temporary directory" 1
trap 'rm -rf "$work"' EXIT
jdir="$work/judge"
mkdir "$jdir" "$work/args" || die "cannot create $jdir" 1
! git -C "$jdir" rev-parse --show-toplevel >/dev/null 2>&1 \
  || die "the temporary directory $work is inside a git repository; set TMPDIR to a directory outside any repository" 1
IFS=, read -r -a label_list <<< "$labels"
for l in "${label_list[@]}"; do
  cp -R "$cand/$l" "$jdir/$l" || die "cannot copy $cand/$l" 1
done
cp "$rubric" "$jdir/rubric.md" || die "cannot copy the rubric" 1

# The judge's input: the copy, and every value that reaches the prompt besides the rubric.
printf '%s\n' "$eval_id" > "$work/args/eval-id"
printf '%s\n' "$run_id" > "$work/args/run-id"
printf '%s\n' "$extra_layout" > "$work/args/extra-layout"
set -- "$jdir" --profile judge \
  --file "$work/args/eval-id" --file "$work/args/run-id" --file "$work/args/extra-layout"
[ -z "$conditions" ] || set -- "$@" --file "$conditions"
[ -z "$extra_words" ] || set -- "$@" --extra-words "$extra_words"
blind="$("$here/check-blind.sh" "$@" 2>&1)"
case $? in
  0) ;;
  1) # Name the argument files by their option, not by their temporary path.
     printf '%s\n' "$blind" | awk -v p="$work/args/" '{
       while ((i = index($0, p)) > 0) $0 = substr($0, 1, i - 1) "--" substr($0, i + length(p)); print }'
     die "the judge's input is not blind; sanitize the candidates (sanitize-candidates.sh) and the arguments first" 4 ;;
  *) die "check-blind.sh could not run: $blind" ;;
esac

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
"$codex" exec -s read-only -C "$jdir" -m "$model" -c "model_reasoning_effort=\"$effort\"" \
  --skip-git-repo-check --output-schema "$skill/schemas/verdict.schema.json" -o "$work/reply.json" \
  < "$work/prompt.txt" > "$log" 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
  # The log is the judge's output; strip control characters so it cannot drive the terminal.
  grep -v 'rmcp::transport' "$log" | tail -n 5 | LC_ALL=C tr -d '\000-\010\013-\037\177' >&2
  die "codex exec failed (exit $rc); full output in $log" 6
fi
printf 'judge log: %s\n' "$log"

cp "$work/reply.json" "$out" || die "cannot write $out" 1
jq -n --arg model "$model" --arg effort "$effort" --arg invoked_at "$invoked_at" --arg log "$log" \
  '{model: $model, effort: $effort, invoked_at: $invoked_at, family: "codex", log: $log}' > "$out.meta.json" \
  || die "cannot write $out.meta.json" 1

"$here/check-verdict.sh" "$out" --rubric "$jdir/rubric.md" --labels "$labels" \
  --eval-id "$eval_id" --run-id "$run_id" --rubric-version "$version"
rc=$?
case "$rc" in
  0) ;;
  12[6-9]|1[3-9][0-9]|2[0-9][0-9]) die "check-verdict.sh could not run (exit $rc); the verdict is left at $out, unchecked" 7 ;;
  *) die "the verdict failed its checks; left at $out" 5 ;;
esac
