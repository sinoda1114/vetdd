# Mutation testing reports for evidence.sh --mutation-report (bash 3.2 compatible; needs jq,
# common.sh, tree-hash.sh). Format stryker-json: the JSON reporter output of StrykerJS
# (mutation-testing-report-schema 1.x): files[<path relative to projectRoot>] = {source, mutants[]}.

# jq: a stryker-json report -> {projectRoot, keys, counts}. Errors (status invalid) when the shape is
# not schema 1.x, projectRoot is not absolute, a file key is not a plain relative path (no empty, . or
# .. component, no control character), or a mutant has a status outside the final ones (Pending means
# the run did not finish).
VETDD_STRYKER_JSON='
  def final: . as $s | any(["Killed","Survived","NoCoverage","Timeout","CompileError","RuntimeError","Ignored"][]; . == $s);
  def printable: explode | all(. > 31 and (. < 127 or . > 159));
  def int: type == "number" and . == floor and . >= 0;
  def pos: type == "object" and (.line | int) and (.column | int);
  # Every field the copy keeps has the type Stryker writes, so nothing free-form reaches the judge.
  def mutant: type == "object" and (.status | type) == "string" and (.status | final)
    and (.id | type) == "string" and (.id | printable) and (.mutatorName | type) == "string"
    and (.mutatorName | test("^[A-Za-z]+$"))
    and ((has("replacement") | not) or ((.replacement | type) == "string"))
    and (.location | type) == "object" and (.location.start | pos) and (.location.end | pos);
  def plain: . != "" and (explode | all(. > 31 and (. < 127 or . > 159))) and (split("/") | all(. != "" and . != "." and . != ".."));
  if type == "object" and (.schemaVersion | type) == "string" and (.schemaVersion | test("^1(\\.|$)"))
     and (.projectRoot | type) == "string" and (.projectRoot | startswith("/"))
     and (.files | type) == "object" and (.files | length) > 0
     and all(.files | keys[]; plain)
     and ((.config.mutate // null) == null
          or ((.config.mutate | type) == "array" and all(.config.mutate[]; type == "string" and printable)))
     and all(.files[]; type == "object" and (.source | type) == "string" and (.mutants | type) == "array"
       and all(.mutants[]; mutant))
  then . else error("not a stryker-json report") end
  | [.files[].mutants[].status] as $st
  | def n($s): [$st[] | select(. == $s)] | length;
  {projectRoot, keys: (.files | keys),
   counts: {killed: n("Killed"), survived: n("Survived"), no_coverage: n("NoCoverage"), timeout: n("Timeout"),
            compile_error: n("CompileError"), runtime_error: n("RuntimeError"), ignored: n("Ignored"),
            total: ($st | length)}}'

# jq: the copy kept for the judge: the line ranges asked for (config.mutate), and per file its source and
# each mutant's id, mutator, replacement, status, and location. Any other field of the raw report (the
# rest of the config, free text a tool or a person added) is left out.
VETDD_STRYKER_COPY='
  {schemaVersion, config: {mutate: (.config.mutate // null)},
   files: (.files | map_values({source, mutants: [.mutants[] | {id, mutatorName, replacement, status,
     location: {start: {line: .location.start.line, column: .location.start.column},
                end: {line: .location.end.line, column: .location.end.column}}}]}))}'

# vetdd_mutation_files <root> <report> <projectRoot> <keys...>: print [{path, sha256}] with each path
# relative to <root> in its on-disk spelling and the sha256 of the source the report mutated; fail
# when projectRoot or a path leaves the repository.
vetdd_mutation_files() {
  local root="$1" report="$2" pr="$3" key p prel src sum out=""; shift 3
  [ -d "$pr" ] || return 1
  pr="$(CDPATH='' cd -P -- "$pr" 2>/dev/null && pwd -P)" || return 1
  case "$pr" in "$root") prel="" ;; "$root"/*) prel="${pr#"$root"/}/" ;; *) return 1 ;; esac
  src="$(mktemp "${TMPDIR:-/tmp}/vetdd-source.XXXXXX")" || return 1
  for key in "$@"; do
    p="$(vetdd_disk_path "$root" "$prel$key")"
    if ! vetdd_inside_repo "$root" "$p" \
       || ! jq -j --arg k "$key" '.files[$k].source' "$report" > "$src" 2>/dev/null \
       || ! sum="$(vetdd_sha256 "$src")"; then
      rm -f -- "$src"; return 1
    fi
    out="$out$(jq -n --arg p "$p" --arg s "$sum" '{path: $p, sha256: $s}')"
  done
  rm -f -- "$src"
  # Two keys that name one file (another letter case on a case-insensitive file system) leave no
  # single hash for it.
  printf '%s' "$out" | jq -s 'if (map(.path) | unique | length) == length then . else error("one file twice") end'
}

# vetdd_mutation_report_import <root> <rel> <copy> <copy-rel>: print the run's audit.report object.
# The report is read once, into a private temp file beside <copy>; the checks, the counts, the file
# hashes, and the normalized copy all come from that one read, so a report rewritten meanwhile cannot
# make the record and the copy disagree. The copy is renamed into place, never written through a link.
# When the report is missing or not usable, status is missing or invalid, with a warning on stderr.
vetdd_mutation_report_import() {
  local root="$1" rel="$2" copy="$3" copy_rel="$4" status="" summary files sum k keys=() raw="" norm=""
  rm -f -- "$copy" 2>/dev/null
  # Checked again here: the command that just ran could have swapped the report for a link.
  # Something left at the copy's name that rm cannot remove (a directory) would take the copy inside it.
  if [ -e "$copy" ] || [ -L "$copy" ]; then status=invalid
  elif ! vetdd_inside_repo "$root" "$rel" || [ -d "$root/$rel" ]; then status=invalid
  elif [ ! -e "$root/$rel" ]; then status=missing
  elif [ ! -f "$root/$rel" ]; then status=invalid
  elif ! raw="$(mktemp "$(dirname -- "$copy")/.mutation.XXXXXX")" || ! norm="$(mktemp "$(dirname -- "$copy")/.mutation.XXXXXX")"; then status=invalid
  elif [ -L "$root/$rel" ] || ! cat -- "$root/$rel" > "$raw" 2>/dev/null; then status=invalid
  elif ! jq -e -s 'length == 1 and (.[0] | type) == "object"' "$raw" >/dev/null 2>&1; then status=invalid
  elif ! summary="$(jq -c "$VETDD_STRYKER_JSON" "$raw" 2>/dev/null)"; then status=invalid
  else
    while IFS= read -r -d '' k; do keys+=("$k"); done < <(printf '%s' "$summary" | jq -j '.keys[] | ., "\u0000"')
    if ! files="$(vetdd_mutation_files "$root" "$raw" "$(printf '%s' "$summary" | jq -r '.projectRoot')" "${keys[@]}")"; then
      status=invalid
    elif ! jq "$VETDD_STRYKER_COPY" "$raw" > "$norm" 2>/dev/null || ! sum="$(vetdd_sha256 "$norm")" \
         || ! chmod "$(vetdd_file_mode)" "$norm" || ! mv -f -- "$norm" "$copy"; then
      status=invalid
    fi
  fi
  # Stryker writes "files": {} when the --mutate ranges held no mutant at all: say so, it is not a broken run.
  if [ "$status" = invalid ] && [ -n "$raw" ] && [ -f "$raw" ] && jq -e '.files == {}' "$raw" >/dev/null 2>&1; then
    printf 'evidence.sh: warning: mutation report %s mutated nothing: the --mutate ranges held no mutant (an emptied function body needs the range to reach its closing brace)\n' "$rel" | vetdd_printable >&2
  fi
  [ -z "$raw" ] || rm -f -- "$raw"
  [ -z "$norm" ] || rm -f -- "$norm"
  if [ -n "$status" ]; then
    rm -f -- "$copy" 2>/dev/null
    printf 'evidence.sh: warning: mutation report %s is %s; recorded audit.report.status=%s (the outcome still comes from the exit code)\n' \
      "$rel" "$status" "$status" | vetdd_printable >&2
    jq -n --arg p "$rel" --arg s "$status" '{format: "stryker-json", path: $p, status: $s}'
    return 0
  fi
  printf '%s' "$summary" | jq --arg p "$rel" --arg sum "$sum" --arg c "$copy_rel" --argjson files "$files" \
    '{format: "stryker-json", path: $p, status: "ok", sha256: $sum, copy: $c, counts, files: $files}' \
    || { rm -f -- "$copy"; return 1; }
}
