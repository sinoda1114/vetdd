#!/usr/bin/env bash
# Record one oracle run as evidence for a slice.
# Usage: evidence.sh <slice-id> <kind> [--outcome <o>] [--infra-exit <code>]... [--seam <s>]
#                    [--oracle-version <v>] [--oracle-file <path>]... [--test-report jest-json:<path>]
#                    -- <command...>
# kind: calibration | before | after | integrated
# outcome: pass | target_failure | infrastructure_error | inconclusive
#   default: exit 0 -> pass, 126/127 (not runnable) -> infrastructure_error, else target_failure
#   --infra-exit <code> declares another exit code that means "could not observe" (for example a
#   verify script's exit 2), so it is recorded as infrastructure_error and never counts as red
# --test-report: the runner's JSON report at <path> (under .vetdd/ or git-ignored) is deleted before
#   the run and read after it; its counts go on the run as `tests`. It never changes the outcome.
# The log and the run entry are always written. Exit 1 when the run violates its kind
# (before must be target_failure; after/integrated must be pass), 2 on usage errors.
set -u

die() { printf 'evidence.sh: %s\n' "$1" >&2; exit 2; }

unset CDPATH  # `cd dir` must never resolve through CDPATH or print a path
. "${BASH_SOURCE[0]%/*}/lib/common.sh"
vetdd_require_jq evidence.sh
. "${BASH_SOURCE[0]%/*}/lib/tree-hash.sh"
. "${BASH_SOURCE[0]%/*}/lib/test-report.sh"

[ $# -ge 2 ] || die "usage: evidence.sh <slice-id> <kind> [options] -- <command...>"
slice="$1"; kind="$2"; shift 2
vetdd_is_slice_id "$slice" || die "invalid slice id '$slice' (letters, digits, . _ -; starting with a letter or digit)"
case "$kind" in
  calibration|before|after|integrated) ;;
  *) die "invalid kind '$kind' (calibration|before|after|integrated)" ;;
esac

outcome_opt=""; seam_opt=""; seam_set=0; version_opt=""; version_set=0; infra_exits=" 126 127 "
oracle_files=(); report_opt=""
while [ $# -gt 0 ]; do
  case "$1" in
    --outcome) [ $# -ge 2 ] || die "--outcome needs a value"; outcome_opt="$2"; shift 2 ;;
    --infra-exit) [ $# -ge 2 ] || die "--infra-exit needs an exit code"
      case "$2" in [1-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5]) ;; *) die "--infra-exit takes an exit code from 1 to 255, got '$2'" ;; esac
      infra_exits="$infra_exits$2 "; shift 2 ;;
    --seam) [ $# -ge 2 ] || die "--seam needs a value"; seam_opt="$2"; seam_set=1; shift 2 ;;
    --oracle-version) [ $# -ge 2 ] || die "--oracle-version needs a value"
      # The version is printed by check-evidence: letters, digits, . _ - only.
      vetdd_is_slice_id "$2" || die "--oracle-version takes letters, digits, and . _ - (got an unsupported value)"
      version_opt="$2"; version_set=1; shift 2 ;;
    --oracle-file) [ $# -ge 2 ] || die "--oracle-file needs a value"; oracle_files+=("$2"); shift 2 ;;
    --test-report) [ $# -ge 2 ] || die "--test-report needs jest-json:<path>"
      case "$2" in jest-json:?*) report_opt="${2#jest-json:}" ;; *) die "--test-report takes jest-json:<path>" ;; esac
      shift 2 ;;
    --) shift; break ;;
    *) die "unexpected argument '$1' (put the command after --)" ;;
  esac
done
[ $# -ge 1 ] || die "no command given after --"
case "$outcome_opt" in
  ""|pass|target_failure|infrastructure_error|inconclusive) ;;
  *) die "invalid outcome '$outcome_opt' (pass|target_failure|infrastructure_error|inconclusive)" ;;
esac

