# Mutation testing reports for evidence.sh --mutation-report (bash 3.2 compatible; needs jq,
# common.sh, tree-hash.sh). Format stryker-json: the JSON reporter output of StrykerJS
# (mutation-testing-report-schema 1.x): files[<path relative to projectRoot>] = {source, mutants[]}.

# The largest report read (64 MiB): a larger one is invalid, so a runaway file is never read whole.
VETDD_MUTATION_REPORT_MAX_BYTES=67108864

# jq: clean is true for a string with no control character (C0, DEL, C1), no bidirectional control
# (U+061C, U+200E, U+200F, U+202A-U+202E, U+2066-U+2069), and no invisible format character (U+200B-U+200D,
# U+2028, U+2029, U+2060-U+2065, U+FEFF), so text that reaches the judge or a terminal reads as it shows.
VETDD_JQ_CLEAN='
  def clean: explode | all(. > 31 and (. < 127 or . > 159) and . != 1564 and (. < 8203 or . > 8207)
    and (. < 8232 or . > 8238) and (. < 8288 or . > 8297) and . != 65279);'

# jq: a stryker-json report -> {projectRoot, keys, counts}. Errors (status invalid) when the shape is
# not schema 1.x, projectRoot is not absolute, a file key is not a plain relative path (no empty, . or
# .. component, no control, bidirectional, or invisible character), or a mutant has a status outside the
# final ones (Pending means the run did not finish). Each check errors with "vetdd: <why>", fixed words
# that evidence.sh prints with its warning; no recorded text goes into them.
VETDD_STRYKER_JSON="$VETDD_JQ_CLEAN"'
  def final: . as $s | any(["Killed","Survived","NoCoverage","Timeout","CompileError","RuntimeError","Ignored"][]; . == $s);
  def int: type == "number" and . == floor and . >= 0;
  def pos: type == "object" and (.line | int) and (.column | int);
  # Every field the copy keeps has the type and form Stryker writes, so nothing free-form reaches the
  # judge: an id is a number (Stryker counts them), a mutator name is letters only.
  def mutant: type == "object" and (.status | type) == "string" and (.status | final)
    and (.id | type) == "string" and (.id | test("^[0-9]{1,20}$")) and (.mutatorName | type) == "string"
    and (.mutatorName | test("^[A-Za-z]+$"))
    and ((has("replacement") | not) or ((.replacement | type) == "string"))
    and (.location | type) == "object" and (.location.start | pos) and (.location.end | pos);
  def plain: type == "string" and . != "" and clean and (split("/") | all(. != "" and . != "." and . != ".."));
  # A --mutate range: <file>:<first line>-<last line>, or with columns (<line>:<column>), the file a plain
  # relative path with none of the characters Stryker reads as a glob or a list (mutate-ranges.sh).
  def range: type == "string" and length <= 4096
    and test("^[^:*?\\[\\]{}()\\\\!,]+:[0-9]+(:[0-9]+)?-[0-9]+(:[0-9]+)?$")
    and (sub(":[0-9]+(:[0-9]+)?-[0-9]+(:[0-9]+)?$"; "") | plain);
  def check(c; why): if c then . else error("vetdd: " + why) end;
  check(type == "object"; "it is not one JSON object")
  | check((.schemaVersion | type) == "string" and (.schemaVersion | test("^1(\\.|$)")); "its schemaVersion is not 1.x")
  | check((.projectRoot | type) == "string" and (.projectRoot | startswith("/")); "its projectRoot is not an absolute path")
  | check((.files | type) == "object" and (.files | length) > 0; "it holds no files object with a file in it")
  | check(all(.files | keys[]; plain); "a file key is not a plain relative path (an empty, . or .. component, or a control, bidirectional, or invisible character)")
  # The command runner must name its command (the tests it ran), clean and at most 4096 characters.
  | check(.config.testRunner != "command"
          or ((.config.commandRunner.command | type) == "string" and (.config.commandRunner.command | length) > 0);
          "the command runner names no command")
  | check(.config.testRunner != "command" or (.config.commandRunner.command | length) <= 4096;
          "the command of the command runner is longer than 4096 characters, the most the record keeps; name fewer or shorter test paths")
  | check(.config.testRunner != "command" or (.config.commandRunner.command | clean);
          "the command of the command runner holds a control, bidirectional, or invisible character")
  # The runner is one of StrykerJS own test runners, by name, so no free text reaches the judge there.
  | (.config.testRunner // null) as $tr
  | check($tr == null or any(["command", "vitest", "jest", "mocha", "jasmine", "karma", "tap", "cucumber"][]; . == $tr);
          "config.testRunner is not one of the StrykerJS test runners (command, vitest, jest, mocha, jasmine, karma, tap, cucumber)")
  | check((.config.mutate // null) == null or ((.config.mutate | type) == "array" and all(.config.mutate[]; range));
          "config.mutate is not a list of <file>:<first line>-<last line> ranges")
  | check(all(.files[]; type == "object" and (.source | type) == "string" and (.mutants | type) == "array");
          "a file has no source text or no list of mutants")
  | check(all(.files[].mutants[]; type == "object" and (.status | type) == "string" and (.status | final));
          "a mutant has a status that is not final (Pending means the run did not finish)")
  | check(all(.files[].mutants[]; mutant);
          "a mutant has no numeric id, letters-only mutator name, or line and column location as Stryker writes them")
  | [.files[].mutants[].status] as $st
  | def n($s): [$st[] | select(. == $s)] | length;
  {projectRoot, keys: (.files | keys),
   counts: {killed: n("Killed"), survived: n("Survived"), no_coverage: n("NoCoverage"), timeout: n("Timeout"),
            compile_error: n("CompileError"), runtime_error: n("RuntimeError"), ignored: n("Ignored"),
            total: ($st | length)}}'

# jq: VETDD_STRYKER_JSON with its failure as data: the summary, or {invalid: <why>} (empty for an error
# that is not one of its fixed reasons, which is never shown).
VETDD_STRYKER_SUMMARY='try ('"$VETDD_STRYKER_JSON"') catch {invalid: (if type == "string" and startswith("vetdd: ") then .[7:] else "" end)}'

# jq: the copy kept for the judge: the line ranges asked for (config.mutate), the command the command
# runner ran against each mutant (config.command: which tests faced them; kept only when testRunner is
# "command", since Stryker writes a default commandRunner.command into every report), the runner itself
# (config.testRunner), and per file its source and
# each mutant's id, mutator, replacement, status, and location. Any other field of the raw report (the
# rest of the config, free text a tool or a person added) is left out.
VETDD_STRYKER_COPY='
  {schemaVersion, config: {mutate: (.config.mutate // null), testRunner: (.config.testRunner // null),
             command: (if .config.testRunner == "command" then (.config.commandRunner.command // null) else null end)},
   files: (.files | map_values({source, mutants: [.mutants[] | {id, mutatorName, replacement, status,
     location: {start: {line: .location.start.line, column: .location.start.column},
                end: {line: .location.end.line, column: .location.end.column}}}]}))}'

# vetdd_mutation_prel <root> <projectRoot>: print the repository path of projectRoot with a slash after
# it ("" for the root itself); fail when it is not a directory inside the repository.
vetdd_mutation_prel() {
  local root="$1" pr="$2"
  [ -d "$pr" ] || return 1
  pr="$(CDPATH='' cd -P -- "$pr" 2>/dev/null && pwd -P)" || return 1
  case "$pr" in "$root") ;; "$root"/*) printf '%s/' "${pr#"$root"/}" ;; *) return 1 ;; esac
}

# vetdd_mutation_files <root> <report> <prefix> <scratch> <keys...>: print [{path, sha256}] with each path
# (<prefix> + key, from vetdd_mutation_prel) relative to <root> in its on-disk spelling and the sha256 of
# the source the report mutated, written to the <scratch> file to be hashed. Exit 2 when a path leaves
# the repository or the report cannot be read, 3 when two keys name one file.
vetdd_mutation_files() {
  local root="$1" report="$2" prel="$3" src="$4" key p sum out=""; shift 4
  for key in "$@"; do
    p="$(vetdd_disk_path "$root" "$prel$key")"
    if ! vetdd_inside_repo "$root" "$p" \
       || ! jq -j --arg k "$key" '.files[$k].source' "$report" > "$src" 2>/dev/null \
       || ! sum="$(vetdd_sha256 "$src")"; then
      return 2
    fi
    out="$out$(jq -n --arg p "$p" --arg s "$sum" '{path: $p, sha256: $s}')"
  done
  # Two keys that name one file (another letter case on a case-insensitive file system) leave no
  # single hash for it.
  printf '%s' "$out" | jq -s 'if (map(.path) | unique | length) == length then . else error("one file twice") end' 2>/dev/null \
    || return 3
}

# vetdd_mutation_report_import <root> <rel> <copy> <copy-rel>: print the run's audit.report object.
# The report is read once, into a private temp file beside <copy>; the checks, the counts, the file
# hashes, and the normalized copy all come from that one read, so a report rewritten meanwhile cannot
# make the record and the copy disagree. The copy is renamed into place, never written through a link,
# and only into a runs directory that is still the repository's own (the command that just ran could
# have swapped it). A report with another hard link, or larger than VETDD_MUTATION_REPORT_MAX_BYTES, is
# not read. The temp files go when a signal cuts the import short.
# When the report is missing or not usable, status is missing or invalid, with a warning on stderr
# that says why in fixed words.
vetdd_mutation_report_import() {
  local root="$1" rel="$2" copy="$3" copy_rel="$4" status="" why="" summary="" files sum k keys=()
  local raw="" norm="" src="" runs prel rc got=0
  runs="$(dirname -- "$copy")"
  trap 'rm -f -- ${raw:+"$raw"} ${norm:+"$norm"} ${src:+"$src"}; exit 1' INT TERM HUP
  # Checked again here: the command that just ran could have swapped runs/ or the report for a link.
  if [ -L "$runs" ] || ! vetdd_inside_repo "$root" "${runs#"$root"/}"; then
    status=invalid; why="the runs directory of the slice is a link or leaves the repository now"
  else
    rm -f -- "$copy" 2>/dev/null
    # Something left at the copy's name that rm cannot remove (a directory) would take the copy inside it.
    if [ -e "$copy" ] || [ -L "$copy" ]; then status=invalid; why="something at $copy_rel cannot be removed"
    elif ! vetdd_inside_repo "$root" "${copy#"$root"/}"; then
      status=invalid; why="the runs directory of the slice is a link or leaves the repository now"
    elif ! vetdd_inside_repo "$root" "$rel" || [ -d "$root/$rel" ]; then
      status=invalid; why="its path is a link, a directory, or leaves the repository now"
    elif [ ! -e "$root/$rel" ]; then status=missing
    elif [ ! -f "$root/$rel" ]; then status=invalid; why="it is not a regular file"
    elif [ -z "$(find "$root/$rel" -prune -type f -links 1 2>/dev/null)" ]; then
      status=invalid; why="it has another hard link, a name of a file elsewhere"
    elif ! raw="$(mktemp "$runs/.mutation.XXXXXX")" || ! norm="$(mktemp "$runs/.mutation.XXXXXX")" \
         || ! src="$(mktemp "$runs/.mutation.XXXXXX")"; then
      status=invalid; why="no temp file could be made in the runs directory"
    # Read once, through a redirection, at most one byte over the limit; the path is checked again after.
    elif ! head -c "$((VETDD_MUTATION_REPORT_MAX_BYTES + 1))" < "$root/$rel" > "$raw" 2>/dev/null \
         || [ -L "$root/$rel" ] || [ ! -f "$root/$rel" ]; then
      status=invalid; why="it could not be read, or became a link while it was read"
    elif [ "$(wc -c < "$raw" | tr -d ' ')" -gt "$VETDD_MUTATION_REPORT_MAX_BYTES" ]; then
      status=invalid; why="it is larger than 64 MiB"
    else
      got=1
      if ! jq -e -s 'length == 1 and (.[0] | type) == "object"' "$raw" >/dev/null 2>&1; then
        status=invalid; why="it is not one JSON object"
      elif ! summary="$(jq -c "$VETDD_STRYKER_SUMMARY" "$raw" 2>/dev/null)" || [ -z "$summary" ]; then
        status=invalid
      elif printf '%s' "$summary" | jq -e 'has("invalid")' >/dev/null 2>&1; then
        status=invalid; why="$(printf '%s' "$summary" | jq -r '.invalid')"
      elif ! prel="$(vetdd_mutation_prel "$root" "$(printf '%s' "$summary" | jq -r '.projectRoot')")"; then
        status=invalid; why="its projectRoot is not a directory inside the repository"
      else
        while IFS= read -r -d '' k; do keys+=("$k"); done < <(printf '%s' "$summary" | jq -j '.keys[] | ., "\u0000"')
        files="$(vetdd_mutation_files "$root" "$raw" "$prel" "$src" "${keys[@]}")"; rc=$?
        if [ "$rc" -eq 3 ]; then status=invalid; why="two file keys name one file (another letter case on this file system)"
        elif [ "$rc" -ne 0 ]; then status=invalid; why="a file key names a file through a link or outside the repository"
        elif ! jq "$VETDD_STRYKER_COPY" "$raw" > "$norm" 2>/dev/null || ! sum="$(vetdd_sha256 "$norm")" \
             || ! chmod "$(vetdd_file_mode)" "$norm" || ! mv -f -- "$norm" "$copy"; then
          status=invalid; why="its copy could not be written"
        fi
      fi
    fi
  fi
  # Stryker writes "files": {} when the --mutate ranges held no mutant at all: recorded as empty, not invalid.
  # Only a report that passes every other check: one object, schema 1.x, an absolute projectRoot that is a
  # directory inside the repository, a command for the command runner (the same filter, run with a
  # placeholder file in place of the empty files), all in one jq.
  if [ "$status" = invalid ] && [ "$got" -eq 1 ] \
     && jq -e -s 'length == 1 and (.[0] | type) == "object" and .[0].files == {}
          and (.[0] | .files = {"placeholder.ts": {"source": "", "mutants": []}} | try (('"$VETDD_STRYKER_JSON"') | true) catch false)' \
          "$raw" >/dev/null 2>&1 \
     && vetdd_mutation_prel "$root" "$(jq -r '.projectRoot' "$raw" 2>/dev/null)" >/dev/null; then
    status=empty; why=""
    printf 'evidence.sh: warning: mutation report %s mutated nothing: the --mutate ranges held no mutant (an emptied function body needs the range to reach its closing brace)\n' "$rel" | vetdd_printable >&2
  fi
  [ -z "$raw" ] || rm -f -- "$raw"
  [ -z "$norm" ] || rm -f -- "$norm"
  [ -z "$src" ] || rm -f -- "$src"
  trap - INT TERM HUP
  if [ -n "$status" ]; then
    # Never through a swapped runs directory: nothing is removed outside the repository.
    [ -L "$runs" ] || rm -f -- "$copy" 2>/dev/null
    printf 'evidence.sh: warning: mutation report %s is %s%s; recorded audit.report.status=%s (the outcome still comes from the exit code)\n' \
      "$rel" "$status" "${why:+ ($why)}" "$status" | vetdd_printable >&2
    jq -n --arg p "$rel" --arg s "$status" '{format: "stryker-json", path: $p, status: $s}'
    return 0
  fi
  printf '%s' "$summary" | jq --arg p "$rel" --arg sum "$sum" --arg c "$copy_rel" --argjson files "$files" \
    '{format: "stryker-json", path: $p, status: "ok", sha256: $sum, copy: $c, counts, files: $files}' \
    || { rm -f -- "$copy"; return 1; }
}
