#!/usr/bin/env bash
# Check recorded evidence (plan §2.4).
# Usage: check-evidence.sh [--repo <dir>] [<slice-id>...]
# History:  (1) a red run precedes the first green run, and no red before follows the last green
#           (2) accepted before runs are target_failure
#           (3) accepted after/integrated runs are pass, and the latest after/integrated run passed
#           (4) infrastructure_error / inconclusive never count as red or green
# Final:    (5) the latest after/integrated tree_hash matches the current working tree
#           (6) oracle.files sha256 match the current files
# Output: "<slice>: OK" or one "<slice>: FAIL (<rule>: <reason>)" line per failing rule.
# Exit code: number of failing slices (capped at 125); 2 on usage errors.
set -u

die() { printf 'check-evidence.sh: %s\n' "$1" >&2; exit 2; }

. "${BASH_SOURCE[0]%/*}/lib/common.sh"
vetdd_require_jq check-evidence.sh
. "${BASH_SOURCE[0]%/*}/lib/tree-hash.sh"

repo="."
slices=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] || die "--repo needs a value"; repo="$2"; shift 2 ;;
    -*) die "unknown option '$1'" ;;
    *) slices+=("$1"); shift ;;
  esac
done

root="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || die "not a git repository: $repo"
root="$(cd "$root" && pwd -P)"
evidence_dir="$root/.vetdd/evidence"

if [ ${#slices[@]} -eq 0 ]; then
  if [ -d "$evidence_dir" ]; then
    for d in "$evidence_dir"/*/; do
      [ -d "$d" ] || continue
      d="${d%/}"; slices+=("${d##*/}")
    done
  fi
  if [ ${#slices[@]} -eq 0 ]; then
    echo "check-evidence.sh: no evidence found under $evidence_dir"
    exit 0
  fi
fi

# Rules 1-4 and the rule-5 precondition, as "<rule>: <reason>" lines.
HISTORY_RULES='
def green: .kind == "after" or .kind == "integrated";
def red: (.kind == "before" or .kind == "calibration") and .outcome == "target_failure";
def neither: .outcome == "infrastructure_error" or .outcome == "inconclusive";
.runs as $all
| [$all[] | select(.accepted != false)] as $acc
| ([$acc[] | select(green)] | first) as $first_green
| ([$all[] | select(green)] | last) as $last_green
| (
    (if $first_green != null and ([$acc[] | select(red and .seq < $first_green.seq)] | length) == 0
     then "1: no red run (before or calibration ending target_failure) precedes \($first_green.kind) run \($first_green.seq)"
     else empty end),
    ($acc[] | select(.kind == "before" and .outcome == "target_failure" and $last_green != null and .seq > $last_green.seq)
     | "1: before run \(.seq) has no later after or integrated run"),
    ($acc[] | select(.kind == "before" and .outcome == "pass")
     | "2: before run \(.seq) is accepted but ended pass"),
    ($acc[] | select(green and .outcome == "target_failure")
     | "3: \(.kind) run \(.seq) is accepted but ended target_failure"),
    (if $last_green != null and ($last_green.accepted == false or $last_green.outcome != "pass")
     then "3: latest \($last_green.kind) run \($last_green.seq) ended \($last_green.outcome)"
     else empty end),
    ($acc[] | select(.kind != "calibration" and neither)
     | "4: \(.kind) run \(.seq) is accepted but ended \(.outcome), which is neither red nor green"),
    (if $last_green == null then "5: no after or integrated run" else empty end)
  )'

current_tree="$(vetdd_tree_hash "$root")" || current_tree=""

check_slice() {
  local slice="$1" meta="$evidence_dir/$1/meta.json" final_tree path want have
  vetdd_is_slice_id "$slice" || { echo "schema: invalid slice id"; return; }
  if [ ! -f "$meta" ]; then echo "schema: no meta.json for this slice"; return; fi
  if ! jq -e --arg s "$slice" \
      '(.slice_id == $s) and (.runs | type == "array") and (.oracle.files | type == "array")' \
      "$meta" >/dev/null 2>&1; then
    echo "schema: meta.json is not valid evidence for slice '$slice'"
    return
  fi
  jq -r "$HISTORY_RULES" "$meta"

  final_tree="$(jq -r '[.runs[] | select(.kind == "after" or .kind == "integrated")] | last | .tree.tree_hash // empty' "$meta")"
  if [ -n "$final_tree" ]; then
    if [ -z "$current_tree" ]; then echo "5: could not hash the working tree"
    elif [ "$final_tree" != "$current_tree" ]; then
      echo "5: working tree $current_tree differs from the tree of the latest green run ($final_tree)"
    fi
  fi

  if [ "$(jq '.oracle.files | length' "$meta")" -eq 0 ]; then
    echo "6: oracle.files is empty; nothing binds the evidence to an oracle"
  fi
  jq -r '.oracle.files[] | "\(.path)\t\(.sha256 // "")"' "$meta" |
    while IFS="$(printf '\t')" read -r path want; do
      if [ ! -f "$root/$path" ]; then echo "6: oracle file $path is missing"; continue; fi
      have="$(vetdd_sha256 "$root/$path")"
      [ "$have" = "$want" ] || echo "6: oracle file $path changed since it was recorded"
    done
}

failed=0
for slice in "${slices[@]}"; do
  problems="$(check_slice "$slice")"
  if [ -z "$problems" ]; then
    echo "$slice: OK"
  else
    failed=$((failed + 1))
    printf '%s\n' "$problems" | while IFS= read -r line; do echo "$slice: FAIL ($line)"; done
  fi
done
[ "$failed" -le 125 ] || failed=125
exit "$failed"
