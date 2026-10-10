#!/usr/bin/env bash
# Check recorded evidence (plan §2.4).
# Usage: check-evidence.sh [--repo <dir>] [<slice-id>...]
# History:  (1) a red run precedes the first green run, and no red before follows the last green
#           (2) accepted before runs are target_failure
#           (3) accepted after/integrated runs are pass, and the latest after/integrated run passed
#           (4) infrastructure_error / inconclusive never count as red or green
# Final:    (5) the latest after/integrated tree_hash matches the current working tree
#           (6) oracle.files sha256 match the current files
# Focus:    (9a) no focused test (.only, fdescribe) in a JS or TS oracle file: it would run only that
#               test and skip the rest. The file is read as code (comments, strings, templates, and
#               regular-expression literals blanked, across lines). A tripwire for an accident, not a
#               boundary: fit(, a renamed or wrapped focus, a helper, a file not named with
#               --oracle-file, or another language passes it.
# Oracle:   (8) the version chain of accepted runs: an oracle is its version plus the sha256 of its
#               files. Within the final green's version the files do not change from its first red
#               on, nor after any green of that version (edits before the first red are the test
#               being written); the final green has a red with the same oracle before it (a red the
#               command produced, not one forced with --outcome on exit 0, 126, or 127); the final version is
#               not a replaced one come back; and nothing after the final green uses another oracle. A version left behind is
#               history: bumping it and recording its red clears an earlier slip. This catches an
#               oracle file edited after its green, and a weakening that stops the recorded command
#               going red. It is a tripwire, not a boundary: a weakening that still goes red, a red
#               from another command, and helpers or fixtures not named with --oracle-file pass it.
#           (8d) the version log (oracle-version.sh), asked for only once meta.json has an
#               oracle_versions key (older evidence has none), and only of the version the final
#               green rests on when it is not the first version of the chain (a version left behind is
#               history; a bump recovers a slip): it has an entry with a reason, a change in meaning
#               has its re-agreement, and the version's first red comes after the entry (agree first,
#               then recalibrate). Also a tripwire: it checks that the record exists and is in order,
#               not that it is true.
# Tests:    (9b) a test that ran (passed or failed) in an earlier accepted run and is skipped or todo in the
#               latest accepted run of the same command and oracle version, for the version the final
#               green rests on (an older version left behind is history; bumping --oracle-version, with
#               its entry in the version log, is the way out of a skip that is meant). Cmd is compared as
#               JSON. The report is the normalized copy that evidence.sh --test-report saves
#               (runs/<seq>-<kind>.tests.json, opened by a name made from seq and kind, only through a
#               safe path, and only if its sha256 matches the record). A command whose latest run has no
#               usable report (absent, missing, invalid) is not compared (9c warns); a copy that cannot be
#               read for a run recorded ok fails. This is IDS's count of unfinished tests (the Admitted
#               holes), taken from the runner's report. A tripwire, not a boundary: a test that
#               disappears altogether, a changed command (a name filter), a renamed test, tests sharing a
#               file and a name (read as one), a skip written into an oracle file itself (its hash change
#               needs a version bump, so it starts a new comparison), a slice that never asks for a report,
#               and a copy and its sha256 both rewritten by hand all pass it.
#           (9c) a warning, never a failure, per command that asked for a report at some point (among the
#               runs of the final version): its own latest green run has skipped or todo tests (counts
#               shown), or has no usable report. A command that never asked for one (a type check) and a
#               slice whose runs never record a report (old evidence) are not warned: a blind spot.
# Audit:    (10a) a calibration run marked audit undefined-imports (calibrate.sh stub: every product file the
#               oracle imports replaced by a stub with undefined exports) that is accepted and ended pass,
#               with the oracle of the final green (an audit of a version left behind is history): the
#               test observes nothing.
#           (10b) the oracle of the final green run has an accepted audit run, recorded after a green run
#               of that oracle, that ended target_failure (not forced with --outcome; the command is
#               not compared with the green's, a blind spot), or an audits[] entry not_applicable with a reason
#               (audit-note.sh) recorded after the final oracle first ran, so a note written for an older
#               version stops counting once a new one has run. Asked only of a slice that opted in: a run with an audit mark other
#               than mutation, or an audits key that is empty or holds an entry other than a mutation
#               note (an unknown kind opts in; evidence from before the audit, and a slice that never opts in, are not
#               asked: a blind spot, since a slice that never runs `calibrate.sh stub` is never told to).
#               An audit run is never a red for rules 1 and 8 (the product was stubbed, not defective)
#               and never the latest run of a command for rule 9b. A tripwire, not a boundary: it sees
#               only the files named with --file (one left out is not stubbed), a runner that fails
#               on the stub at import time is red for the wrong reason (the log must show the test's
#               own failure), and a not_applicable note is a claim, not a proof.
#           (10c) the latest accepted mutation run (evidence.sh --audit mutation) recorded after the final
#               green run has a usable report (status ok, its copy present with the
#               recorded sha256), mutated and tested something, let no mutant survive or go uncovered,
#               and its mutated files still hold the source it mutated; with no such run, a mutation
#               note written after the final oracle first ran. Ignored mutants are a WARN (10c). Asked
#               of a slice whose final oracle has a JS or TS file (.js .jsx .mjs .cjs .ts .tsx .mts
#               .cts), and of any other slice with a mutation run or note. A tripwire, not a boundary: it trusts the
#               report (what Stryker mutated and how it ran), and the ranges are the judge's to check.
# Output: "<slice>: OK" or one "<slice>: FAIL (<rule>: <reason>)" line per failing rule, then one
#         "<slice>: WARN (9c|10c: <reason>)" line per warning (advice for the reply's Attention section;
#         it holds no recorded text).
# Exit code: number of failing slices (capped at 125; a WARN line never counts); 2 on usage errors.
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
def red: (.kind == "before" or .kind == "calibration") and .outcome == "target_failure" and .audit == null;
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
    ($acc[] | select(green and .outcome == "pass" and (.exit_code // 0) != 0)
     | "3: \(.kind) run \(.seq) ended pass only because --outcome forced it (the command exited \(.exit_code)); the evidence cannot be edited back, so fix the cause and record the slice again under a new slice id"),
    (if $last_green != null and ($last_green.accepted == false or $last_green.outcome != "pass")
     then "3: latest \($last_green.kind) run \($last_green.seq) ended \($last_green.outcome)"
     else empty end),
    ($acc[] | select(.kind != "calibration" and neither)
     | "4: \(.kind) run \(.seq) is accepted but ended \(.outcome), which is neither red nor green"),
    (if $last_green == null then "5: no after or integrated run" else empty end)
  )'

# Rule 8, over accepted runs in seq order, each with the oracle it was measured with.
ORACLE_RULES='
def green: .kind == "after" or .kind == "integrated";
# A red the command itself produced: an outcome forced with --outcome on an exit 0, or on a
# command that could not run (126, 127), is not one.
def red: (.kind == "before" or .kind == "calibration") and .outcome == "target_failure"
         and .audit == null and .exit_code != 0 and .exit_code != 126 and .exit_code != 127;
def oid: {v: (.oracle.version // null), f: ((.oracle.files // []) | map({path, sha256}) | sort_by(.path))};
def vname: if . == null then "unset" else tostring end;
def recorded: (.oracle | type) == "object" and (.oracle.files | type) == "array";
def usable: recorded and (.exit_code | type) == "number";
. as $meta
| [.runs[] | select(.accepted != false)] as $accepted
| [$accepted[] | select(usable)] | sort_by(.seq) as $acc
| ([$acc[] | select(green and .outcome == "pass")] | last) as $g
| (
    ($accepted[] | select(recorded | not) | "8: run \(.seq) has no oracle record, so the oracle chain cannot be checked"),
    ($accepted[] | select(recorded and (usable | not)) | "8: run \(.seq) has no numeric exit_code, so it cannot count as a red or a green"),
    (($g // ($acc | last)) as $ref
     | select($ref != null)
     # Edits before the oracle'"'"'s first red with this identity are the test being written, not a change.
     | ([$acc[] | select(red and oid == ($ref | oid))] | first | .seq // 0) as $from
     # A version that already went green is finished: editing it later needs a new version too.
     | [$acc[] | select(oid.v == ($ref | oid).v and oid.f != ($ref | oid).f
                       and (.seq >= $from or (green and .outcome == "pass")))] | first
     | select(. != null)
     | "8: the oracle files changed while the version stayed \(oid.v | vname) (run \(.seq) differs from run \($ref.seq)); bump --oracle-version, record a red for the new version (calibrate.sh unfix for a defect or a new behavior, plant and planted for a behavior-preserving slice), then the green. If another slice added its test to the same file, give each slice its own test file, or write every test before any before run (modes/test.md)"),
    (if $g != null and ([$acc[] | select(red and .seq < $g.seq and oid == ($g | oid))] | length) == 0
     then (if ([$acc[] | select((.kind == "before" or .kind == "calibration") and .outcome == "target_failure" and .audit == null
                                and .seq < $g.seq and oid == ($g | oid))] | length) > 0
           then "8: the only red runs with the oracle of the final green run \($g.seq) (version \(($g | oid).v | vname)) were forced with --outcome on a command that exited 0 or could not run (126, 127); make the oracle run and report failure through its exit code (references/feedback-loop-ladder.md)"
           else "8: no red run with the oracle of the final green run \($g.seq) (version \(($g | oid).v | vname)) precedes it; a new or edited oracle needs its own red before its green" end)
     else empty end),
    # Only the version that is final counts: a version left behind is history.
    ((($g // ($acc | last)) | if . == null then null else oid.v end) as $final_v
     | $acc | reduce .[] as $r ({prev: null, started: false, left: [], out: []};
        ($r | oid).v as $v
        | if .started and $v != .prev
          then (if $v == $final_v and any(.left[]; . == $v)
                then .out += ["8: version \($v | vname) is used again at run \($r.seq) after it was replaced; a changed oracle takes a new version"]
                else . end)
               | .left += [.prev] | .prev = $v
          else .prev = $v | .started = true end)
     | .out[]),
    ([$acc[] | select($g != null and .seq > $g.seq and oid != ($g | oid))] | first
     | select(. != null)
     | "8: run \(.seq) uses oracle version \((oid).v | vname) after the final green run \($g.seq); record the green again with it"),
    # Rule 8d, on the version the final green rests on (an older version left behind is history, as in
    # rule 8, and a bump recovers an earlier slip). A slice with no oracle_versions key is older than the
    # log: nothing is asked of it. The first version of the chain is the initial agreement.
    (if ($meta | has("oracle_versions")) | not then empty
     elif ($meta.oracle_versions | type) != "array" then "8: oracle_versions is not an array, so the version log cannot be checked"
     else
       ($meta.oracle_versions | map(select(type == "object"))) as $log
       | ($acc | map(oid.v) | map(select(. != null)) | reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end)) as $chain
       | ((($g // ($acc | last)) | if . == null then null else oid.v end)) as $v
       # The initial agreement is the version the log marks initial; without such an entry, the first
       # version with a name in the chain.
       | (($log | map(select(.change == "initial")) | first | .version) // $chain[0]) as $init
       | select($v != null and ($chain | length) > 0 and $v != $init)
       # The version comes from meta.json and goes into the suggested command: only a plain name.
       | if (($v | type) != "string") or ($v | test("^[A-Za-z0-9][A-Za-z0-9._-]*$") | not)
         then "8: the final oracle version is not a plain name (letters, digits, . _ -), so the version log cannot be checked"
         else
       ($log | map(select(.version == $v)) | first) as $e
       | ($acc | map(select(red and oid.v == $v)) | first) as $r
       | (if $e == null or ($e.reason | type) != "string" or ($e.reason | length) == 0
          then (if $r == null
                then "8: oracle version \($v | vname) has no recorded reason; record it with oracle-version.sh \($slice) --version \($v | vname) --change implementation --reason-file <path> (--change meaning plus --agreement-via, --question-file, --answer-file when the agreed behavior changed) before its red"
                else "8: oracle version \($v | vname) has no recorded reason and its red is already recorded, so an entry now would come after it; bump --oracle-version, record the new version with oracle-version.sh first (--change implementation --reason-file <path>, or --change meaning with --agreement-via, --question-file, --answer-file when the agreed behavior changed), then its red and green" end)
          else empty end),
         (if $e == null then empty
          elif ($e.change != "implementation" and $e.change != "meaning")
          then "8: oracle version \($v | vname) is recorded with a change that is not implementation or meaning, as a version after the first needs; bump --oracle-version, record the new version with oracle-version.sh first (--change implementation or meaning), then its red and green"
          elif $e.change == "meaning"
               and ($e.agreement | if type != "object" then true
                    else ($e.agreement.via != "AskUserQuestion" and $e.agreement.via != "chat")
                         or (($e.agreement.question | type) != "string" or ($e.agreement.question | length) == 0)
                         or (($e.agreement.answer | type) != "string" or ($e.agreement.answer | length) == 0) end)
          then "8: oracle version \($v | vname) is recorded as a change in meaning without its re-agreement (via, question, answer), and the entry cannot be completed; return to the agreement (principle 1a), bump --oracle-version, record the new version with oracle-version.sh \($slice) --version <new> --change meaning --agreement-via ... --question-file ... --answer-file ... first, then its red and green"
          else empty end),
         (if $e == null or $r == null then empty
          elif ($e.after_seq | type) != "number"
          then "8: the entry for oracle version \($v | vname) has no numeric after_seq, so the order of agreement and red cannot be checked"
          elif $r.seq <= $e.after_seq
          then "8: the first red run (\($r.seq)) of oracle version \($v | vname) is not after its log entry (after_seq \($e.after_seq)); bump --oracle-version, record the entry with oracle-version.sh first, then the red and green for the new version"
          else empty end)
         end
     end)
  )'

# Rule 10, over the accepted runs and the audits log. The final oracle is the one of the final green run
# (as in rule 8): its version and the sha256 of its files. Recorded text is never printed (run numbers
# only); a value of the wrong type is an error, which the caller turns into a failure.
AUDIT_RULES='
# A not_applicable note counts for the final oracle when it was written after that oracle first ran:
# by after_seq (the last run number then) when it has one, else by its time (a note written before
# after_seq existed). With nothing to compare, it counts for nothing.
def counts_for($first; $first_seq):
  if (.after_seq | type) == "number" then $first_seq != null and $first_seq <= .after_seq
  else $first != null and (.recorded_at | type) == "string" and .recorded_at >= $first end;
def green: .kind == "after" or .kind == "integrated";
def oid: {v: (.oracle.version // null), f: ((.oracle.files // []) | map({path, sha256}) | sort_by(.path))};
def usable: (.oracle | type) == "object" and (.oracle.files | type) == "array" and (.exit_code | type) == "number";
def num: if type == "number" then floor | tostring else error("not a number") end;
def audited: .audit.kind == "undefined-imports";
. as $meta
| [.runs[] | select(.accepted != false)] as $accepted
| [$accepted[] | select(usable)] as $acc
| ([$acc[] | select(green and .outcome == "pass")] | sort_by(.seq) | last) as $g
| [$accepted[] | select(.kind == "calibration" and audited)] as $audits
# Opted in to the undefined-imports audit: a run with its mark, or an audits key that is empty, not an
# array, or holds any entry but a mutation note; a run with any audit mark but mutation (an unknown kind
# fails closed, in both places). A mutation run or note alone opts in to nothing here.
| (($meta | has("audits")) and (($meta.audits | type) != "array" or ($meta.audits | length) == 0
     or any($meta.audits[]; type != "object" or .kind != "mutation"))) as $noted_key
| ($noted_key or ([$meta.runs[] | .audit as $a | $a != null and (($a | type) != "object" or $a.kind != "mutation")] | any)) as $opted
| (
    ($audits[] | select(.outcome == "pass") | select($g == null or oid == ($g | oid))
     | "10a: the audit run \(.seq | num) (every import stubbed with undefined) still passed, so the test observes nothing; make the test call or check the product code"),
    (if ($meta | has("audits")) and ($meta.audits | type) != "array"
     then "10: audits is not an array, so the audit notes cannot be checked"
     elif $opted and $g != null then
       ($g | oid) as $fo
       | [$acc[] | select(green and .outcome == "pass" and oid == $fo)] as $greens
       # A caught audit comes after a green run of the same oracle: before that, the red is the unfixed product.
       | ([$acc[] | select(.kind == "calibration" and audited and .outcome == "target_failure"
                           and .exit_code != 0 and .exit_code != 126 and .exit_code != 127 and oid == $fo)
                  | . as $a | select(any($greens[]; .seq < $a.seq))] | length) as $caught
       # A note counts for the final oracle when it was recorded after that oracle first ran (the entry
       # has no version of its own); with no start time to compare, it counts for nothing.
       | ([$acc[] | select(oid == $fo) | .started_at | select(type == "string")] | min) as $first
       | ([$acc[] | select(oid == $fo) | .seq | numbers] | min) as $first_seq
       | ((($meta.audits // []) | map(select(type == "object" and .kind == "undefined-imports" and .status == "not_applicable"
                                              and (.reason | type) == "string" and (.reason | length) > 0
                                              and counts_for($first; $first_seq))) | length)) as $noted
       | if $caught + $noted == 0
         then "10b: no undefined-imports audit for the final oracle after a green run of it; run calibrate.sh stub \($slice) --file <product files> --oracle-file <test files> -- <command> (it must end target_failure), or record why it does not apply with audit-note.sh \($slice) --kind undefined-imports --not-applicable --reason-file <path>"
         else empty end
     else empty end)
  )'

# Rule 10c, over the accepted runs and the audits log: the mutation audit of the final oracle. One JSON
# object: problems and warnings (rule text with run numbers only), and the files of the judged run for
# the shell to hash. Asked of a slice whose final oracle has a JS or TS file, and of any other slice with
# a mutation run or a mutation note.
MUTATION_RULES='
# A not_applicable note counts for the final oracle when it was written after that oracle first ran:
# by after_seq (the last run number then) when it has one, else by its time (a note written before
# after_seq existed). With nothing to compare, it counts for nothing.
def counts_for($first; $first_seq):
  if (.after_seq | type) == "number" then $first_seq != null and $first_seq <= .after_seq
  else $first != null and (.recorded_at | type) == "string" and .recorded_at >= $first end;
def green: .kind == "after" or .kind == "integrated";
def oid: {v: (.oracle.version // null), f: ((.oracle.files // []) | map({path, sha256}) | sort_by(.path))};
def usable: (.oracle | type) == "object" and (.oracle.files | type) == "array";
def num: if type == "number" then floor | tostring else error("not a number") end;
def nn: if type == "number" and . >= 0 then . else error("not a count") end;
def mut: (.audit | type) == "object" and .audit.kind == "mutation";
. as $meta
| [.runs[] | select(.accepted != false and usable)] as $acc
| ($acc | map(select(green and .outcome == "pass")) | sort_by(.seq) | last) as $g
# A final oracle with a JS or TS file is always asked (#25: Stryker covers those languages); any other
# slice only once it has a mutation run or note.
| (([$meta.runs[] | mut] | any) or ([($meta.audits // [])[] | select(type == "object" and .kind == "mutation")] | length > 0)
   or ($g != null and ([$g.oracle.files[]? | .path? | strings | select(test("\\.([cm]?[jt]s|[jt]sx)$"))] | length > 0))) as $opted
| if ($opted | not) or $g == null then {problems: [], warns: [], files: [], copy: null}
  else
    ($g | oid) as $fo
    # Only an audit after the final green counts: a later change outside the mutated files (runner
    # settings, dependencies, a helper) is not covered by their hashes.
    | ([$acc[] | select(.kind == "calibration" and mut and oid == $fo and .seq > $g.seq)]
       | sort_by(.seq) | last) as $m
    | ([$acc[] | select(oid == $fo) | .started_at | select(type == "string")] | min) as $first
    | ([$acc[] | select(oid == $fo) | .seq | numbers] | min) as $first_seq
    | ([($meta.audits // [])[] | select(type == "object" and .kind == "mutation" and .status == "not_applicable"
          and (.reason | type) == "string" and (.reason | length) > 0 and counts_for($first; $first_seq))] | length) as $noted
    | if $m == null then
        {copy: null, problems: (if $noted > 0 then [] else ["10c: no mutation audit for the final oracle after its last green run; run VETDD_MUTATION_TESTS=<the slice'"'"'s test files, one per line> evidence.sh \($slice) calibration --audit mutation --mutation-report stryker-json:<the jsonReporter.fileName of the Stryker config> -- npx --no-install stryker run --mutate <file>:<first>-<last>,... on the lines the slice changed, or record why it does not apply with audit-note.sh \($slice) --kind mutation --not-applicable --reason-file <path>"] end),
         warns: [], files: []}
      else
        ($m.seq | num) as $s | $m.audit.report as $rep
        | if ($rep | type) != "object" then error("no report")
          elif $rep.status != "ok" then
            {copy: null, problems: [if $rep.status == "empty"
                then "10c: mutation run \($s) mutated nothing: the --mutate ranges held no mutant; widen them to the function'"'"'s closing brace"
                else "10c: the report of mutation run \($s) is \(if $rep.status == "missing" then "missing" else "invalid" end); run the mutation audit again" end], warns: [], files: []}
          else
            ($rep.counts) as $c
            | ($c.survived | nn) as $sv | ($c.no_coverage | nn) as $nc | ($c.total | nn) as $t | ($c.ignored | nn) as $ig
            | ($c.killed | nn) as $k | ($c.timeout | nn) as $to | ($c.compile_error | nn) as $ce | ($c.runtime_error | nn) as $re
            | ($rep.sha256 | if type == "string" then . else error("sha256") end) as $csum
            | ($rep.files | if type == "array" and length > 0 and all(.[]; type == "object" and (.path | type) == "string" and (.sha256 | type) == "string")
                            then . else error("files") end) as $files
            | {problems: (
                 (if $t == 0 then ["10c: mutation run \($s) mutated nothing (0 mutants); --mutate must cover the lines the slice changed"]
                  elif $k + $to + $sv + $nc == 0 then ["10c: mutation run \($s) tested no mutant (\($ce) compile errors, \($re) runtime errors, and \($ig) ignored of \($t)); fix the setup (a type checker or a broken build rejects every mutant) and run the audit again"]
                  else [] end)
                 + (if $sv + $nc > 0 then ["10c: mutation run \($s): \($sv) survived and \($nc) without coverage of \($t) mutants; strengthen the test until each is killed, or, for a mutant that cannot change behavior, disable it in the product code with // Stryker disable next-line <mutator>: <reason> and run the audit again"] else [] end)),
               warns: (if $ig > 0 then ["10c: \($ig) of the \($t) mutants of mutation run \($s) are ignored (Stryker disable comments); each one and its reason goes in the reply'"'"'s Attention"] else [] end),
               files: [$files[] | {path, sha256, seq: $s}], copy: {seq: $s, sha256: $csum}}
          end
      end
  end'

# Warnings (rule 9c) travel in a file, apart from the problems that decide pass or fail.
warn_file="$(mktemp "${TMPDIR:-/tmp}/check-evidence.XXXXXX")" || die "cannot create a temporary file"
trap 'rm -f "$warn_file"' EXIT

current_tree="$(vetdd_tree_hash "$root")" || current_tree=""

# Rule 9b, step 1: the accepted runs that recorded a usable report, one line each: seq, kind, sha256 of
# the copy ("-" when the record has none), and the command as one line of JSON. A run whose seq or kind
# is not what evidence.sh writes prints "?": the copy's name is made from them, so nothing else is opened.
REPORT_RUNS='
  .runs[] | select(.accepted != false and .audit == null and (.tests | type) == "object" and .tests.status == "ok")
  | if (.seq | type) == "number" and .seq >= 1 and .seq < 1000000 and .seq == (.seq | floor)
       and (.kind == "before" or .kind == "calibration" or .kind == "after" or .kind == "integrated")
    then "\(.seq | floor | tostring)\t\(.kind)\t\(.tests.sha256 | if type == "string" and length == 64 and test("^[0-9a-f]{64}$") then . else "-" end)\t\(.cmd | tojson)\t\(.oracle.version | tojson)"
    else "?" end'

# Rule 9b, step 2, over the readable copies ({seq, cmd, tests} each): per command, a test (file and name)
# that has a passed or failed result in an earlier run and only skipped or todo results in the latest run.
# Recorded text is shown without control characters (so a name cannot start a line) and cut to 100
# characters; pass or fail does not depend on what is shown. At most $max tests are listed.
TEST_DROP_RULES='
def ran: .status == "passed" or .status == "failed";
def idle: .status == "skipped" or .status == "pending" or .status == "disabled" or .status == "todo";
# Shown without control characters, bidirectional controls, or line separators, cut to 100 characters.
def show: tostring | explode | map(select(. > 31 and (. < 127 or . > 159) and . != 8232 and . != 8233
    and (. < 8234 or . > 8238) and (. < 8294 or . > 8297)
    and (. < 8203 or . > 8207) and . != 1564 and . != 65279 and . != 8288)) as $c
  | if ($c | length) > 100 then ($c[0:100] | implode) + "..." else ($c | implode) end;
# The input holds the readable copies ({seq, cmd, ov, tests}) and one marker ({m: true, seq, cmd, ov}) for
# every accepted run, whether or not it has a report. Only the version the final green rests on is
# compared (an older version left behind is history), and only a command whose latest run has a copy.
(. | map(select(.m != true))) as $copies
| (. | map(select(.m == true))) as $marks
| [ ($copies | group_by([.cmd, .ov] | tojson)[]) | sort_by(.seq) | . as $g | ($g | last) as $l | $g[:-1] as $earlier
  | select($l.ov == $fv)
  | select(([$marks[] | select(.cmd == $l.cmd and .ov == $l.ov) | .seq] | max) == $l.seq)
  | select(($earlier | length) > 0)
  # One index of what ran before: per test (file and name), the latest earlier run in which it ran and
  # whether it failed there. Built once, so a large suite is not searched test by test.
  | (reduce ($earlier[] | .seq as $s | .tests[] | select(ran) | {k: ([.file, .name] | tojson), s: $s, st: .status}) as $t ({};
       .[$t.k] = (if (.[$t.k].e // -1) == $t.s
                  then {e: $t.s, failed: (.[$t.k].failed or $t.st == "failed")}
                  else {e: $t.s, failed: ($t.st == "failed")} end))) as $idx
  | ($l.tests | group_by([.file, .name])[] | select(all(.[]; idle))
     | {file: .[0].file, name: .[0].name, status: (if all(.[]; .status == "todo") then "todo" else "skipped" end)}) as $d
  | ($idx[[$d.file, $d.name] | tojson]) as $x
  | select($x != null)
  | {l: $l.seq, e: $x.e, d: $d, was: (if $x.failed then "failed" else "passed" end)}
] as $f
| ($f[:$max][] | "9b: test \"\(.d.name | show)\" in \(.d.file | show) ran (\(.was)) in run \(.e) but is \(.d.status) in run \(.l), the latest run of the same command and oracle version; a test that stops running makes the green mean less than it says. Run it again; if it is meant to be \(.d.status), bump --oracle-version, record why with oracle-version.sh, and record the slice again"),
  (if ($f | length) > $max then "9b: and \($f | length - $max) more tests ran in an earlier run and are skipped or todo in the latest run of their command" else empty end)'

# Rule 9c: warnings only (no recorded text in them: counts, a run number, and fixed words). A count that
# is not a number is an error: nothing prints, and the caller fails the slice.
TEST_WARN_RULES='
def num: if type == "number" then . else error("not a number") end;
# Per command, among the runs of the version the final green rests on: the commands that asked for a
# report at some point, each with its own latest green (after or integrated). A command that never
# asked for one (a type check) is not asked about.
[.runs[] | select(.accepted != false and .oracle.version == $fv and .audit == null)] as $acc
| ($acc | group_by(.cmd | tojson)[])
| select(any(.[]; (.tests | type) == "object"))
| ([.[] | select(.kind == "after" or .kind == "integrated")] | max_by(.seq)) as $l
| select($l != null)
| ($l.seq | num | floor | tostring) as $s
| if ($l.tests | type) == "object" and $l.tests.status == "ok" then
    (($l.tests.skipped | num) as $sk | ($l.tests.todo | num) as $td
     | select($sk + $td > 0)
     | "9c: \($sk) skipped and \($td) todo tests in the latest \($l.kind) run \($s), counted from the runner'"'"'s report (tests left out by a name filter count as skipped); they did not run, so the green says nothing about them. Put them in the reply'"'"'s Attention")
  elif ($l.tests | type) == "object" then
    "9c: the latest \($l.kind) run \($s) asked for a test report but it is \(if $l.tests.status == "missing" then "missing" elif $l.tests.status == "invalid" then "invalid" else "unusable" end); skipped and todo tests cannot be counted. Put this in the reply'"'"'s Attention"
  else
    "9c: no test report was recorded for the latest \($l.kind) run \($s), though another run of the same command asked for one; skipped and todo tests cannot be counted. Record the run with --test-report and put this in the reply'"'"'s Attention"
  end'

# Lines of a JS or TS oracle file that hold a focused test, one per output line: the line number,
# "!<line>" for a line too long to scan, or "?" when a comment or template literal is still open at
# the end of the file (the scan cannot be trusted). The file is read as code: comments (// and /* */)
# and the contents of strings, template literals, and regular-expression literals are blanked first,
# across lines (a string continued with a backslash included), then the code is searched for
# <it|test|describe|suite|context|specify>[.name]*.only[.name]*( or `, spacing, comments, and a line
# break allowed between the tokens, or fdescribe(. The root name must stand alone (not myit.only, not
# this.it.only, however spaced). Not covered, so a tripwire and not a boundary: fit( (a common name
# for other functions), code inside ${...} in a template, a regular-expression literal after a keyword
# such as return (it reads as division), a division written right after a > (it reads as a regular
# expression), JSX text (read as code: an it.only( written there is
# reported, and a bare backtick or quote there can hide what follows), and a focus API renamed or
# wrapped.
focused_lines() {
  LC_ALL=C awk -v sq="'" '
    function blanks(k,   b) { b = ""; while (k-- > 0) b = b " "; return b }
    # Does s hold a match of regular expression r that ends after position off and is not a property
    # access (a "." before the root name, however spaced)?
    function hit(s, r, off,   pos, rest, st, rp, pre, e) {
      pos = 0; rest = s
      while (match(rest, r)) {
        st = pos + RSTART; e = st + RLENGTH - 1
        rp = (substr(rest, RSTART, 1) ~ /[A-Za-z]/) ? st : st + 1
        pre = substr(s, 1, rp - 1); sub(/[ \t]+$/, "", pre)
        if (e > off && substr(pre, length(pre), 1) != ".") return 1
        pos = st; rest = substr(s, pos + 1)
      }
      return 0
    }
    BEGIN {
      block = 0; tpl = 0; carry = ""; tail = ""; prev = ""
      re = "(^|[^A-Za-z0-9_$.])(it|test|describe|suite|context|specify)([ \t]*\\.[ \t]*[A-Za-z_$]+)*[ \t]*\\.[ \t]*only([ \t]*\\.[ \t]*[A-Za-z_$]+)*[ \t]*(<[^()]*>)?[ \t]*[(`]"
      fre = "(^|[^A-Za-z0-9_$.])fdescribe[ \t]*\\("
    }
    {
      line = $0; sub(/\r$/, "", line); n = length(line)
      if (n > 20000) { print "!" NR; next }
      out = ""; i = 1; str = carry; carry = ""
      if (tpl) str = "`"
      while (i <= n) {
        c = substr(line, i, 1); d = substr(line, i + 1, 1)
        if (block) {
          if (c == "*" && d == "/") { block = 0; out = out "  "; i += 2 } else { out = out " "; i++ }
          continue
        }
        if (str != "") {
          if (c == "\\") {
            if (i == n && str != "`") carry = str
            out = out "  "; i += 2; continue
          }
          if (c == str) { out = out c; if (c == "`") tpl = 0; str = ""; prev = "x"; i++; continue }
          out = out " "; i++; continue
        }
        if (c == "/" && d == "/") break
        if (c == "/" && d == "*") { block = 1; out = out "  "; i += 2; continue }
        if (c == "\"" || c == sq || c == "`") { str = c; if (c == "`") tpl = 1; out = out c; prev = c; i++; continue }
        if (c == "/" && (prev == "" || index("(,=:[!&|?{};+-*%~^>", prev) > 0)) {
          # A regular-expression literal: skip to its closing slash (not inside [...], not escaped).
          j = i + 1; incls = 0; e = 0
          while (j <= n) {
            ch = substr(line, j, 1)
            if (ch == "\\") { j += 2; continue }
            if (incls) { if (ch == "]") incls = 0 }
            else if (ch == "[") incls = 1
            else if (ch == "/") { e = j; break }
            j++
          }
          if (e > 0) { out = out "/" blanks(e - i - 1) "/"; prev = "x"; i = e + 1; continue }
        }
        if (c != " " && c != "\t") {
          pc = substr(out, length(out), 1)
          prev = ((c == "+" || c == "-") && pc == c) ? "x" : c
        }
        out = out c
        i++
      }
      # The end of what came before is joined on (runs of blanks collapsed, so blank lines and comments
      # cost nothing), so a call split over lines is seen. A match that ends inside that tail was
      # reported on its own line.
      cur = out; gsub(/[ \t]+/, " ", cur)
      joined = tail " " cur; off = length(tail) + 1
      if (hit(joined, re, off) || hit(joined, fre, off)) print NR
      tail = joined; if (length(tail) > 400) tail = substr(tail, length(tail) - 399)
    }
    END { if (block || tpl) print "?" }' "$1"
}

check_slice() {
  local slice="$1" meta="$evidence_dir/$1/meta.json" final_tree
  vetdd_is_slice_id "$slice" || { echo "schema: invalid slice id"; return; }
  if [ ! -f "$meta" ]; then echo "schema: no meta.json for this slice"; return; fi
  if ! jq -e --arg s "$slice" \
      '(.slice_id == $s) and (.runs | type == "array") and (.oracle.files | type == "array")' \
      "$meta" >/dev/null 2>&1; then
    echo "schema: meta.json is not valid evidence for slice '$slice'"
    return
  fi
  # A filter that errors on a malformed record prints nothing; that must fail, never read as OK.
  jq -r "$HISTORY_RULES" "$meta" 2>/dev/null || echo "1: could not evaluate the run history (a run record is malformed)"
  jq -r --arg slice "$slice" "$ORACLE_RULES" "$meta" 2>/dev/null || echo "8: could not evaluate the oracle chain (a run's oracle record or the version log is malformed)"

  final_tree="$(jq -r '[.runs[] | select(.kind == "after" or .kind == "integrated")] | last | .tree.tree_hash // empty' "$meta")"
  if [ -n "$final_tree" ]; then
    if [ -z "$current_tree" ]; then echo "5: could not hash the working tree"
    elif [ "$final_tree" != "$current_tree" ]; then
      echo "5: working tree $current_tree differs from the tree of the latest green run ($final_tree)"
    fi
  fi

  check_oracle_files "$meta"
  check_test_reports "$slice" "$meta"
  # Rule 10: a filter that fails prints nothing; that must fail the slice, never read as OK.
  jq -r --arg slice "$slice" "$AUDIT_RULES" "$meta" 2>/dev/null || echo "10: could not evaluate the undefined-imports audit (a run's audit record or the audits log is malformed)"
  check_mutation "$slice" "$meta"
}

# Rule 10c: problems on stdout, the ignored-mutant warning appended to $warn_file. The mutated files
# are hashed here: each must still hold the source the report mutated.
check_mutation() {
  local slice="$1" meta="$2" out path sum seq rel tr
  if ! out="$(jq -c --arg slice "$slice" "$MUTATION_RULES" "$meta" 2>/dev/null)" \
     || ! printf '%s' "$out" | jq -e '(.problems | type) == "array" and (.warns | type) == "array" and (.files | type) == "array"' >/dev/null 2>&1; then
    echo "10c: could not evaluate the mutation audit (a run's audit record or the audits log is malformed)"
    return
  fi
  printf '%s' "$out" | jq -r '.problems[]'
  printf '%s' "$out" | jq -r '.warns[]' >> "$warn_file"
  # The copy the judge reads: named from the run number evidence.sh wrote, never from a path in the record.
  if seq="$(printf '%s' "$out" | jq -r '.copy.seq // empty')" && [ -n "$seq" ]; then
    rel=".vetdd/evidence/$slice/runs/$(printf '%03d' "$seq")-mutation.json"
    if ! vetdd_inside_repo "$root" "$rel" || [ ! -f "$root/$rel" ] \
       || [ "$(vetdd_sha256 "$root/$rel")" != "$(printf '%s' "$out" | jq -r '.copy.sha256')" ]; then
      echo "10c: the copy of mutation run $seq's report is missing or does not match the sha256 recorded for it (or is a link); run the mutation audit again"
    else
      # The command runner is the one known to judge vitest 5 correctly (#20): any other runner is a warning.
      tr="$(jq -r '.config.testRunner // "" | if type == "string" then . else "?" end' "$root/$rel" 2>/dev/null)" || tr="?"
      if [ -z "$tr" ] && jq -e '(.config.command // null) == null' "$root/$rel" >/dev/null 2>&1; then
        # A copy from before testRunner was kept, with no command: not the command runner, or unknown.
        printf '%s\n' "10c: mutation run $seq does not say which Stryker runner it used (its report names no runner and no command), so it may be the vitest runner that reported killable mutants as Survived (vetdd #20); run the mutation audit again" >> "$warn_file"
      elif [ -n "$tr" ] && [ "$tr" != command ]; then
        printf '%s\n' "10c: mutation run $seq ran Stryker's $tr runner, not the command runner; Stryker's vitest runner reported killable mutants as Survived with vitest 5 (vetdd #20), so read its survivors before trusting them" >> "$warn_file"
      fi
    fi
  fi
  # NUL-separated: a path is read exactly as recorded, backslashes and all.
  while IFS= read -r -d '' path && IFS= read -r -d '' sum && IFS= read -r -d '' seq; do
    if [ -z "$path" ] || ! vetdd_inside_repo "$root" "$path" || [ ! -f "$root/$path" ] || [ "$(vetdd_sha256 "$root/$path")" != "$sum" ]; then
      echo "10c: ${path:-<an empty path>} changed since mutation run $seq (or is missing, a link, or outside the repository); run the mutation audit again on the delivered file"
    fi
  done < <(printf '%s' "$out" | jq -j '.files[] | .path, "\u0000", .sha256, "\u0000", (.seq | tostring), "\u0000"')
}

# Rules 6 and 9a, on the files the oracle names.
check_oracle_files() {
  local meta="$1" path want have found
  # Each entry is a repo-relative path and a hash; anything else is never skipped, and nothing
  # outside the repository is opened.
  if ! jq -e '(.oracle.files | type) == "array" and all(.oracle.files[];
        type == "object" and (.path | type) == "string" and ((.sha256 | type) == "string" or .sha256 == null)
        and (.path | startswith("/") | not) and (.path | split("/") | index("..") == null)
        and (.path | explode | all(. > 31 and (. < 127 or . > 159))))' "$meta" >/dev/null 2>&1; then
    echo "6: oracle.files holds an entry that is not a repo-relative path and a hash"
    return
  fi
  if [ "$(jq '.oracle.files | length' "$meta")" -eq 0 ]; then
    echo "6: oracle.files is empty; nothing binds the evidence to an oracle"
  fi
  jq -r '.oracle.files[] | "\(.path)\t\(.sha256 // "")"' "$meta" |
    while IFS="$(printf '\t')" read -r path want; do
      if ! vetdd_inside_repo "$root" "$path"; then echo "6: oracle file $path is a symbolic link or outside the repository"; continue; fi
      if [ ! -f "$root/$path" ]; then echo "6: oracle file $path is missing"; continue; fi
      have="$(vetdd_sha256 "$root/$path")"
      [ "$have" = "$want" ] || echo "6: oracle file $path changed since it was recorded; record the slice again with a bumped --oracle-version and a red for it (rule 8; a file shared with another slice: modes/test.md)"
    done

  # Rule 9a: a focused test in a JS or TS oracle file. Only files rule 6 could open are read.
  jq -r '.oracle.files[].path' "$meta" |
    while IFS= read -r path; do
      # Any letter case: a file system that ignores case still hands the file to the toolchain.
      case "$(printf '%s' "$path" | LC_ALL=C tr 'A-Z' 'a-z')" in
        *.js|*.jsx|*.mjs|*.cjs|*.ts|*.tsx|*.mts|*.cts) ;;
        *) continue ;;
      esac
      vetdd_inside_repo "$root" "$path" && [ -f "$root/$path" ] || continue
      # A scanner that fails prints nothing; that must fail the slice, never read as OK.
      found="$(focused_lines "$root/$path")" || { echo "9a: could not scan oracle file $path"; continue; }
      printf '%s\n' "$found" | while IFS= read -r n; do
        case "$n" in
          '') ;;
          '!'*) echo "9a: oracle file $path line ${n#!} is over 20000 characters; it was not scanned for a focused test, so split the line" ;;
          '?') echo "9a: oracle file $path could not be scanned to the end (a comment or template literal is still open there, or a regular expression was read as one); fix it or split the file" ;;
          *) echo "9a: oracle file $path line $n holds a focused test (.only or fdescribe); it runs only that test and skips the rest, so the green means less than it says. Remove it and record the slice again with a bumped --oracle-version (rule 8)" ;;
        esac
      done
    done
}

# Rules 9b (problems, on stdout) and 9c (warnings, appended to $warn_file).
# The oracle version the final green rests on (the last accepted green run, or else the last accepted
# run), as JSON; and one marker per accepted run, so a command whose latest run has no report is known.
FINAL_VERSION='
  [.runs[] | select(.accepted != false)] as $a
  | (([$a[] | select((.kind == "after" or .kind == "integrated") and .outcome == "pass")] | last) // ($a | last)) | .oracle.version | tojson'
RUN_MARKS='.runs[] | select(.accepted != false and (.seq | type) == "number" and .audit == null) | {m: true, seq, cmd, ov: .oracle.version}'

check_test_reports() {
  local slice="$1" meta="$2" list seq kind sum cmd ov rel copy stream="" marks fv tab line
  tab="$(printf '\t')"
  if ! fv="$(jq -r "$FINAL_VERSION" "$meta" 2>/dev/null)" || ! marks="$(jq -c "$RUN_MARKS" "$meta" 2>/dev/null)"; then
    echo "9b: could not evaluate the runs of the oracle version the final green rests on (a run record is malformed)"
    return
  fi
  if ! list="$(jq -r "$REPORT_RUNS" "$meta" 2>/dev/null)"; then
    echo "9b: could not evaluate which runs recorded a test report (a run record is malformed)"
  elif [ -n "$list" ]; then
    while IFS="$tab" read -r seq kind sum cmd ov; do
      if [ "$seq" = "?" ]; then echo "9b: could not read the test report copy of a run whose seq or kind is malformed"; continue; fi
      # The name is made from the seq and kind evidence.sh wrote, never from a path in the record.
      rel=".vetdd/evidence/$slice/runs/$(printf '%03d' "$seq")-$kind.tests.json"
      if ! vetdd_inside_repo "$root" "$rel" || [ ! -f "$root/$rel" ]; then
        echo "9b: could not read the test report copy of run $seq (it is missing, or it or its directory is a symbolic link)"; continue
      fi
      if [ "$sum" = "-" ] || [ "$(vetdd_sha256 "$root/$rel")" != "$sum" ]; then
        echo "9b: could not read the test report copy of run $seq (it does not match the sha256 recorded for it)"; continue
      fi
      if ! copy="$(jq -c --argjson seq "$seq" --argjson cmd "$cmd" --argjson ov "$ov" '
          if type == "object" and (.tests | type) == "array"
             and all(.tests[]; type == "object" and (.file | type) == "string" and (.name | type) == "string" and (.status | type) == "string")
          then {seq: $seq, cmd: $cmd, ov: $ov, tests: [.tests[] | {file, name, status}]} else error("shape") end' "$root/$rel" 2>/dev/null)"; then
        echo "9b: could not read the test report copy of run $seq (it is not a normalized test report)"; continue
      fi
      stream="$stream$copy"$'\n'
    done <<< "$list"
    # A filter that fails prints nothing; that must fail the slice, never read as OK.
    if [ -n "$stream" ]; then
      printf '%s\n%s\n' "$stream" "$marks" | jq -r -s --argjson max 5 --argjson fv "$fv" "$TEST_DROP_RULES" 2>/dev/null || echo "9b: could not compare the test reports of the runs"
    fi
  fi
  if line="$(jq -r --argjson fv "$fv" "$TEST_WARN_RULES" "$meta" 2>/dev/null)"; then
    [ -z "$line" ] || printf '%s\n' "$line" >> "$warn_file"
  else
    echo "9c: could not evaluate the skipped and todo counts (a run's tests record is malformed)"
  fi
}

failed=0
for slice in "${slices[@]}"; do
  # Pass or fail is decided on the raw problems; the display filter only shapes what is shown.
  : > "$warn_file"
  problems="$(check_slice "$slice")"
  # A name that is not a slice id (a stray directory, possibly holding control characters or
  # newlines) is never printed as given.
  if vetdd_is_slice_id "$slice"; then shown="$slice"; else shown="<invalid slice name>"; fi
  if [ -z "$problems" ]; then
    echo "$shown: OK"
  else
    failed=$((failed + 1))
    # Recorded values (versions, paths) reach the terminal: strip control characters.
    shown_problems="$(printf '%s\n' "$problems" | vetdd_printable)"
    [ -n "$shown_problems" ] || shown_problems="a problem that could not be displayed"
    printf '%s\n' "$shown_problems" | while IFS= read -r line; do echo "$shown: FAIL ($line)"; done
  fi
  # Warnings never change the exit code. The display filter runs on them too.
  if [ -s "$warn_file" ]; then
    vetdd_printable < "$warn_file" | while IFS= read -r line; do [ -z "$line" ] || echo "$shown: WARN ($line)"; done
  fi
done
[ "$failed" -le 125 ] || failed=125
exit "$failed"
