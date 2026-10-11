# The stall shape (references/stall.md), shared by stall.sh and check-evidence.sh rule 11.
# A stall: K+1 failed attempts in a row (after runs that ended target_failure, accepted or not) whose
# failure counts (tests.failed from the runner's report, else 1 per attempt) never fall. An
# infrastructure_error never counts; a green after (or integrated) run, or an attempt on another
# oracle version, starts over; after a stall is counted the next attempts start over too, so each
# redesign gets its own K+1 attempts.

VETDD_HANDOVER_HEADINGS="## Unmet requirement
## Expected and actual
## Minimal reproduction
## Hypotheses tried
## Why it failed
## Reusable results"

# jq: stall_walk($k) over a meta.json -> {stalls, trailing: [counts since the last green or stall],
# stalled: whether the trailing attempts are a stall now}.
VETDD_STALL_JQ='
def attempt_count: (.tests.failed? | numbers) // 1;
def stall_walk($k):
  reduce ((.runs // []) | sort_by(.seq)[]) as $r ({stalls: 0, trail: [], ver: null, last_stall: false};
    if ($r.kind == "after" or $r.kind == "integrated") and $r.outcome == "pass" then
      .trail = [] | .last_stall = false
    elif $r.kind == "after" and $r.outcome == "target_failure" then
      ($r.oracle.version? // null) as $v
      | (if .ver != $v then .trail = [] else . end) | .ver = $v
      | ($r | attempt_count) as $n
      | (if (.trail | length) > 0 and $n < (.trail | last) then .trail = [$n] else .trail += [$n] end)
      | .last_stall = false
      | if (.trail | length) >= ($k + 1) then .stalls += 1 | .last_stall = true | .trail_at_stall = .trail | .trail = [] else . end
    else . end)
  | {stalls, stalled: .last_stall, trailing: (if .last_stall then .trail_at_stall else .trail end)};
'
