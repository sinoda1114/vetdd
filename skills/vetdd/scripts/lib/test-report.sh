# Test runner reports for evidence.sh --test-report (bash 3.2 compatible; needs jq and common.sh).
# Format jest-json: the JSON reporter output of jest and vitest (vitest: --reporter=json
# --outputFile.json=<path>). Counts come from testResults[].assertionResults[].status.

# vetdd_report_rel <root> <path>: print where <path> (relative to the current directory, or
# absolute) really is, relative to <root> and spelled as on disk; fail when it leaves the repository.
# The deepest existing directory is resolved physically (symlinks and .. included), since the
# report's own directory may not exist yet; the rest is kept as written.
vetdd_report_rel() {
  local root="$1" p="$2" d tail
  # A report is a file: a path ending in /, /. or /.. would lose or change its last component.
  case "$p" in ''|*/|*/.|*/..|.|..) return 1 ;; esac
  case "$p" in /*) ;; *) p="$(pwd -P)/$p" ;; esac
  d="$(dirname -- "$p")"; tail=""
  while [ ! -d "$d" ] && [ "$d" != / ]; do tail="/${d##*/}$tail"; d="$(dirname -- "$d")"; done
  d="$(CDPATH='' cd -P -- "$d" && pwd -P)" || return 1
  p="${d%/}$tail/${p##*/}"
  case "$p" in "$root"/*) p="${p#"$root"/}" ;; *) return 1 ;; esac
  # One spelling per path: no doubled slash, and every component as it is on disk, so another
  # letter case on a case-insensitive file system names the file git and the checks below see.
  p="$(printf '%s' "$p" | sed 's#//*#/#g')"
  vetdd_inside_repo "$root" "$p" || return 1
  vetdd_disk_path "$root" "$p"
}

# vetdd_report_allowed <root> <rel>: true when deleting and writing the report cannot touch
# anything but an earlier report: <rel> (as vetdd_report_rel prints it) is a file directly or
# deeper under .vetdd/reports/, not a directory, not a symbolic link, and not tracked by git.
vetdd_report_allowed() {
  local root="$1" rel="$2"
  [ ! -d "$root/$rel" ] && [ ! -L "$root/$rel" ] || return 1
  # Exactly .vetdd/reports/: rel is already in its on-disk spelling, and only .vetdd is left out
  # of the tree hash and ignored, in that spelling.
  case "$rel" in .vetdd/reports/?*) ;; *) return 1 ;; esac
  # Allowed only when git says "not tracked" (1); tracked (0) or a git failure is a refusal.
  local rc=0
  git -C "$root" ls-files --error-unmatch -- ":(literal,icase)$rel" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ]
}

# jq: a jest-json report -> {format, passed, failed, skipped, todo, other, total, tests: [...]}.
# Errors (and so status invalid) when the shape is not jest-json or numTotalTests disagrees.
VETDD_JEST_JSON='
  def bucket: if . == "passed" or . == "failed" or . == "todo" then .
    elif . == "skipped" or . == "pending" or . == "disabled" then "skipped" else "other" end;
  def n($b): map(select(.bucket == $b)) | length;
  if type == "object" and (.testResults | type) == "array"
     and all(.testResults[]; type == "object" and (.assertionResults | type) == "array"
       and all(.assertionResults[]; type == "object" and (.status | type) == "string"))
  then . else error("not jest-json") end
  | .numTotalTests as $declared
  | [.testResults[] | ((.name // "") | tostring | ltrimstr($root + "/")) as $f
     | .assertionResults[] | {file: $f, name: ((.fullName // .title // "") | tostring), status,
                              bucket: (.status | bucket)}] as $t
  | if ($declared | type) == "number" and $declared != ($t | length) then error("numTotalTests disagrees") else . end
  | {format: "jest-json", passed: ($t | n("passed")), failed: ($t | n("failed")),
     skipped: ($t | n("skipped")), todo: ($t | n("todo")), other: ($t | n("other")),
     total: ($t | length), tests: [$t[] | del(.bucket)]}'

# vetdd_test_report_import <root> <rel> <copy>: print the run's `tests` object. When the report is
# a regular file inside the repository and valid jest-json, its normalized form is written to <copy>
# and hashed; otherwise status is missing or invalid, with a warning on stderr.
vetdd_test_report_import() {
  local root="$1" rel="$2" copy="$3" status="" sum
  rm -f -- "$copy"
  # Checked again here: the command that just ran could have swapped the report for a link.
  if ! vetdd_inside_repo "$root" "$rel" || [ -d "$root/$rel" ]; then status=invalid
  elif [ ! -e "$root/$rel" ]; then status=missing
  # Something is there but not a regular file (a FIFO, a socket): never read it.
  elif [ ! -f "$root/$rel" ]; then status=invalid
  # Exactly one JSON object: an empty file or two concatenated reports would print no value or two.
  elif ! jq -e -s 'length == 1 and (.[0] | type) == "object"' "$root/$rel" >/dev/null 2>&1; then status=invalid
  elif ! jq --arg root "$root" "$VETDD_JEST_JSON" "$root/$rel" > "$copy" 2>/dev/null; then status=invalid
  elif ! sum="$(vetdd_sha256 "$copy")"; then status=invalid
  fi
  if [ -n "$status" ]; then
    rm -f -- "$copy"
    printf 'evidence.sh: warning: test report %s is %s; recorded tests.status=%s (the outcome still comes from the exit code)\n' \
      "$rel" "$status" "$status" | vetdd_printable >&2
    jq -n --arg s "$status" '{format: "jest-json", status: $s}'
    return 0
  fi
  jq --arg sum "$sum" '{format, status: "ok", passed, failed, skipped, todo, other, total, sha256: $sum}' "$copy" \
    || { rm -f -- "$copy"; return 1; }
}
