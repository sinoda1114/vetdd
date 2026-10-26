#!/usr/bin/env bash
# Check recorded evidence (plan §2.4).
# Usage: check-evidence.sh [--repo <dir>] [--before-close] [<slice-id>...]
# History:  (1) a red run precedes the first green run, and no red before follows the last green
#           (2) accepted before runs are target_failure
#           (3) accepted after/integrated runs are pass, and the latest after/integrated run passed
#           (4) infrastructure_error / inconclusive never count as red or green
# Final:    (5) the latest after/integrated tree_hash matches the current working tree
#           (6) oracle.files sha256 match the current files
# Focus:    (9a) no focused test (.only, fdescribe) in a JS or TS oracle file (lib/common.sh
#               VETDD_JS_TS_RE, as for 10c): it would run only that
#               test and skip the rest. The file is read as code (comments, strings, templates, and
#               regular-expression literals blanked, across lines). A best-effort tripwire for an
#               accident, not a boundary, frozen as it is (#7): fit(, a renamed or wrapped focus, a
#               helper, a file not named with --oracle-file, another language, and the blind spots
#               listed above focused_lines pass it; the final judge, who reads the tests, is the backstop.
# Oracle:   (8) the version chain of accepted runs: an oracle is its version plus the sha256 of its
#               files. Within the final green's version the files do not change from its first red
#               on, nor after any green of that version (edits before the first red are the test
#               being written); the final green has a red with the same oracle before it (a red the
#               command produced: not one whose run records outcome_forced, and, for a run recorded before
#               evidence.sh kept that field, not one on exit 0, 126, or 127); the final version is
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
#               latest accepted green (after or integrated) of the same command and oracle version, so a
#               calibration or a red recorded after it never moves the comparison, for the version the final
#               green rests on (an older version left behind is history; bumping --oracle-version, with
#               its entry in the version log, is the way out of a skip that is meant). Cmd is compared as
#               JSON. The report is the normalized copy that evidence.sh --test-report saves
#               (runs/<seq>-<kind>.tests.json, opened by a name made from seq and kind, only through a
#               safe path, and only if its sha256 matches the record). A command whose latest green has no
#               usable report (absent, missing, invalid) is not compared (9c warns), nor is a command that
#               never went green (its runs back no green); a copy that cannot be read for a run of the
#               final version recorded ok fails (the copies of an older version are history: not opened). This is IDS's count of unfinished tests (the Admitted
#               holes), taken from the runner's report. A tripwire, not a boundary: a test that
#               disappears altogether, a changed command (a name filter), a renamed test, tests sharing a
#               file and a name (read as one), a skip written into an oracle file itself (its hash change
#               needs a version bump, so it starts a new comparison), a slice that never asks for a report,
#               and a copy and its sha256 both rewritten by hand all pass it.
#           (9c) a warning, never a failure, per command that asked for a report at some point (among the
#               runs of the final version): its own latest green run has skipped or todo tests (counts
#               shown; when an earlier run of the same command has a copy, split into those skipped or
#               todo already in the first such run, as a name filter leaves the same tests out each
#               time, and the newly skipped or todo), or has no usable report. A command that never asked for one (a type check) and a
#               slice whose runs never record a report (old evidence) are not warned: a blind spot.
# Audit:    (10a) a calibration run marked audit undefined-imports (calibrate.sh stub: every product file the
#               oracle imports replaced by a stub with undefined exports) that is accepted and ended pass,
#               with the oracle of the final green (an audit of a version left behind is history): the
#               test observes nothing. A retake clears it: an audit run recorded later (a higher seq) on
#               the same oracle that 10b counts as caught, lists its stubs (audit.files present), ran the
#               same command (argv) in the same directory as the passing audit, and stubbed another set
#               of files. So an audit that passed only because --file named the wrong files needs no
#               version bump once calibrate.sh stub is run again with the right ones. A passing audit
#               after the last such catch still fails. A tripwire: why the retake went red is not
#               checked (its log must show the test's own failure).
#           (10b) the oracle of the final green run has an accepted audit run, recorded after a green run
#               of that oracle, that ended target_failure (not forced with --outcome; the command is
#               not compared with the green's, a blind spot) and whose audit.files are the stubs calibrate.sh
#               stub writes (lib/stub.sh: the sha256 of each recorded file is that of a stub its extension
#               can take; a record that is not fails, and a run recorded before audit.files existed counts
#               with a WARN: a tripwire, since anyone who can write the git dir can fake the stub state
#               evidence.sh asks for, and a stub's text says nothing of which product file it replaced),
#               or an audits[] entry not_applicable with a reason
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
#               and its mutated files still hold the source it mutated, and, when its command is
#               npx [--no-install] vitest run with single-quoted or plain file filters, it names at least
#               one and each is the end of an oracle file path of the final oracle, whole components
#               (ignoring ASCII letter case, as vitest does), so a filter that names another test file
#               is caught; with no such run, a mutation
#               note written after the final oracle first ran. Ignored mutants are a WARN (10c). Asked
#               of a slice whose final oracle has a JS or TS file (.js .jsx .mjs .cjs .ts .tsx .mts
#               .cts, any letter case: lib/common.sh VETDD_JS_TS_RE, as for 9a), and of any other slice
#               with a mutation run or note. A tripwire, not a boundary: it trusts the
#               report (what Stryker mutated and how it ran), a vitest command it cannot read (options,
#               double quotes, a non-ASCII, // or .. path) is a WARN, a command without vitest (a verify
#               wrapper) is not read, a filter that matches can still select more files (the ts-kata
#               config refuses that), and the ranges are the judge's to check. A mutated source with a
#               bidirectional or other control character is a WARN.
# Stall:    (11) every handover file (.vetdd/evidence/<slice>/handover-<n>.md, n = 1, 2, ... as handover.sh
#               names it: the mark of a redesign; another name, such as handover-draft.md, is not one)
#               has each heading. A record that holds more stalls (lib/stall.sh with the
#               default K = 2) than handovers is a WARN, not a FAIL: the agreement can change K, and
#               a worker reports a stall rather than writing the handover. A tripwire, not a boundary:
#               it checks that the diagnosis was written down, not that it is right.
# Planted:  (12) every run that records what was planted (planted: {patch, sha256, files}, written by
#               calibrate.sh planted) is a calibration whose patch is runs/<seq>-planted.patch, named from
#               its own seq, with a sha256 and at least one file; the copy is there (not a link) and
#               matches the recorded sha256, as rule 10c checks the mutation report's copy. A run without
#               the field (an unfix, a plain calibration, evidence from before it) is not asked. A
#               tripwire, not a boundary: a copy and its sha256 both rewritten by hand pass it.
# Abandoned: a slice the parent marked abandoned in a swarm or an arena (.vetdd/evidence/<slice>/abandoned,
#         worktree.sh abandon: a stall, a conflict, or a lane that lost) is not delivered: rules 1-10 and 12
#         are not asked of it, and it is not a failure; with cause stall, rule 11 still is (its handovers are
#         the redesign's record). A mark that is not what worktree.sh abandon writes (one JSON object with
#         cause, recorded_at, and an optional replaced_by; a regular file) fails the slice.
# Output: "<slice>: OK" or one "<slice>: FAIL (<rule>: <reason>)" line per failing rule, then one
#         "<slice>: WARN (9c|10b|10c|11: <reason>)" line per warning (advice for the reply's Attention section;
#         it holds no recorded text). An abandoned slice gets "<slice>: ABANDONED (<cause>[, replaced by
#         <id>])" first, then its rule 11 FAIL and WARN lines, if any.
# --before-close (the pre-commit hook; also VETDD_BEFORE_CLOSE=1, which lib/common.sh sets in any
#         pre-commit hook): a slice whose final oracle has a JS or TS file and whose mutation audit has
#         not run yet gets a 10c WARN, not a FAIL, since the audit waits for Close (Close step 3 is what
#         stops it); every other failure stays a FAIL, also the missing audit of another slice with a
#         mutation run or note (one recorded before its last green no longer counts).
# Exit code: number of failing slices (capped at 125; a WARN or ABANDONED line never counts); 2 on usage
#         errors.
set -u

