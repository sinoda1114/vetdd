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
         and .exit_code != 0 and .exit_code != 126 and .exit_code != 127;
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
     then (if ([$acc[] | select((.kind == "before" or .kind == "calibration") and .outcome == "target_failure"
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

current_tree="$(vetdd_tree_hash "$root")" || current_tree=""

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
  local slice="$1" meta="$evidence_dir/$1/meta.json" final_tree path want have
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

failed=0
for slice in "${slices[@]}"; do
  # Pass or fail is decided on the raw problems; the display filter only shapes what is shown.
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
done
[ "$failed" -le 125 ] || failed=125
exit "$failed"
