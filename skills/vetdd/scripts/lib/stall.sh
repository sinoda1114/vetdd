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

# jq: stall_walk($k) over a meta.json -> {stalls, stalled, trailing}. Each command (.cmd) is its own
# sequence of attempts: a pass of that command, or an attempt on another oracle version, starts it over.
# A count that cannot be read (no report, a report that is not ok, or failed 0: the runner failed
# before any test) is no progress: it repeats the last count.
VETDD_STALL_JQ='
def usable_count: if (.tests | type) == "object" and .tests.status == "ok" and ((.tests.failed // 0) > 0)
  then .tests.failed else null end;
def stall_walk($k):
  reduce ((.runs // []) | sort_by(.seq)[]) as $r ({stalls: 0, seq: {}, ver: {}, now: {}, at: {}};
    (($r.cmd // []) | tojson) as $c
    | if ($r.kind == "after" or $r.kind == "integrated") and $r.outcome == "pass" then
        .seq[$c] = [] | .now[$c] = false
      elif $r.kind == "after" and $r.outcome == "target_failure" then
        ($r.oracle.version? // null) as $v
        | (if .ver[$c] != $v then .seq[$c] = [] else . end) | .ver[$c] = $v
        | (.seq[$c] // []) as $t
        | (($r | usable_count) // ($t | last) // 1) as $n
        | .seq[$c] = (if ($t | length) > 0 and $n < ($t | last) then [$n] else $t + [$n] end)
        | .now[$c] = false
        | if (.seq[$c] | length) >= ($k + 1) then
            .stalls += 1 | .now[$c] = true | .at[$c] = .seq[$c] | .seq[$c] = []
          else . end
      else . end)
  | . as $s
  | ([$s.now | to_entries[] | select(.value) | .key]) as $stuck
  | {stalls: $s.stalls, stalled: ($stuck | length > 0),
     trailing: (if ($stuck | length) > 0 then $s.at[$stuck[0]]
                else ([$s.seq[]] | max_by(length) // []) end)};
'
