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
# sequence of attempts, and a pass of that command starts it over. A counted stall is the redesign
# boundary: every sequence starts over, and so does a new oracle version. "stalled" holds only while
# the attempt that completed a stall is the latest one. A count that cannot be read (no usable report,
# a count that is not a number, failed 0: the runner failed before any test) repeats the last one.
VETDD_STALL_JQ='
def usable_count: if (.tests | type) == "object" and .tests.status == "ok"
    and (.tests.failed | type) == "number" and .tests.failed > 0 then .tests.failed else null end;
def stall_walk($k):
  reduce ((.runs // []) | sort_by(.seq)[]) as $r ({stalls: 0, seq: {}, ver: null, stalled: false, at: [], last: null};
    (($r.cmd // []) | tojson) as $c
    | if ($r.kind == "after" or $r.kind == "integrated") and $r.outcome == "pass" then
        .seq[$c] = [] | .stalled = false | .last = $c
      elif $r.kind == "after" and $r.outcome == "target_failure" then
        ($r.oracle.version? // null) as $v
        | (if .ver != $v then .seq = {} else . end) | .ver = $v
        | (.seq[$c] // []) as $t
        | (($r | usable_count) // ($t | last) // 1) as $n
        | .seq[$c] = (if ($t | length) > 0 and $n < ($t | last) then [$n] else $t + [$n] end)
        | .stalled = false | .last = $c
        | if (.seq[$c] | length) >= ($k + 1) then
            .stalls += 1 | .stalled = true | .at = .seq[$c] | .seq = {}
          else . end
      else . end)
  | {stalls, stalled,
     trailing: (if .stalled then .at elif .last == null then [] else (.seq[.last] // []) end)};
'
