# Mutation testing reports for evidence.sh --mutation-report (bash 3.2 compatible; needs jq,
# common.sh, tree-hash.sh). Format stryker-json: the JSON reporter output of StrykerJS
# (mutation-testing-report-schema 1.x): files[<path relative to projectRoot>] = {source, mutants[]}.

# jq: a stryker-json report -> {projectRoot, keys, counts}. Errors (status invalid) when the shape is
# not schema 1.x, a mutant has a status outside the final ones (Pending means the run did not finish),
# or a file key holds a control character.
VETDD_STRYKER_JSON='
  def final: . as $s | any(["Killed","Survived","NoCoverage","Timeout","CompileError","RuntimeError","Ignored"][]; . == $s);
  if type == "object" and (.schemaVersion | type) == "string" and (.schemaVersion | test("^1(\\.|$)"))
     and (.projectRoot | type) == "string" and (.files | type) == "object" and (.files | length) > 0
     and all(.files | keys[]; explode | all(. > 31 and (. < 127 or . > 159)))
     and all(.files[]; type == "object" and (.source | type) == "string" and (.mutants | type) == "array"
       and all(.mutants[]; type == "object" and (.status | type) == "string" and (.status | final)))
  then . else error("not a stryker-json report") end
  | [.files[].mutants[].status] as $st
  | def n($s): [$st[] | select(. == $s)] | length;
  {projectRoot, keys: (.files | keys),
   counts: {killed: n("Killed"), survived: n("Survived"), no_coverage: n("NoCoverage"), timeout: n("Timeout"),
            compile_error: n("CompileError"), runtime_error: n("RuntimeError"), ignored: n("Ignored"),
            total: ($st | length)}}'

# vetdd_mutation_files <root> <report> <projectRoot> <keys...>: print [{path, sha256}] with each path
# relative to <root> and the sha256 of the source the report mutated; fail when projectRoot or a path
# leaves the repository.
vetdd_mutation_files() {
  local root="$1" report="$2" pr="$3" key p prel src sum out=""; shift 3
  [ -d "$pr" ] || return 1
  pr="$(CDPATH='' cd -P -- "$pr" 2>/dev/null && pwd -P)" || return 1
  case "$pr" in "$root") prel="" ;; "$root"/*) prel="${pr#"$root"/}/" ;; *) return 1 ;; esac
  src="$(mktemp "${TMPDIR:-/tmp}/vetdd-source.XXXXXX")" || return 1
  for key in "$@"; do
    p="$prel$key"
    if ! vetdd_inside_repo "$root" "$p" \
       || ! jq -j --arg k "$key" '.files[$k].source' "$report" > "$src" 2>/dev/null \
       || ! sum="$(vetdd_sha256 "$src")"; then
      rm -f -- "$src"; return 1
    fi
    out="$out$(jq -n --arg p "$p" --arg s "$sum" '{path: $p, sha256: $s}')"
  done
  rm -f -- "$src"
  printf '%s' "$out" | jq -s '.'
}

# vetdd_mutation_report_import <root> <rel> <copy> <copy-rel>: print the run's audit.report object.
# When the report is a regular file inside the repository and a usable stryker-json report, it is
# copied byte for byte to <copy> (the judge reads config.mutate and each mutant there) and hashed;
# otherwise status is missing or invalid, with a warning on stderr.
vetdd_mutation_report_import() {
  local root="$1" rel="$2" copy="$3" copy_rel="$4" status="" summary files sum k keys=()
  rm -f -- "$copy"
  # Checked again here: the command that just ran could have swapped the report for a link.
  if ! vetdd_inside_repo "$root" "$rel" || [ -d "$root/$rel" ]; then status=invalid
  elif [ ! -e "$root/$rel" ]; then status=missing
  elif [ ! -f "$root/$rel" ]; then status=invalid
  elif ! jq -e -s 'length == 1 and (.[0] | type) == "object"' "$root/$rel" >/dev/null 2>&1; then status=invalid
  elif ! summary="$(jq -c "$VETDD_STRYKER_JSON" "$root/$rel" 2>/dev/null)"; then status=invalid
  else
    while IFS= read -r -d '' k; do keys+=("$k"); done < <(printf '%s' "$summary" | jq -j '.keys[] | ., "\u0000"')
    if ! files="$(vetdd_mutation_files "$root" "$root/$rel" "$(printf '%s' "$summary" | jq -r '.projectRoot')" "${keys[@]}")"; then
      status=invalid
    elif ! cp -- "$root/$rel" "$copy" || ! sum="$(vetdd_sha256 "$copy")"; then status=invalid
    fi
  fi
  if [ -n "$status" ]; then
    rm -f -- "$copy"
    printf 'evidence.sh: warning: mutation report %s is %s; recorded audit.report.status=%s (the outcome still comes from the exit code)\n' \
      "$rel" "$status" "$status" | vetdd_printable >&2
    jq -n --arg p "$rel" --arg s "$status" '{format: "stryker-json", path: $p, status: $s}'
    return 0
  fi
  printf '%s' "$summary" | jq --arg p "$rel" --arg sum "$sum" --arg c "$copy_rel" --argjson files "$files" \
    '{format: "stryker-json", path: $p, status: "ok", sha256: $sum, copy: $c, counts, files: $files}' \
    || { rm -f -- "$copy"; return 1; }
}
