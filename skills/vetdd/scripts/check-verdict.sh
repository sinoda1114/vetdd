#!/usr/bin/env bash
# Check a judge verdict (modes/eval.md, step 6).
# Usage: check-verdict.sh <judge.json> [--labels c1,c2] [--rubric <rubric.md>]
#                         [--eval-id <id>] [--run-id <id>] [--rubric-version <n>]
# Checks: (schema) schemas/verdict.schema.json; labels are unique; every label has exactly one score and a non-empty
# evidence citation on every criterion, and no other label appears; "verdicts" has exactly the labels;
# "winner" is "none" for one label, else a label or "tie"; with --labels the label set matches
# exactly; with --rubric the criterion names match the rubric's "## N. name" headings in order
# (a criterion name may repeat the "N. " prefix); --eval-id, --run-id, --rubric-version must equal
# the verdict's fields.
# Recomputed from the scores (when every label has exactly one score per criterion): a label's
# verdict is "pass" iff every score is 2, "fail" iff any score is 0, else "partial"; "inconclusive"
# is accepted for any label. The winner is the label with the strictly highest total, "tie" when
# two or more labels share it; an inconclusive label is never the winner.
# Output: "OK", or one "FAIL (<reason>)" line per problem.
# Exit: number of problems (capped at 125); 126 on usage or tool errors.
set -u

die() { printf 'check-verdict.sh: %s\n' "$1" >&2; exit 126; }

here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
command -v jq >/dev/null 2>&1 || die "jq is required but not found; install it (macOS: brew install jq, Debian/Ubuntu: apt-get install jq)"
command -v node >/dev/null 2>&1 || die "node is required but not found"

file=""; labels=""; labels_set=0; rubric=""; eval_id=""; run_id=""; version=""
while [ $# -gt 0 ]; do
  case "$1" in
    --labels) [ $# -ge 2 ] || die "--labels needs a value"; labels="$2"; labels_set=1; shift 2 ;;
    --rubric) [ $# -ge 2 ] || die "--rubric needs a value"; rubric="$2"; shift 2 ;;
    --eval-id) [ $# -ge 2 ] || die "--eval-id needs a value"; eval_id="$2"; shift 2 ;;
    --run-id) [ $# -ge 2 ] || die "--run-id needs a value"; run_id="$2"; shift 2 ;;
    --rubric-version) [ $# -ge 2 ] || die "--rubric-version needs a value"; version="$2"; shift 2 ;;
    -*) die "unknown option '$1'" ;;
    *) [ -z "$file" ] || die "only one verdict file is allowed"; file="$1"; shift ;;
  esac
done
[ -n "$file" ] || die "usage: check-verdict.sh <judge.json> [--labels c1,c2] [--rubric <file>] [--eval-id <id>] [--run-id <id>] [--rubric-version <n>]"
[ -f "$file" ] || die "verdict not found: $file"
[ -z "$rubric" ] || [ -f "$rubric" ] || die "rubric not found: $rubric"
case "$version" in *[!0-9]*|0*) die "--rubric-version must be a positive integer" ;; esac

problems=0
. "$here/lib/common.sh"
fail() { printf 'FAIL (%s)\n' "$1" | vetdd_printable; problems=$((problems + 1)); }
finish() {
  [ "$problems" -gt 0 ] || echo "OK"
  [ "$problems" -le 125 ] || problems=125
  exit "$problems"
}

schema_out="$(node "$here/lib/validate-json.mjs" "$here/../schemas/verdict.schema.json" "$file" 2>&1)"
case $? in
  0) ;;
  1) while IFS= read -r line; do fail "schema: $line"; done <<< "$schema_out"; finish ;;
  *) die "schema validation could not run: $schema_out" ;;
esac