root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
root="$(cd "$root" && pwd -P)"
prefix="$(git rev-parse --show-prefix)"
cwd_rel="${prefix%/}"; [ -n "$cwd_rel" ] || cwd_rel="."

# Resolve oracle files to repo-relative paths before running anything.
rel_files=()
for f in ${oracle_files[@]+"${oracle_files[@]}"}; do
  case "$f" in -*) f="./$f" ;; esac  # dirname would read it as an option
  [ -f "$f" ] || die "oracle file not found: $f"
  fdir="$(cd "$(dirname "$f")" && pwd -P)"
  # The on-disk spelling: an oracle is identified by its paths (check-evidence rule 8).
  abs="$fdir/$(vetdd_disk_name "$fdir" "$f")"
  case "$abs" in
    "$root"/*) rel="$(vetdd_disk_path "$root" "${abs#"$root"/}")" ;;
    *) die "oracle file is a symbolic link or outside the repository: $f" ;;
  esac
  vetdd_inside_repo "$root" "$rel" || die "oracle file is a symbolic link or outside the repository: $f"
  rel_files+=("$rel")
done
# One entry per file: a file named twice (test.sh and ./test.sh) is still one oracle file.
if [ ${#rel_files[@]} -gt 1 ]; then
  deduped=()
  while IFS= read -r f; do deduped+=("$f"); done < <(printf '%s\n' "${rel_files[@]}" | awk '!seen[$0]++')
  rel_files=("${deduped[@]}")
fi

report_rel=""
if [ -n "$report_opt" ]; then
  report_rel="$(vetdd_report_rel "$root" "$prefix" "$report_opt")" \
    || die "--test-report path is a symbolic link or outside the repository: $report_opt"
  vetdd_report_allowed "$root" "$report_rel" \
    || die "--test-report path must be under .vetdd/ (not .vetdd/evidence/) or git-ignored: $report_opt"
fi

dir="$root/.vetdd/evidence/$slice"
meta="$dir/meta.json"
mkdir -p "$dir/runs" || die "cannot create $dir"
if [ ! -f "$meta" ]; then
  jq -n --arg s "$slice" '{slice_id: $s, oracle: {seam: null, version: null, files: []}, runs: []}' > "$meta"
fi

# Inherited paths come from meta.json: check them before the command runs, as for --oracle-file.
if [ ${#rel_files[@]} -eq 0 ]; then
  jq -e 'all(.oracle.files[]?; (.path | type) == "string" and (.path | explode | all(. > 31 and (. < 127 or . > 159))))' \
    "$meta" >/dev/null 2>&1 || die "an inherited oracle path in $meta is malformed"
  while IFS= read -r p; do
    vetdd_inside_repo "$root" "$p" || die "inherited oracle file is a symbolic link or outside the repository: $p"
  done < <(jq -r '.oracle.files[]?.path' "$meta")
fi

seq=$(( $(jq '[.runs[].seq] | max // 0' "$meta") + 1 ))
log_rel="runs/$(printf '%03d' "$seq")-$kind.log"
head_sha="$(git rev-parse --verify -q HEAD || true)"
tree_hash="$(vetdd_tree_hash "$root")" || die "could not hash the working tree"
node_version=""
if command -v node >/dev/null 2>&1; then node_version="$(node --version 2>/dev/null || true)"; fi

# A stale report from an earlier run must never be read as this run's.
if [ -n "$report_rel" ]; then rm -f -- "$root/$report_rel" || die "cannot remove the stale test report $report_opt"; fi
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
"$@" 2>&1 | tee "$dir/$log_rel"
exit_code=${PIPESTATUS[0]}
ended_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

outcome="$outcome_opt"
if [ -z "$outcome" ]; then
  case "$exit_code" in
    0) outcome=pass ;;
    *) case "$infra_exits" in *" $exit_code "*) outcome=infrastructure_error ;; *) outcome=target_failure ;; esac ;;
  esac
fi

required=""
case "$kind" in
  before) required=target_failure ;;
  after|integrated) required=pass ;;
esac
accepted=true
tests_json=null
if [ -n "$report_rel" ]; then
  tests_json="$(vetdd_test_report_import "$root" "$report_rel" "$dir/${log_rel%.log}.tests.json")" \
    || tests_json='{"format": "jest-json", "status": "invalid"}'  # the run is recorded regardless
  printf '%s' "$tests_json" | jq -e 'type == "object"' >/dev/null 2>&1 \
    || tests_json='{"format": "jest-json", "status": "invalid"}'
fi
if [ -n "$required" ] && [ "$outcome" != "$required" ]; then accepted=false; fi

# hash_files: repo-relative paths on stdin -> JSON [{path, sha256}] (sha256 null if missing)
hash_files() {
  local p sum
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    # Checked again here: the command that just ran could have swapped the file for a link.
    sum=""; vetdd_inside_repo "$root" "$p" && [ -f "$root/$p" ] && sum="$(vetdd_sha256 "$root/$p")"
    jq -n --arg p "$p" --arg s "$sum" '{path: $p, sha256: (if $s == "" then null else $s end)}'
  done | jq -s '.'
}

# Oracle: options override, anything unspecified is inherited; files are hashed now.
if [ ${#rel_files[@]} -gt 0 ]; then
  files_json="$(printf '%s\n' "${rel_files[@]}" | hash_files)"
else
  files_json="$(jq -r '.oracle.files[].path' "$meta" | hash_files)"
fi

# NUL-split the argv so that arguments like --prefix never reach jq's option parser.
cmd_json="$(printf '%s\0' "$@" | jq -Rs 'split("\u0000") | .[:-1]')"
tmp_meta="$meta.tmp.$$"
jq --argjson seq "$seq" --arg kind "$kind" --argjson exit_code "$exit_code" \
  --arg outcome "$outcome" --argjson accepted "$accepted" \
  --arg started_at "$started_at" --arg ended_at "$ended_at" --arg log "$log_rel" \
  --arg head_sha "$head_sha" --arg tree_hash "$tree_hash" \
  --arg cwd "$cwd_rel" --arg node_version "$node_version" \
  --argjson seam_set "$seam_set" --arg seam "$seam_opt" \
  --argjson version_set "$version_set" --arg version "$version_opt" \
  --argjson files "$files_json" --argjson tests "$tests_json" '
  (.oracle
    | (if $seam_set == 1 then .seam = $seam else . end)
    | (if $version_set == 1 then .version = $version else . end)
    | .files = $files) as $oracle
  # A rejected run keeps its own record but never becomes the oracle later runs inherit.
  | (if $accepted then .oracle = $oracle else . end)
  | .runs += [{
      seq: $seq, kind: $kind, cmd: $cmd,
      exit_code: $exit_code, outcome: $outcome, accepted: $accepted,
      started_at: $started_at, ended_at: $ended_at, log: $log,
      tree: {head_sha: (if $head_sha == "" then null else $head_sha end), tree_hash: $tree_hash},
      conditions: {
        cwd: $cwd,
        node_version: (if $node_version == "" then null else $node_version end),
        env_keys: (env | keys | map(select(startswith("VETDD_"))) | sort)
      },
      oracle: $oracle
    } + (if $tests == null then {} else {tests: $tests} end)]' --argjson cmd "$cmd_json" < "$meta" > "$tmp_meta" && mv "$tmp_meta" "$meta" || {
  rm -f "$tmp_meta"; die "could not update $meta"
}

if [ "$accepted" = false ]; then
  printf 'evidence.sh: %s run must end %s, got %s (exit %s); recorded as run %s with accepted=false\n' \
    "$kind" "$required" "$outcome" "$exit_code" "$seq" >&2
  exit 1
fi
printf 'evidence.sh: recorded %s run %s for %s: %s\n' "$kind" "$seq" "$slice" "$outcome" >&2
exit 0
