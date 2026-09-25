#!/usr/bin/env bash
# Record one oracle run as evidence for a slice.
# Usage: evidence.sh <slice-id> <kind> [--outcome <o>] [--seam <s>] [--oracle-version <v>]
#                    [--oracle-file <path>]... -- <command...>
# kind: calibration | before | after | integrated
# outcome: pass | target_failure | infrastructure_error | inconclusive
#   default: exit 0 -> pass, 126/127 (not runnable) -> infrastructure_error, else target_failure
# The log and the run entry are always written. Exit 1 when the run violates its kind
# (before must be target_failure; after/integrated must be pass), 2 on usage errors.
set -u

die() { printf 'evidence.sh: %s\n' "$1" >&2; exit 2; }

. "${BASH_SOURCE[0]%/*}/lib/common.sh"
vetdd_require_jq evidence.sh
. "${BASH_SOURCE[0]%/*}/lib/tree-hash.sh"

[ $# -ge 2 ] || die "usage: evidence.sh <slice-id> <kind> [options] -- <command...>"
slice="$1"; kind="$2"; shift 2
vetdd_is_slice_id "$slice" || die "invalid slice id '$slice' (letters, digits, . _ -; starting with a letter or digit)"
case "$kind" in
  calibration|before|after|integrated) ;;
  *) die "invalid kind '$kind' (calibration|before|after|integrated)" ;;
esac

outcome_opt=""; seam_opt=""; seam_set=0; version_opt=""; version_set=0
oracle_files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --outcome) [ $# -ge 2 ] || die "--outcome needs a value"; outcome_opt="$2"; shift 2 ;;
    --seam) [ $# -ge 2 ] || die "--seam needs a value"; seam_opt="$2"; seam_set=1; shift 2 ;;
    --oracle-version) [ $# -ge 2 ] || die "--oracle-version needs a value"; version_opt="$2"; version_set=1; shift 2 ;;
    --oracle-file) [ $# -ge 2 ] || die "--oracle-file needs a value"; oracle_files+=("$2"); shift 2 ;;
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
  [ -f "$f" ] || die "oracle file not found: $f"
  abs="$(cd "$(dirname "$f")" && pwd -P)/$(basename "$f")"
  case "$abs" in
    "$root"/*) rel_files+=("${abs#"$root"/}") ;;
    *) die "oracle file is outside the repository: $f" ;;
  esac
done

dir="$root/.vetdd/evidence/$slice"
meta="$dir/meta.json"
mkdir -p "$dir/runs" || die "cannot create $dir"
if [ ! -f "$meta" ]; then
  jq -n --arg s "$slice" '{slice_id: $s, oracle: {seam: null, version: null, files: []}, runs: []}' > "$meta"
fi

seq=$(( $(jq '[.runs[].seq] | max // 0' "$meta") + 1 ))
log_rel="runs/$(printf '%03d' "$seq")-$kind.log"
head_sha="$(git rev-parse --verify -q HEAD || true)"
tree_hash="$(vetdd_tree_hash "$root")" || die "could not hash the working tree"
node_version=""
if command -v node >/dev/null 2>&1; then node_version="$(node --version 2>/dev/null || true)"; fi

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
"$@" 2>&1 | tee "$dir/$log_rel"
exit_code=${PIPESTATUS[0]}
ended_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

outcome="$outcome_opt"
if [ -z "$outcome" ]; then
  case "$exit_code" in
    0) outcome=pass ;;
    126|127) outcome=infrastructure_error ;;
    *) outcome=target_failure ;;
  esac
fi

required=""
case "$kind" in
  before) required=target_failure ;;
  after|integrated) required=pass ;;
esac
accepted=true
if [ -n "$required" ] && [ "$outcome" != "$required" ]; then accepted=false; fi

# hash_files: repo-relative paths on stdin -> JSON [{path, sha256}] (sha256 null if missing)
hash_files() {
  local p sum
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    sum=""; [ -f "$root/$p" ] && sum="$(vetdd_sha256 "$root/$p")"
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
  --argjson files "$files_json" '
  (.oracle
    | (if $seam_set == 1 then .seam = $seam else . end)
    | (if $version_set == 1 then .version = $version else . end)
    | .files = $files) as $oracle
  | .oracle = $oracle
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
    }]' --argjson cmd "$cmd_json" < "$meta" > "$tmp_meta" && mv "$tmp_meta" "$meta" || {
  rm -f "$tmp_meta"; die "could not update $meta"
}

if [ "$accepted" = false ]; then
  printf 'evidence.sh: %s run must end %s, got %s (exit %s); recorded as run %s with accepted=false\n' \
    "$kind" "$required" "$outcome" "$exit_code" "$seq" >&2
  exit 1
fi
printf 'evidence.sh: recorded %s run %s for %s: %s\n' "$kind" "$seq" "$slice" "$outcome" >&2
exit 0
