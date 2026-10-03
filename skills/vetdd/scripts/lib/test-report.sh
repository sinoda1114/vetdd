# Test runner reports for evidence.sh --test-report (bash 3.2 compatible; needs jq and common.sh).
# Format jest-json: the JSON reporter output of jest and vitest (vitest: --reporter=json
# --outputFile.json=<path>). Counts come from testResults[].assertionResults[].status.

# vetdd_report_rel <root> <prefix> <path>: print <path> (relative to the directory <prefix> under
# <root>, or absolute under <root>) relative to <root>; fail when it leaves the repository.
vetdd_report_rel() {
  local root="$1" prefix="$2" p="$3"
  case "$p" in
    "$root"/*) p="${p#"$root"/}" ;;
    /*) return 1 ;;
    *) while :; do case "$p" in ./*) p="${p#./}" ;; *) break ;; esac; done; p="$prefix$p" ;;
  esac
  vetdd_inside_repo "$root" "$p" || return 1
  printf '%s\n' "$p"
}

# vetdd_report_allowed <root> <rel>: true when deleting and writing the report cannot change the
# tree that check-evidence rule 5 hashes, nor the evidence: under .vetdd/ (not .vetdd/evidence/)
# or a git-ignored, untracked path, and not a directory.
vetdd_report_allowed() {
  local root="$1" rel="$2" parent phys
  [ ! -d "$root/$rel" ] || return 1
  # The physical directory, so a link into the evidence is caught; letter case folded for
  # case-insensitive file systems.
  parent="$(dirname -- "$root/$rel")"
  phys="$parent"
  if [ -d "$parent" ]; then phys="$(CDPATH='' cd -P -- "$parent" && pwd -P)" || return 1; fi
  case "$(printf '%s/' "$phys" | tr 'A-Z' 'a-z')" in
    "$(printf '%s' "$root/.vetdd/evidence/" | tr 'A-Z' 'a-z')"*) return 1 ;;
  esac
  case "$(printf '%s' "$rel" | tr 'A-Z' 'a-z')" in .vetdd/evidence/*) return 1 ;; esac
  case "$rel" in .vetdd/*) return 0 ;; esac
  git -C "$root" check-ignore -q -- "$rel" 2>/dev/null
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
  elif [ ! -f "$root/$rel" ]; then status=missing
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
  jq --arg sum "$sum" '{format, status: "ok", passed, failed, skipped, todo, other, total, sha256: $sum}' "$copy"
}