# Cross-field rules, one reason per line. The schema stays inside OpenAI's strict structured-output
# subset, so uniqueness and one-entry-per-label are checked here rather than in the schema.
RULES='
# The one score of label $l on each criterion, or null where it is missing or repeated.
def scores_of($v; $l): [$v.criteria[] | [.scores[] | select(.label == $l)] | if length == 1 then .[0].score else null end];
def said($v; $l): [$v.verdicts[] | select(.label == $l) | .verdict] | if length == 1 then .[0] else null end;
# Verdicts and winner recomputed from the scores; skipped unless every label has exactly one score
# per criterion and the winner has a valid shape (the rules below already report those problems).
def recomputed($v):
  $v.labels as $L
  | if ($L | unique | length) != ($L | length) or any($L[]; scores_of($v; .) | any(. == null)) then empty else
      ($L[] as $l | scores_of($v; $l) as $s | said($v; $l) as $said
        | (if all($s[]; . == 2) then "pass" elif any($s[]; . == 0) then "fail" else "partial" end) as $want
        | select($said != null and $said != "inconclusive" and $said != $want)
        | "verdicts: \($l) is \($said), but its scores make it \($want)"),
      (if ($L | length) < 2 or ($v.winner != "tie" and ($v.winner | IN($L[]) | not)) then empty else
         [$L[] as $l | {label: $l, total: (scores_of($v; $l) | add)}] as $t
         | ($t | map(.total) | max) as $top
         | [$t[] | select(.total == $top) | .label] as $best
         | (if ($best | length) > 1 then "tie" else $best[0] end) as $want
         | ($t | map("\(.label)=\(.total)") | join(", ")) as $totals
         | if $want != "tie" and said($v; $want) == "inconclusive" then
             "winner: \($want) has the highest total (\($totals)) but is inconclusive, so no winner can be named"
           elif $v.winner != $want then "winner: expected \($want) from the totals (\($totals)), got \($v.winner)"
           else empty end
       end)
    end;
. as $v | $v.labels as $L
| ($L | group_by(.)[] | select(length > 1) | "labels: duplicate \(.[0])"),
  ($v.criteria[] as $c | $L[] as $l
    | [$c.scores[] | select(.label == $l)] as $mine
    | (if ($mine | length) == 0 then "criterion \($c.name | tojson): no score for \($l)"
       elif ($mine | length) > 1 then "criterion \($c.name | tojson): more than one score for \($l)"
       elif ($mine[0].evidence | test("\\S") | not) then "criterion \($c.name | tojson): no evidence citation for \($l)"
       else empty end)),
  ($v.criteria[] as $c | $c.scores[].label | select(IN($L[]) | not)
    | "criterion \($c.name | tojson): unknown label \(.)"),
  ($L | unique[] as $l | [$v.verdicts[] | select(.label == $l)] | length
    | if . == 0 then "verdicts: no entry for \($l)"
      elif . > 1 then "verdicts: more than one entry for \($l)" else empty end),
  ($v.verdicts[].label | select(IN($L[]) | not) | "verdicts: unknown label \(.)"),
  (if ($L | length) == 1 then
     (if $v.winner == "none" then empty else "winner: must be none with one label, got \($v.winner)" end)
   elif $v.winner == "tie" or ($v.winner | IN($L[])) then empty
   else "winner: must be one of \($L | join(", ")) or tie, got \($v.winner)" end),
  (if $want == null or ($want | sort) == ($L | sort) then empty
   else "labels: expected \($want | sort | join(",")), verdict has \($L | sort | join(","))" end),
  (if $headings == null then empty else
     [$v.criteria[].name | sub("^[0-9]+\\.\\s*"; "")] as $names
     | range(0; [($names | length), ($headings | length)] | max) as $i
     | select($names[$i] != $headings[$i])
     | "criteria: position \($i + 1) is \($names[$i] // "missing" | tojson), rubric heading is \($headings[$i] // "none" | tojson)"
   end),
  (if $eid == null or $v.eval_id == $eid then empty else "eval_id: expected \($eid), got \($v.eval_id)" end),
  (if $rid == null or $v.run_id == $rid then empty else "run_id: expected \($rid), got \($v.run_id)" end),
  (if $rver == null or $v.rubric_version == $rver then empty
   else "rubric_version: expected \($rver), got \($v.rubric_version)" end),
  recomputed($v)'

want="null"
if [ "$labels_set" -eq 1 ]; then
  want="$(printf '%s' "$labels" | jq -Rc 'split(",") | map(select(. != ""))')"
fi
headings="null"
if [ -n "$rubric" ]; then
  headings="$(sed -n 's/^## [0-9][0-9]*\.[[:space:]]*//p' "$rubric" | sed 's/[[:space:]]*$//' | jq -Rsc 'split("\n") | map(select(. != ""))')"
fi

eid="null"; rid="null"; rver="null"
[ -z "$eval_id" ] || eid="$(jq -n --arg x "$eval_id" '$x')"
[ -z "$run_id" ] || rid="$(jq -n --arg x "$run_id" '$x')"
[ -z "$version" ] || rver="$version"
rules_out="$(jq -r --argjson want "$want" --argjson headings "$headings" --argjson eid "$eid" \
  --argjson rid "$rid" --argjson rver "$rver" "$RULES" "$file")" \
  || die "could not evaluate the verdict rules"
while IFS= read -r line; do
  [ -z "$line" ] || fail "$line"
done <<< "$rules_out"
finish