die() { printf 'check-evidence.sh: %s\n' "$1" >&2; exit 2; }

. "${BASH_SOURCE[0]%/*}/lib/common.sh"
vetdd_require_jq check-evidence.sh
. "${BASH_SOURCE[0]%/*}/lib/tree-hash.sh"
. "${BASH_SOURCE[0]%/*}/lib/stall.sh"
. "${BASH_SOURCE[0]%/*}/lib/mutation-report.sh"
. "${BASH_SOURCE[0]%/*}/lib/stub.sh"

repo="."
slices=()
before_close=false
# Set by lib/common.sh in a pre-commit hook (a hook installed before #25 does not pass the option).
[ "${VETDD_BEFORE_CLOSE:-}" = 1 ] && before_close=true
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] || die "--repo needs a value"; repo="$2"; shift 2 ;;
    --before-close) before_close=true; shift ;;
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

# jq definitions the rules over the runs share, so rules 1-4, 8, 10, and 10c agree on what a green run,
# an oracle, and a run the oracle chain can place are (#16).
RUN_DEFS='
def green: .kind == "after" or .kind == "integrated";
def oid: {v: (.oracle.version // null), f: ((.oracle.files // []) | map({path, sha256}) | sort_by(.path))};
def recorded: (.oracle | type) == "object" and (.oracle.files | type) == "array";
# A run the oracle chain can place: an oracle record and a numeric exit code (rule 8 fails any other).
def usable: recorded and (.exit_code | type) == "number";
def num: if type == "number" then floor | tostring else error("not a number") end;
# An outcome the command itself produced. evidence.sh records outcome_forced on a run whose --outcome
# differs from what its exit code says; a run recorded before that field is judged by its exit code: an
# outcome other than pass on exit 0, or a red on a command that could not run (126, 127), was forced.
def unforced: .outcome_forced != true and .exit_code != 0 and .exit_code != 126 and .exit_code != 127;
# A not_applicable note counts for the final oracle when it was written after that oracle first ran:
# by after_seq (the last run number then) when it has one, else by its time (a note written before
# after_seq existed). With nothing to compare, it counts for nothing.
def counts_for($first; $first_seq):
  if (.after_seq | type) == "number" then $first_seq != null and $first_seq <= .after_seq
  else $first != null and (.recorded_at | type) == "string" and .recorded_at >= $first end;
'

# Rules 1-4 and the rule-5 precondition, as "<rule>: <reason>" lines.
HISTORY_RULES="$RUN_DEFS"'
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
    ($acc[] | select(green and .outcome == "pass" and (.outcome_forced == true or (.exit_code // 0) != 0))
     | "3: \(.kind) run \(.seq) ended pass only because --outcome forced it (the command exited \(.exit_code)); the evidence cannot be edited back, so fix the cause and record the slice again under a new slice id"),
    (if $last_green != null and ($last_green.accepted == false or $last_green.outcome != "pass")
     then "3: latest \($last_green.kind) run \($last_green.seq) ended \($last_green.outcome)"
     else empty end),
    ($acc[] | select(.kind != "calibration" and neither)
     | "4: \(.kind) run \(.seq) is accepted but ended \(.outcome), which is neither red nor green"),
    (if $last_green == null then "5: no after or integrated run" else empty end)
  )'

# Rule 8, over accepted runs in seq order, each with the oracle it was measured with.
ORACLE_RULES="$RUN_DEFS"'
# A red the command itself produced: an outcome forced with --outcome is not one.
def red: (.kind == "before" or .kind == "calibration") and .outcome == "target_failure"
         and .audit == null and unforced;
def vname: if . == null then "unset" else tostring end;
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
           then "8: the only red runs with the oracle of the final green run \($g.seq) (version \(($g | oid).v | vname)) were forced with --outcome (on a command that exited 0, could not run (126, 127), or exited with a code declared with --infra-exit); make the oracle run and report failure through its exit code (references/feedback-loop-ladder.md)"
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
AUDIT_RULES="$RUN_DEFS"'
def audited: .audit.kind == "undefined-imports";
# $bad: the seqs of audit runs whose audit.files are not the stubs; $old: those with no audit.files (shell).
def listed($l): (.seq | floor) as $s | any($l[]; . == $s);
. as $meta
| [.runs[] | select(.accepted != false)] as $accepted
| [$accepted[] | select(usable)] as $acc
| ([$acc[] | select(green and .outcome == "pass")] | sort_by(.seq) | last) as $g
| [$accepted[] | select(.kind == "calibration" and audited)] as $audits
# The caught audits of the final oracle (10b counts them; a later one clears a 10a): ended target_failure,
# not forced, audit.files the stubs, and recorded after a green run of the same oracle (before that, the
# red is the unfixed product).
| (if $g == null then [] else
     ($g | oid) as $fo
     | [$acc[] | select(green and .outcome == "pass" and oid == $fo)] as $greens
     | [$acc[] | select(.kind == "calibration" and audited and .outcome == "target_failure" and unforced
                        and oid == $fo and (listed($bad) | not))
               | . as $a | select(any($greens[]; .seq < $a.seq))]
   end) as $caughtruns
# Opted in to the undefined-imports audit: a run with its mark, or an audits key that is empty, not an
# array, or holds any entry but a mutation note; a run with any audit mark but mutation (an unknown kind
# fails closed, in both places). A mutation run or note alone opts in to nothing here.
| (($meta | has("audits")) and (($meta.audits | type) != "array" or ($meta.audits | length) == 0
     or any($meta.audits[]; type != "object" or .kind != "mutation"))) as $noted_key
| ($noted_key or ([$meta.runs[] | .audit as $a | $a != null and (($a | type) != "object" or $a.kind != "mutation")] | any)) as $opted
| (
    # A retake clears it: a caught audit recorded later (a higher seq) on the same oracle, with its stubs
    # listed (one recorded before audit.files existed does not show which files it stubbed), the same
    # command in the same directory (a red of another command says nothing of the test), and another set
    # of stubbed files (the same audit again that went red is a flaky run, not the right --file).
    ($audits[] | select(.outcome == "pass") | select($g == null or oid == ($g | oid))
     | . as $p
     | select(any($caughtruns[]; (listed($old) | not) and (.seq | type) == "number"
                                 and ($p.seq | type) == "number" and .seq > $p.seq
                                 and .cmd == $p.cmd and .conditions.cwd == $p.conditions.cwd
                                 and ([.audit.files[]? | .path?] | sort) != ([$p.audit.files[]? | .path?] | sort))
              | not)
     | "10a: the audit run \(.seq | num) (every import stubbed with undefined) still passed, so the test observes nothing; make the test call or check the product code"),
    ($audits[] | select(listed($bad)) | select($g == null or oid == ($g | oid))
     | "10b: undefined-imports audit run \(.seq | num) does not record the stubs calibrate.sh stub writes (audit.files: each stubbed file with the sha256 of its stub), so it is not counted, and the record cannot be edited back: bump --oracle-version, record the new version with oracle-version.sh first, then its red, its green, and calibrate.sh stub"),
    (if ($meta | has("audits")) and ($meta.audits | type) != "array"
     then "10: audits is not an array, so the audit notes cannot be checked"
     elif $opted and $g != null then
       ($g | oid) as $fo
       | ($caughtruns | length) as $caught
       # A note counts for the final oracle when it was recorded after that oracle first ran (the entry
       # has no version of its own); with no start time to compare, it counts for nothing.
       | ([$acc[] | select(oid == $fo) | .started_at | select(type == "string")] | min) as $first
       | ([$acc[] | select(oid == $fo) | .seq | numbers] | min) as $first_seq
       | ((($meta.audits // []) | map(select(type == "object" and .kind == "undefined-imports" and .status == "not_applicable"
                                              and (.reason | type) == "string" and (.reason | length) > 0
                                              and counts_for($first; $first_seq))) | length)) as $noted
       | ($caughtruns[] | select(listed($old))
          | "WARN:10b: undefined-imports audit run \(.seq | num) records no stubbed files (it was recorded before audit runs listed them), so 10b could not check that its files were the stubs"),
         (if $caught + $noted == 0
         then "10b: no undefined-imports audit for the final oracle after a green run of it; run calibrate.sh stub \($slice) --file <product files> --oracle-file <test files> -- <command> (it must end target_failure), or record why it does not apply with audit-note.sh \($slice) --kind undefined-imports --not-applicable --reason-file <path>"
         else empty end)
     else empty end)
  )'

# Rule 10c, over the accepted runs and the audits log: the mutation audit of the final oracle. One JSON
# object: problems and warnings (rule text with run numbers only), and the files of the judged run for
# the shell to hash. Asked of a slice whose final oracle has a JS or TS file ($jsts_re, VETDD_JS_TS_RE),
# and of any other slice with a mutation run or a mutation note.
MUTATION_RULES="$RUN_DEFS$VETDD_JQ_CLEAN"'
def nn: if type == "number" and . >= 0 then . else error("not a count") end;
def mut: (.audit | type) == "object" and .audit.kind == "mutation";
# The way out of a run of no mutant whose --mutate value was empty (in the argv of the run: --mutate or -m
# followed by an empty word or by nothing, or --mutate=): mutate-ranges.sh had nothing to print (#74),
# and a note does not lift a run after the last green, so the green is recorded again.
def empty_mutate: (.cmd | if type == "array" then . else [] end) as $c
  | any(range(0; $c | length); ($c[.] == "--mutate" or $c[.] == "-m") and (($c[. + 1] // "") == ""))
    or any($c[]; . == "--mutate=" or . == "-m=");
def test_only: "; the --mutate value was empty: when mutate-ranges.sh \($slice) exits 3 (nothing to mutate: a slice that changed only its tests, or no file Stryker mutates), run no audit: record why with audit-note.sh \($slice) --kind mutation --not-applicable --reason-file <path>, then the slice'"'"'s green again (evidence.sh \($slice) integrated -- <the slice'"'"'s test command>), since a note does not lift a mutation run after the last green";
. as $meta
| [.runs[] | select(.accepted != false and usable)] as $acc
| ($acc | map(select(green and .outcome == "pass")) | sort_by(.seq) | last) as $g
# A final oracle with a JS or TS file is always asked (#25: Stryker covers those languages); any other
# slice only once it has a mutation run or note.
| ($g != null and ([$g.oracle.files[]? | .path? | strings | select(test($jsts_re))] | length > 0)) as $jsts
| (([$meta.runs[] | mut] | any) or ([($meta.audits // [])[] | select(type == "object" and .kind == "mutation")] | length > 0)
   or $jsts) as $opted
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
        ("10c: no mutation audit for the final oracle after its last green run; run r=\"$(mutate-ranges.sh \($slice))\" && VETDD_MUTATION_TESTS=<the slice'"'"'s test files, one per line> evidence.sh \($slice) calibration --audit mutation --mutation-report stryker-json:<the jsonReporter.fileName of the Stryker config> -- npx --no-install stryker run <the Stryker config> --mutate \"$r\" (the ranges widened to whole statements when they need it, modes/test.md Audits › Mutation), or record why it does not apply (mutate-ranges.sh exits 3 when there is nothing to mutate) with audit-note.sh \($slice) --kind mutation --not-applicable --reason-file <path>") as $missing
        # Before Close (the pre-commit hook) the audit of a JS or TS slice is not due yet: say so, do not
        # block. Another slice is asked only once it ran an audit or wrote a note: a missing one fails.
        | if $noted > 0 then {copy: null, problems: [], warns: [], files: []}
          elif $before_close and $jsts then {copy: null, problems: [], warns: [$missing + " (due in Close; not yet run)"], files: []}
          else {copy: null, problems: [$missing], warns: [], files: []} end
      else
        ($m.seq | num) as $s | $m.audit.report as $rep
        | if ($rep | type) != "object" then error("no report")
          elif $rep.status != "ok" then
            {copy: null, problems: [if $rep.status == "empty"
                then "10c: mutation run \($s) mutated nothing: the --mutate ranges held no mutant; widen them to the function'"'"'s closing brace\(if $m | empty_mutate then test_only else "" end)"
                elif $rep.status == "missing" then "10c: the report of mutation run \($s) is missing; run the mutation audit again"
                else "10c: the report of mutation run \($s) is invalid; run the mutation audit again (evidence.sh printed why when it recorded the run)" end], warns: [], files: []}
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
               # A path is shown only when it is clean and short; it is still checked either way.
               files: [$files[] | {path, sha256, seq: $s, shown: (if (.path | clean) and (.path | length) <= 256 then .path else "" end)}],
               copy: {seq: $s, sha256: $csum, oracle: [$fo.f[].path | strings]}}
          end
      end
  end'

# Rule 10c, on the copy of the judged run (its sha256 checked), with $o the paths of the final oracle and
# $root the repository: which test files its command ran against the mutants. Each file filter of an
# npx [--no-install] vitest run command (plain words and single-quoted ones; an absolute one under $root
# read from $root) is a match when it is the end of an oracle file path at a component boundary,
# ignoring ASCII letter case as vitest does; unreadable when it is still absolute (outside $root, or
# $root spelled through a link), holds a non-ASCII character (vitest folds its case, jq cannot), // or
# a . or .. component; else no match. An option anywhere makes the whole command unread (it may take the
# next word as its value). The answer: "other" when a filter
# matches no oracle file, "none" for no filter (every test file), "unread" for an unreadable filter or a
# vitest command of another shape (options, double quotes, other shell syntax), "ok", or "skip" for no
# command or one without vitest (a verify wrapper): the judge reads that. A tripwire, not a boundary:
# vitest selects every file whose path holds a filter, so a filter that matches can still select more
# files; the ts-kata config refuses one that selects more than one, a config without that check does not.
COMMAND_FILTERS='
  def nodots: if startswith("./") then .[2:] | nodots else . end;
  # On the filter as written ($r) and with the repository and leading ./ taken off (.).
  def unreadable($r): ($r | startswith("-")) or ($r | explode | any(.[]; . > 126)) or ($r | test("//"))
    or startswith("/") or (split("/") | any(.[]; . == "." or . == ".."));
  (.config.command // null) as $c
  | if ($c | type) != "string" or ($c | test("vitest") | not) then "skip"
    else (($c | capture("^npx (--no-install )?vitest run(?<rest>( +([A-Za-z0-9._/@+=:,%^][A-Za-z0-9._/@+=:,%~^-]*|\u0027([^\u0027]|\u0027\\\\\u0027\u0027)*\u0027))*) *$"))? // null) as $m
      | if $m == null then "unread"
        else [$m.rest | scan("\u0027((?:[^\u0027]|\u0027\\\\\u0027\u0027)*)\u0027|([^ \u0027]+)") | (.[0] // .[1])
              | gsub("\u0027\\\\\u0027\u0027"; "\u0027") | {r: ., n: (ltrimstr($root + "/") | nodots)}] as $t
          | ($o | map("/" + ascii_downcase)) as $paths
          | [$t[] | .r as $r | .n | select(unreadable($r) | not) | ascii_downcase] as $plain
          # An option may take the next word as its value, so no word after one can be read as a filter.
          | if any($t[]; .r | startswith("-")) then "unread"
            elif any($plain[]; . as $f | $f == "" or (any($paths[]; endswith("/" + $f)) | not)) then "other"
            elif ($t | length) == 0 then "none"
            elif ($plain | length) < ($t | length) then "unread"
            else "ok" end
        end
    end'

# Rule 12, one line per run that carries planted: "<seq>\t<sha256>\tok" when the record has the shape
# calibrate.sh writes (the patch named from the run's own seq), "<seq>\t-\tbad" when not, "?" for a seq
# that is not a run number (the copy's name is made from it, so nothing is opened).
PLANTED_RUNS='
  .runs[] | select(type == "object" and has("planted"))
  | if (.seq | type) == "number" and .seq >= 1 and .seq < 1000000 and .seq == (.seq | floor) then
      (.seq | floor | tostring) as $s
      | ("runs/" + (if ($s | length) < 3 then ("00" + $s)[-3:] else $s end) + "-planted.patch") as $want
      | if .kind == "calibration" and (.planted | type) == "object" and .planted.patch == $want
           and (.planted.sha256 | type) == "string" and (.planted.sha256 | test("^[0-9a-f]{64}$"))
           and (.planted.files | type) == "array" and (.planted.files | length) > 0
           and all(.planted.files[]; type == "string" and length > 0)
        then "\($s)\t\(.planted.sha256)\tok" else "\($s)\t-\tbad" end
    else "?" end'

# Warnings (rules 9c, 10c, 11) travel on the same stdout as the problems, each line prefixed with $WARN;
# every other line is a problem and decides pass or fail. A problem always starts with its rule, so one
# whose recorded text holds a new line still fails the slice (the rest of it may show as a warning).
WARN="$(printf 'warn\t')"

current_tree="$(vetdd_tree_hash "$root")" || current_tree=""

# Rule 9b, step 1: the accepted runs of the version the final green rests on ($fv) that recorded a usable
# report, one line each: seq, kind, sha256 of the copy ("-" when the record has none), and the command as
# one line of JSON. A run under an older version is history: its copy is never opened. A run whose seq
# or kind is not what evidence.sh writes prints "?": the copy's name is made from them, so nothing else
# is opened.
REPORT_RUNS='
  .runs[] | select(.accepted != false and .audit == null and (.tests | type) == "object" and .tests.status == "ok"
                   and .oracle.version == $fv)
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
# The input holds the readable copies ({seq, cmd, ov, tests}) and one marker ({m: true, seq, cmd, ov, kind})
# for every accepted run, whether or not it has a report. Only the version the final green rests on is
# compared (an older version left behind is history), and per command only its latest green (after or
# integrated, as 9c reads it), when that run has a copy, against the copies of the runs before it.
(. | map(select(.m != true))) as $copies
| (. | map(select(.m == true))) as $marks
| [ ($copies | group_by([.cmd, .ov] | tojson)[]) | sort_by(.seq) | . as $g
  | select($g[0].ov == $fv)
  | ([$marks[] | select(.cmd == $g[0].cmd and .ov == $g[0].ov and (.kind == "after" or .kind == "integrated")) | .seq] | max) as $ls
  | select($ls != null)
  | ([$g[] | select(.seq == $ls)] | first) as $l
  | select($l != null)
  | [$g[] | select(.seq < $ls)] as $earlier
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
| ($f[:$max][] | "9b: test \"\(.d.name | show)\" in \(.d.file | show) ran (\(.was)) in run \(.e) but is \(.d.status) in run \(.l), the latest green of the same command and oracle version; a test that stops running makes the green mean less than it says. Run it again; if it is meant to be \(.d.status), bump --oracle-version, record why with oracle-version.sh, and record the slice again"),
  (if ($f | length) > $max then "9b: and \($f | length - $max) more tests ran in an earlier run and are skipped or todo in the latest green of their command" else empty end)'

# Rule 9c, over the same input as TEST_DROP_RULES: per command of the final version whose latest green
# (as 9b reads it) has a copy and an earlier run of it has one too, its skipped and todo tests split in
# two: those skipped or todo already in the first run of the command with a copy (a name filter leaves
# the same tests out every time), and the rest (newly skipped or todo). One array of
# {cmd, l: the latest green, f: the first run, old, new}.
SKIP_SPLIT='
def idle: .status == "skipped" or .status == "pending" or .status == "disabled" or .status == "todo";
(. | map(select(.m != true))) as $copies
| (. | map(select(.m == true))) as $marks
| [ ($copies | map(select(.ov == $fv)) | group_by(.cmd | tojson)[]) | sort_by(.seq) | . as $g
  | ([$marks[] | select(.cmd == $g[0].cmd and .ov == $fv and (.kind == "after" or .kind == "integrated")) | .seq] | max) as $ls
  | select($ls != null and $g[0].seq < $ls)
  | ([$g[] | select(.seq == $ls)] | first) as $l
  | select($l != null)
  # The tests idle in the first run: every result of the test (file and name) skipped or todo there.
  | (reduce ($g[0].tests | group_by([.file, .name])[] | select(all(.[]; idle)) | [.[0].file, .[0].name] | tojson) as $k
       ({}; .[$k] = true)) as $was
  | [$l.tests[] | select(idle) | ($was[[.file, .name] | tojson] == true)] as $d
  | {cmd: $l.cmd, l: $ls, f: $g[0].seq, old: ($d | map(select(.)) | length), new: ($d | map(select(. | not)) | length)}
]'

# Rule 9c: warnings only (no recorded text in them: counts, a run number, and fixed words). A count that
# is not a number is an error: nothing prints, and the caller fails the slice. $splits is SKIP_SPLIT's.
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
     | ([$splits[] | select(.cmd == $l.cmd and .l == $l.seq)] | first) as $sp
     | "9c: \($sk) skipped and \($td) todo tests in the latest \($l.kind) run \($s), counted from the runner'"'"'s report (tests left out by a name filter count as skipped)"
       + (if $sp == null then ""
          else ": \($sp.old | num) of them were skipped or todo already in run \($sp.f | num | floor), the first run of the same command with a report (as a name filter leaves the same tests out every time), and \($sp.new | num) are newly skipped or todo" end)
       + "; they did not run, so the green says nothing about them. Put them in the reply'"'"'s Attention")
  elif ($l.tests | type) == "object" then
    "9c: the latest \($l.kind) run \($s) asked for a test report but it is \(if $l.tests.status == "missing" then "missing" elif $l.tests.status == "invalid" then "invalid" else "unusable" end); skipped and todo tests cannot be counted. Put this in the reply'"'"'s Attention"
  else
    "9c: no test report was recorded for the latest \($l.kind) run \($s), though another run of the same command asked for one; skipped and todo tests cannot be counted. Record the run with --test-report and put this in the reply'"'"'s Attention"
  end'

# Lines of a JS or TS oracle file that hold a focused test, one per output line: the line number,
# "!<line>" for a long line that was not searched, "+<line>" for a line too long to read at all, or
# "?" when a comment or template literal is still open at the end of the file (the scan cannot be
# trusted). The file is read as code: comments (// and /* */)
# and the contents of strings, template literals, and regular-expression literals are blanked first,
# across lines (a string continued with a backslash included), then the code is searched for
# <it|test|describe|suite|context|specify>[.name]*.only[.name]*( or `, spacing, comments, and a line
# break allowed between the tokens, or fdescribe(. The root name must stand alone (not myit.only, not
# this.it.only, however spaced).
#
# A line over 20000 characters (a minified file) is read for what it opens and closes (comments,
# strings, templates) and for the code it ends with, so the lines after it are read right, but it is
# searched only when it cannot hold a focus: when neither its code nor the code just before it (the
# last 400 characters, as for any line) holds the text only or fdescribe (strings and comments do not
# count). Otherwise it is "!" (not searched, so the slice fails). A line over 1000000 characters is
# not scanned at all, to bound the time: it is "+", and the lines after it may be misread. A long line
# with a slash that opens a regular expression it never closes is "!" too, read on with every later
# slash as a division. Time is linear in the length of a long line, and the memory of the scan does
# not grow with it (awk still holds the line itself).
#
# Known limits. The scanner is frozen (#7): it is a best-effort tripwire for an accident, not a
# boundary, and the final judge, who reads the delivered tests in full, is the backstop. Each of these
# passes it or is misread, and none will be fixed here:
# - fit( is not covered (a common name for other functions), nor a focus API renamed or wrapped in a
#   helper.
# - A type argument that holds parentheses hides the call: test.only<{ fn: () => void }>("x", ...).
# - A regular-expression literal right after a keyword such as return or typeof reads as a division.
# - A division written right after a > reads as a regular expression (the code up to the next slash on
#   the line is blanked).
# - JSX text is read as code: an it.only( written there is reported, and a bare backtick or quote
#   there can hide what follows.
# - Code inside ${...} in a template literal is not searched.
# - Only the last 400 characters of earlier code (blanks collapsed) are joined to a line, so a call
#   split from its only by more than that (a long type argument: it.only<{ ... }> on one line, its
#   ("x", ...) on the next) is not seen, on a short line or a long one.
# - A line over 20000 characters whose code holds the text only or fdescribe (a name such as readonly
#   included) or a slash read as a regular expression it never closes, or any line over 1000000
#   characters, fails the slice though it may hold no focus; split the line.
# The lasting answer is the runner's own count of skipped tests (rule 9c, --test-report), not the
# source.
focused_lines() {
  LC_ALL=C awk -v sq="'" '
    # The character at position p of the line (n characters long), from a split of the 10000-character
    # piece that holds it: substr measures the whole line on every call in some awks, which makes a
    # long line quadratic, and a split of the whole line costs memory in proportion to its length.
    function at(p) {
      if (p > n) return ""
      if (p < base || p >= base + 10000) { base = p - (p - 1) % 10000; split(substr(line, base, 10000), cs, "") }
      return cs[p - base + 1]
    }
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
      # An awk that does not split "" into characters would misread every line: fail, never OK.
      if (split("ab", t, "") != 2) exit 2
    }
    {
      line = $0; sub(/\r$/, "", line); n = length(line); base = -10000
      if (n > 1000000) { print "+" NR; next }
      # A long line is searched only when it cannot hold a focus (see above), but it is read either way
      # for what it opens and closes; its output is cut down as it is built, keeping the end the next
      # line is joined to, after it is looked at for the text only or fdescribe in code.
      long = (n > 20000); seen = long && (index(tail, "only") || index(tail, "fdescribe")); norx = 0
      out = ""; i = 1; k = 0; str = carry; carry = ""
      if (tpl) str = "`"
      while (i <= n) {
        if (long && ++k % 1000 == 0 && length(out) > 2000) {
          if (index(out, "only") || index(out, "fdescribe")) seen = 1
          gsub(/[ \t]+/, " ", out); if (length(out) > 400) out = substr(out, length(out) - 399)
        }
        c = at(i); d = at(i + 1)
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
        if (c == "/" && !norx && (prev == "" || index("(,=:[!&|?{};+-*%~^>", prev) > 0)) {
          # A regular-expression literal: skip to its closing slash (not inside [...], not escaped).
          j = i + 1; incls = 0; e = 0
          while (j <= n) {
            ch = at(j)
            if (ch == "\\") { j += 2; continue }
            if (incls) { if (ch == "]") incls = 0 }
            else if (ch == "[") incls = 1
            else if (ch == "/") { e = j; break }
            j++
          }
          # One blank stands for the whole body: the output is only ever read with blanks collapsed.
          if (e > 0) { out = out "/ /"; prev = "x"; i = e + 1; continue }
          # On a long line, each such slash would be read to the end of the line again: the line is not
          # searched, and the rest of it is read with every slash as a division.
          if (long) { seen = 1; norx = 1 }
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
      if (long && (index(out, "only") || index(out, "fdescribe"))) seen = 1
      if (seen) print "!" NR
      else if (hit(joined, re, off) || hit(joined, fre, off)) print NR
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
  check_audit "$slice" "$meta"
  check_mutation "$slice" "$meta"
  check_stall "$slice" "$meta"
  check_planted "$slice" "$meta"
}

# Rule 10: the stubbed files each undefined-imports audit run records, compared with the stubs
# calibrate.sh stub writes (lib/stub.sh), then the rules. Problems on stdout, warnings too, prefixed with $WARN.
# STUB_RUNS: per accepted audit run, NUL-separated groups of four: seq, how (file, old: no audit.files,
# bad: a record of another shape), and for each file its path and sha256.
STUB_RUNS='
  .runs[] | select(type == "object" and .accepted != false and (.audit | type) == "object"
                   and .audit.kind == "undefined-imports" and (.seq | type) == "number")
  | (.seq | floor | tostring) as $s
  # A seq that is not a whole number would be compared floored with the rules, which read it as is.
  | if .seq != (.seq | floor) then [$s, "bad", "", ""]
    elif (.audit | has("files")) | not then [$s, "old", "", ""]
    elif (.audit.files | type) == "array" and (.audit.files | length) > 0
         and all(.audit.files[]; type == "object" and (.path | type) == "string" and (.path | length) > 0
                 and (.path | explode | all(. != 0)) and (.sha256 | type) == "string" and (.sha256 | test("^[0-9a-f]{64}$")))
    then (.audit.files[] | [$s, "file", .path, .sha256])
    else [$s, "bad", "", ""] end
  | map(. + "\u0000") | add'
stub_sums=""
for k in esm cjs guarded py; do stub_sums="$stub_sums $k:$(vetdd_stub_text "$k" | vetdd_sha256 /dev/stdin) "; done
check_audit() {
  local slice="$1" meta="$2" seq how path sum k ok bad="" old="" out
  if ! jq -e "[$STUB_RUNS] | length >= 0" "$meta" >/dev/null 2>&1; then
    echo "10: could not evaluate the undefined-imports audit (a run's audit record or the audits log is malformed)"; return
  fi
  while IFS= read -r -d '' seq && IFS= read -r -d '' how && IFS= read -r -d '' path && IFS= read -r -d '' sum; do
    case "$how" in
      old) old="$old $seq"; continue ;;
      bad) bad="$bad $seq"; continue ;;
    esac
    ok=0
    for k in $(vetdd_stub_kinds "$path"); do
      case "$stub_sums" in *" $k:$sum "*) ok=1 ;; esac
    done
    [ "$ok" -eq 1 ] || bad="$bad $seq"
  done < <(jq -j "$STUB_RUNS" "$meta" 2>/dev/null)
  if ! out="$(jq -r --arg slice "$slice" \
       --argjson bad "$(jq -cn --arg l "$bad" '$l | split(" ") | map(select(. != "") | tonumber) | unique')" \
       --argjson old "$(jq -cn --arg l "$old" '$l | split(" ") | map(select(. != "") | tonumber) | unique')" \
       "$AUDIT_RULES" "$meta" 2>/dev/null)"; then
    echo "10: could not evaluate the undefined-imports audit (a run's audit record or the audits log is malformed)"; return
  fi
  [ -n "$out" ] || return 0
  # A warning line is made by the rules alone (run numbers and fixed words), never from recorded text.
  printf '%s\n' "$out" | grep -v '^WARN:' || true
  printf '%s\n' "$out" | sed -n 's/^WARN://p' | while IFS= read -r l; do printf '%s%s\n' "$WARN" "$l"; done
}

# Rule 12: the copy of each planted patch, named from the run's seq, never from a path in the record.
check_planted() {
  local slice="$1" meta="$2" list seq sum how rel tab
  tab="$(printf '\t')"
  list="$(jq -r "$PLANTED_RUNS" "$meta" 2>/dev/null)" \
    || { echo "12: could not evaluate the planted records (a run record is malformed)"; return; }
  [ -n "$list" ] || return 0
  while IFS="$tab" read -r seq sum how; do
    if [ "$seq" = "?" ]; then echo "12: a run that records a planted patch has a malformed seq"; continue; fi
    if [ "$how" != ok ]; then
      echo "12: run $seq records a planted patch that is not what calibrate.sh planted writes (a calibration run with planted: {patch: runs/<seq>-planted.patch, sha256, files}); take the red again with calibrate.sh plant and planted"
      continue
    fi
    rel=".vetdd/evidence/$slice/runs/$(printf '%03d' "$seq")-planted.patch"
    if ! vetdd_inside_repo "$root" "$rel" || [ ! -f "$root/$rel" ] || [ "$(vetdd_sha256 "$root/$rel")" != "$sum" ]; then
      echo "12: the planted patch of calibration run $seq is missing or does not match the sha256 recorded for it (or is a link); take the red again with calibrate.sh plant and planted"
    fi
  done <<< "$list"
}

# Rule 11: one handover per stall in the record, each with every heading.
check_stall() {
  local slice="$1" meta="$2" dir="$evidence_dir/$1" n have=0 f h miss n_
  n="$(jq -r "$VETDD_STALL_JQ"' stall_walk(2) | .stalls' "$meta" 2>/dev/null)" \
    || { echo "11: could not evaluate the stall record (a run record is malformed)"; return; }
  # handover.sh names them handover-1.md, handover-2.md, ...: another name (a draft) is not a handover.
  # The digits are spelled out: bash 3.2 matches a range such as [1-9] by the locale's collation (#50).
  for f in "$dir"/handover-[123456789]*.md; do
    n_="${f##*/handover-}"; n_="${n_%.md}"
    case "$n_" in *[!0123456789]*) continue ;; esac
    if [ -L "$f" ]; then echo "11: ${f##*/} is a link"; continue; fi
    [ -f "$f" ] || continue
    have=$((have + 1)); miss=""
    while IFS= read -r h; do tr -d '\r' < "$f" | grep -qxF -- "$h" || miss="$miss ${h#\#\# };"; done <<EOF_H
$VETDD_HANDOVER_HEADINGS
EOF_H
    [ -z "$miss" ] || echo "11: ${f##*/} lacks the heading(s):$miss"
  done
  [ "$n" -le "$have" ] \
    || echo "${WARN}11: the record holds $n stalls and $have handover(s); write one per stall with handover.sh before redesigning (references/stall.md)"
}

# Rule 10c: problems on stdout, its warnings too, prefixed with $WARN. The mutated files
# are hashed here: each must still hold the source the report mutated.
check_mutation() {
  local slice="$1" meta="$2" out path sum seq rel tr
  if ! out="$(jq -c --arg slice "$slice" --argjson before_close "$before_close" --arg jsts_re "$VETDD_JS_TS_RE" "$MUTATION_RULES" "$meta" 2>/dev/null)" \
     || ! printf '%s' "$out" | jq -e '(.problems | type) == "array" and (.warns | type) == "array" and (.files | type) == "array"' >/dev/null 2>&1; then
    echo "10c: could not evaluate the mutation audit (a run's audit record or the audits log is malformed)"
    return
  fi
  printf '%s' "$out" | jq -r '.problems[]'
  printf '%s' "$out" | jq -r --arg w "$WARN" '.warns[] | $w + .'
  # The copy the judge reads: named from the run number evidence.sh wrote, never from a path in the record.
  if seq="$(printf '%s' "$out" | jq -r '.copy.seq // empty')" && [ -n "$seq" ]; then
    rel=".vetdd/evidence/$slice/runs/$(printf '%03d' "$seq")-mutation.json"
    if ! vetdd_inside_repo "$root" "$rel" || [ ! -f "$root/$rel" ] \
       || [ "$(vetdd_sha256 "$root/$rel")" != "$(printf '%s' "$out" | jq -r '.copy.sha256')" ]; then
      echo "10c: the copy of mutation run $seq's report is missing or does not match the sha256 recorded for it (or is a link); run the mutation audit again"
    else
      # The command runner is the one known to judge vitest 5 correctly (#20): any other runner is a warning.
      # A name of another shape (a new line would end the warning line early) is shown as ?.
      tr="$(jq -r '.config.testRunner // "" | if type == "string" and (. == "" or (test("^[A-Za-z0-9._-]+$") and (contains("\n") | not))) then . else "?" end' "$root/$rel" 2>/dev/null)" || tr="?"
      if [ -z "$tr" ] && jq -e '(.config.command // null) == null' "$root/$rel" >/dev/null 2>&1; then
        # A copy from before testRunner was kept, with no command: not the command runner, or unknown.
        printf '%s\n' "${WARN}10c: mutation run $seq does not say which Stryker runner it used (its report names no runner and no command), so it may be the vitest runner that reported killable mutants as Survived (vetdd #20); run the mutation audit again"
      elif [ -n "$tr" ] && [ "$tr" != command ]; then
        printf '%s\n' "${WARN}10c: mutation run $seq ran Stryker's $tr runner, not the command runner; Stryker's vitest runner reported killable mutants as Survived with vitest 5 (vetdd #20), so read its survivors before trusting them"
      fi
      # A source with a control or a bidirectional control (Trojan Source) reads otherwise to the judge than
      # to the toolchain; emoji joiners and variation selectors are not warned about.
      if ! jq -e "$VETDD_JQ_CLEAN"' all(.files[]?.source; type != "string" or cleantext)' "$root/$rel" >/dev/null 2>&1; then
        printf '%s\n' "${WARN}10c: mutation run $seq mutated a file whose source holds a bidirectional or other control character; it may read otherwise than it runs, so look at that file's bytes"
      fi
      # The tests that faced the mutants are the slice's own (#16): a mutant another test kills is not the slice's.
      case "$(jq -r --arg root "$root" --argjson o "$(printf '%s' "$out" | jq -c '.copy.oracle // []')" "$COMMAND_FILTERS" "$root/$rel" 2>/dev/null || echo error)" in
        ok|skip) ;;
        unread) printf '%s\n' "${WARN}10c: mutation run $seq ran a vitest command that 10c cannot read (an option, double quotes, a non-ASCII, // or .. path, or other shell syntax), so it did not check that only the slice's own test files faced the mutants; the judge reads the command in the copy" ;;
        none) echo "10c: mutation run $seq ran its mutants against every test file (its vitest run command names no test file), so a mutant another test kills counts for the slice; set VETDD_MUTATION_TESTS to the slice's own test files and run the mutation audit again" ;;
        other) echo "10c: mutation run $seq ran its mutants against test files outside the slice's oracle files (a file filter of its vitest run command is not the end of an oracle file path), so a mutant another test kills counts for the slice; set VETDD_MUTATION_TESTS to the slice's own test files and run the mutation audit again" ;;
        *) echo "10c: could not read which tests mutation run $seq ran against its mutants (its copy is malformed); run the mutation audit again" ;;
      esac
    fi
  fi
  # NUL-separated: a path is read exactly as recorded, backslashes and all.
  while IFS= read -r -d '' path && IFS= read -r -d '' sum && IFS= read -r -d '' seq && IFS= read -r -d '' shown; do
    if [ -z "$path" ] || ! vetdd_inside_repo "$root" "$path" || [ ! -f "$root/$path" ] || [ "$(vetdd_sha256 "$root/$path")" != "$sum" ]; then
      [ -z "$path" ] && shown="<an empty path>"
      echo "10c: ${shown:-<a recorded path not shown: it holds a bidirectional or invisible character, or is over 256 characters>} changed since mutation run $seq (or is missing, a link, or outside the repository); run the mutation audit again on the delivered file"
    fi
  done < <(printf '%s' "$out" | jq -j '.files[] | .path, "\u0000", .sha256, "\u0000", (.seq | tostring), "\u0000", .shown, "\u0000"')
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
      vetdd_is_js_ts "$path" || continue
      vetdd_inside_repo "$root" "$path" && [ -f "$root/$path" ] || continue
      # A scanner that fails prints nothing; that must fail the slice, never read as OK.
      found="$(focused_lines "$root/$path")" || { echo "9a: could not scan oracle file $path"; continue; }
      printf '%s\n' "$found" | while IFS= read -r n; do
        case "$n" in
          '') ;;
          '!'*) echo "9a: oracle file $path line ${n#!} is over 20000 characters and its code, or the code just before it, holds the text only or fdescribe, or a slash that opens a regular expression it never closes, so it was not scanned for a focused test; split the line" ;;
          '+'*) echo "9a: oracle file $path line ${n#+} is over 1000000 characters, too long to read, so it was not scanned for a focused test; split the line" ;;
          '?') echo "9a: oracle file $path could not be scanned to the end (a comment or template literal is still open there, or a regular expression was read as one); fix it or split the file" ;;
          *) echo "9a: oracle file $path line $n holds a focused test (.only or fdescribe); it runs only that test and skips the rest, so the green means less than it says. Remove it and record the slice again with a bumped --oracle-version (rule 8)" ;;
        esac
      done
    done
}

# Rules 9b (problems, on stdout) and 9c (warnings, on stdout prefixed with $WARN).
# The oracle version the final green rests on (the last accepted green run, or else the last accepted
# run), as JSON; and one marker per accepted run, so a command whose latest run has no report is known.
FINAL_VERSION='
  [.runs[] | select(.accepted != false)] as $a
  | (([$a[] | select((.kind == "after" or .kind == "integrated") and .outcome == "pass")] | last) // ($a | last)) | .oracle.version | tojson'
RUN_MARKS='.runs[] | select(.accepted != false and (.seq | type) == "number" and .audit == null) | {m: true, seq, cmd, ov: .oracle.version, kind}'

check_test_reports() {
  local slice="$1" meta="$2" list seq kind sum cmd ov rel copy stream="" marks fv tab line splits="[]"
  tab="$(printf '\t')"
  if ! fv="$(jq -r "$FINAL_VERSION" "$meta" 2>/dev/null)" || ! marks="$(jq -c "$RUN_MARKS" "$meta" 2>/dev/null)"; then
    echo "9b: could not evaluate the runs of the oracle version the final green rests on (a run record is malformed)"
    return
  fi
  if ! list="$(jq -r --argjson fv "$fv" "$REPORT_RUNS" "$meta" 2>/dev/null)"; then
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
      splits="$(printf '%s\n%s\n' "$stream" "$marks" | jq -c -s --argjson fv "$fv" "$SKIP_SPLIT" 2>/dev/null)" \
        || { echo "9c: could not compare the skipped and todo tests with the first run of each command"; splits="[]"; }
    fi
  fi
  if line="$(jq -r --argjson fv "$fv" --argjson splits "$splits" "$TEST_WARN_RULES" "$meta" 2>/dev/null)"; then
    [ -z "$line" ] || printf '%s\n' "$line" | while IFS= read -r l; do printf '%s%s\n' "$WARN" "$l"; done
  else
    echo "9c: could not evaluate the skipped and todo counts (a run's tests record is malformed)"
  fi
}

# The mark of an abandoned slice (worktree.sh abandon): "<cause>[, replaced by <id>]" on stdout, or a
# return of 1 when it is not what worktree.sh abandon writes (a link, not a regular file, not that JSON).
abandoned_mark() {
  local rel=".vetdd/evidence/$1/abandoned"
  vetdd_inside_repo "$root" "$rel" && [ -f "$root/$rel" ] && [ ! -L "$root/$rel" ] || return 1
  jq -r -s --arg slice "$1" "$VETDD_ABANDONED_JQ" "$root/$rel" 2>/dev/null
}

# An abandoned slice is not delivered: only rule 11 is asked, and only of a stall (its handovers are the
# record of the redesign).
check_abandoned() {
  local slice="$1" meta="$evidence_dir/$1/meta.json"
  # worktree.sh abandon marks only a slice with evidence: a mark alone was not written by it.
  [ -f "$meta" ] && [ ! -L "$meta" ] || { echo "schema: no meta.json for this slice (worktree.sh abandon marks only a slice with evidence)"; return; }
  case "$2" in stall|"stall, "*) ;; *) return 0 ;; esac
  check_stall "$slice" "$meta"
}

failed=0
for slice in "${slices[@]}"; do
  # A name that is not a slice id (a stray directory, possibly holding control characters or
  # newlines) is never printed as given.
  if vetdd_is_slice_id "$slice"; then shown="$slice"; else shown="<invalid slice name>"; fi
  mark=""
  if vetdd_is_slice_id "$slice" && vetdd_abandoned "$root" "$slice"; then
    if mark="$(abandoned_mark "$slice")" && [ -n "$mark" ]; then
      out="$(check_abandoned "$slice" "$mark")"
    else
      mark=""
      out="abandoned: .vetdd/evidence/$slice/abandoned is not a mark worktree.sh abandon writes (a regular file holding one JSON object: cause stall, conflict, or lost, recorded_at a UTC time, and an optional replaced_by naming another slice); remove it and mark the slice again with worktree.sh abandon"
    fi
  else
    out="$(check_slice "$slice")"
  fi
  # Pass or fail is decided on the raw problems (every line not marked a warning); the display filter
  # only shapes what is shown.
  problems="$(printf '%s\n' "$out" | LC_ALL=C grep -v "^$WARN")"
  warns="$(printf '%s\n' "$out" | LC_ALL=C sed -n "s/^$WARN//p")"
  [ -z "$mark" ] || echo "$shown: ABANDONED ($mark)"
  if [ -z "$problems" ]; then
    [ -n "$mark" ] || echo "$shown: OK"
  else
    failed=$((failed + 1))
    # Recorded values (versions, paths) reach the terminal: strip control characters.
    shown_problems="$(printf '%s\n' "$problems" | vetdd_printable)"
    [ -n "$shown_problems" ] || shown_problems="a problem that could not be displayed"
    printf '%s\n' "$shown_problems" | while IFS= read -r line; do echo "$shown: FAIL ($line)"; done
  fi
  # Warnings never change the exit code. The display filter runs on them too.
  if [ -n "$warns" ]; then
    printf '%s\n' "$warns" | vetdd_printable | while IFS= read -r line; do [ -z "$line" ] || echo "$shown: WARN ($line)"; done
  fi
done
[ "$failed" -le 125 ] || failed=125
exit "$failed"
