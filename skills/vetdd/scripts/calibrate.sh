#!/usr/bin/env bash
# Record a calibration red without ever losing the uncommitted fix (modes/test.md, principle 2).
#
# Usage (run from the directory the oracle command runs in; paths are relative to it):
#   calibrate.sh unfix   <slice> --file <f>... --oracle-file <o>... [evidence options] -- <command...>
#       Take the fix in <f>... out (staged, unstaged, and new files), run the oracle on the
#       defect, then put every file and its index entry back byte for byte.
#   calibrate.sh plant   <slice> --file <f>... --oracle-file <o>...
#       Save <f>... and fingerprint the oracle and everything else, so a mutation can be planted.
#   calibrate.sh planted <slice> --oracle-file <o>... [evidence options] -- <command...>
#       Check the mutation is in <f>... only and the oracle is untouched, run the oracle, put the
#       saved files and their index entries back.
#   calibrate.sh stub    <slice> --file <product file>... --oracle-file <o>... [--oracle-version <v>]
#                        [--seam <s>] -- <command...>
#       The undefined-imports audit (principle 4's quick check): replace every product file the oracle
#       imports with a stub whose exports are all undefined, run the command as a calibration marked
#       audit: {"kind": "undefined-imports"}, then put the files back. It must end target_failure
#       (exit 0): a test that still passes (exit 1) observes nothing. Stubs: .ts .tsx .jsx .mjs .mts ->
#       `export {};` (.ts .tsx .jsx: the same guarded CommonJS module as .js when the nearest
#       package.json says "commonjs"); .cjs .cts -> `module.exports = {};`; .js -> by the nearest package.json "type"
#       (an empty CommonJS module, or `export {};` for "module"); .py -> a module __getattr__ returning
#       None; any other extension is a usage error before anything changes. Run it once the test is green; it is
#       also the rule 10b record (check-evidence), unless audit-note.sh says it does not apply.
#   calibrate.sh restore <slice>
#       Put back whatever an interrupted unfix, plant, or stub left saved.
#
# Unfix, plant, and stub save a byte copy and the index entry of every <f> before anything changes,
# and restoring always writes those back, so neither line-ending conversion nor a staged edit can
# alter what returns (stub puts a new file in place, so a hard link never keeps the stub). --file and
# --oracle-file take regular files inside the repository (no directories, no symlinks, no newlines),
# compared as files (-ef), so the oracle is never parked under another spelling. --seam, --oracle-version, and --oracle-file pass through to
# evidence.sh <slice> calibration. State lives in <git dir>/vetdd-calib/<slice>/, survives a killed
# run, and its path is printed first. Fingerprints detect accidental damage; they are not a
# security boundary (anyone who can write .git can already run hooks). The stub audit is a tripwire,
# not a boundary: it stubs only the files named with --file (a product file left out is still real, so
# name every one the oracle imports); a runner that fails on the stub while loading it (native ESM
# reports a missing named export as a link error) goes red for the wrong reason, so read the log.
# Exit: 0 the calibration ended target_failure; 1 it did not; 2 usage or refused (nothing
# changed); 3 the files could not be put back (state kept).
set -u

unset CDPATH  # `cd dir` must never resolve through CDPATH or print a path
here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)" && [ -n "$here" ] || { echo "calibrate.sh: cannot locate itself" >&2; exit 2; }
. "$here/lib/common.sh"
. "$here/lib/tree-hash.sh"
vetdd_require_jq calibrate.sh

# A name in a message (a file the user named) can hold control characters: show it filtered.
die() { printf 'calibrate.sh: %s\n' "$(printf '%s' "$1" | vetdd_printable)" >&2; exit "${2:-2}"; }
warn() { printf 'calibrate.sh: %s\n' "$(printf '%s' "$1" | vetdd_printable)" >&2; }

cmd="${1:-}"; slice="${2:-}"
[ -n "$cmd" ] && [ -n "$slice" ] || die "usage: calibrate.sh unfix|plant|planted|stub|restore <slice> ..."
vetdd_is_slice_id "$slice" || die "invalid slice id: $slice"
shift 2
top="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git working tree"
top="$(cd "$top" && pwd -P)"
gitdir="$(git rev-parse --absolute-git-dir 2>/dev/null)" && [ -n "$gitdir" ] || die "cannot locate the git dir"
state="$gitdir/vetdd-calib/$slice"
# The restore command (recovery after an interruption) keeps any content it replaces here.
keep_replaced=0; replaced="$gitdir/vetdd-calib/$slice.replaced.$(date +%Y%m%d%H%M%S).$$"

# Literal pathspecs (a path with [ ] * ? is a name, not a glob), unquoted names, and whitespace
# handling fixed, so neither the path nor the user's git config changes what is taken out.
g() { GIT_LITERAL_PATHSPECS=1 git -C "$top" -c core.quotePath=false -c apply.whitespace=nowarn "$@"; }
# A fixed diff format against HEAD (staged and unstaged together); only used to take the fix out.
fix_diff() {
  g diff HEAD --no-ext-diff --no-textconv --no-color --no-renames --unified=3 --binary \
    --src-prefix=a/ --dst-prefix=b/ -- "$@"
}

# rel <path>: the repository-relative real path of a regular file, or die.
rel() {
  local p="$1" d
  case "$p" in -*) p="./$p" ;; esac  # dirname and basename would read it as an option
  case "$p" in *$'\n'*) die "a file name containing a newline cannot be parked" ;; esac
  [ ! -L "$p" ] || die "$p is a symlink; pass the file it points to"
  [ -f "$p" ] || die "$p is not a regular file (directories are refused)"
  d="$(cd "$(dirname -- "$p")" && pwd -P)" || die "cannot resolve $p"
  case "$d/" in "$top"/*) ;; *) die "$p is outside the repository" ;; esac
  # Use the name as it is on disk, so a different letter case on a case-insensitive file system is
  # neither missed by git nor written back under the wrong spelling.
  local name
  name="$(vetdd_disk_name "$d" "$p")"
  d="${d#"$top"}"; d="${d#/}"
  # Every component under its on-disk spelling, as evidence.sh records it.
  local path
  path="$(vetdd_disk_path "$top" "${d:+$d/}$name")"
  case "/$(printf '%s' "$path" | tr 'A-Z' 'a-z')/" in */.git/*) die "$p is .git or inside it" ;; esac
  printf '%s\n' "$path"
}

files=(); oracle=(); pass=(); argv=(); have_cmd=0
parse() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --file) [ $# -ge 2 ] || die "--file needs a path"; files+=("$(rel "$2")") || exit 2; shift 2 ;;
      --oracle-file) [ $# -ge 2 ] || die "--oracle-file needs a path"
        o="$(rel "$2")" || exit 2
        # evidence.sh refuses an oracle file name with a control character; refuse it before anything is parked.
        vetdd_inside_repo "$top" "$o" || die "an oracle file name with a control character cannot be used"
        # One entry per file: a file named twice is one oracle file (as evidence.sh records it).
        seen=0
        for x in ${oracle[@]+"${oracle[@]}"}; do [ "$x" = "$o" ] && seen=1; done
        [ "$seen" -eq 1 ] || oracle+=("$o")
        case "$2" in -*) pass+=("$1" "./$2") ;; *) pass+=("$1" "$2") ;; esac; shift 2 ;;
      --seam) [ $# -ge 2 ] || die "$1 needs a value"; pass+=("$1" "$2"); shift 2 ;;
      --oracle-version) [ $# -ge 2 ] || die "$1 needs a value"
        # Checked here, before the fix is parked: evidence.sh refuses it with exit 2, which would
        # otherwise read as "the calibration did not go red" (exit 1).
        vetdd_is_slice_id "$2" || die "--oracle-version takes letters, digits, and . _ -"
        pass+=("$1" "$2"); shift 2 ;;
      --) shift; argv=("$@"); have_cmd=1; return ;;
      *) die "unknown option: $1 (--file, --oracle-file, --seam, --oracle-version)" ;;
    esac
  done
}

require_oracle() { [ ${#oracle[@]} -gt 0 ] || die "--oracle-file is required: the oracle must be named so it is never parked"; }
require_cmd() { [ "$have_cmd" -eq 1 ] && [ ${#argv[@]} -gt 0 ] || die "a command after -- is required"; }
require_files() {
  [ ${#files[@]} -gt 0 ] || die "at least one --file is required"
  local f o
  for f in "${files[@]}"; do
    for o in "${oracle[@]}"; do
      # -ef compares the files themselves, so letter case or a hard link cannot disguise the oracle.
      [ ! "$top/$f" -ef "$top/$o" ] || die "$f is the oracle file $o; the oracle must not be parked"
    done
  done
}

# fingerprint <path>: executable bit plus content digest, link target, or absence; "!" if unreadable.
fingerprint() {
  local p="$1" h
  if [ -L "$top/$p" ]; then printf 'link:%s' "$(readlink "$top/$p")"
  elif [ -f "$top/$p" ]; then
    h="$(vetdd_sha256 "$top/$p")" || { printf '!'; return; }
    if [ -x "$top/$p" ]; then printf 'x%s' "$h"; else printf -- '-%s' "$h"; fi
  else printf -- '-'; fi
}
oracle_prints() { local o; for o in "${oracle[@]}"; do printf '%s %s\n' "$(fingerprint "$o")" "$o"; done | sort; }
# Every path that differs from HEAD or is untracked, minus the saved set, fingerprinted; names are
# printed with %q so a newline in a name stays one entry. Files ignored by git are not covered.
others() {
  local p saved base names
  saved=$'\n'"$(cat "$state/files")"$'\n'
  base=HEAD; g rev-parse -q --verify HEAD >/dev/null || base="$(g hash-object -t tree /dev/null)"
  names="$(mktemp "$state/names.XXXXXX")" || { echo '! cannot list changed files'; return; }
  if ! { g diff "$base" --name-only --no-ext-diff --no-renames -z && g ls-files -z --others --exclude-standard; } > "$names"; then
    echo '! git could not list changed files'; rm -f "$names"; return
  fi
  while IFS= read -r -d '' p; do
    case "$saved" in *$'\n'"$p"$'\n'*) continue ;; esac
    printf '%s %q\n' "$(fingerprint "$p")" "$p"
  done < "$names" | sort
  rm -f "$names"
}
unreadable() { grep -q '^!' "$@"; }

# Save a byte copy, its digest, and the index entry of every file in $state/files.
# is_ita <path> <sha>: an intent-to-add entry holds the empty blob, is absent from HEAD, and is
# invisible to `diff --cached` (a staged empty new file is not).
is_ita() {
  [ "$2" = "$(g hash-object -t blob /dev/null)" ] || return 1
  ! g cat-file -e "HEAD:$1" 2>/dev/null || return 1
  g diff --cached --quiet -- "$1"
}

save_originals() {
  local f entry h meta path sha tag
  for f in "${files[@]}"; do
    tag="$(g ls-files -v -- "$f" | cut -c1)"
    case "$tag" in
      S) die "$f is marked skip-worktree; clear the flag (git update-index --no-skip-worktree) first" ;;
      [a-z]) die "$f is marked assume-unchanged; clear the flag (git update-index --no-assume-unchanged) first" ;;
    esac
  done
  : > "$state/index" && : > "$state/ita" || die "cannot write $state"
  g ls-files -s -z -- "${files[@]}" > "$state/ls-files" || die "git ls-files failed; nothing was changed"
  while IFS= read -r -d '' entry; do
    meta="${entry%%$'\t'*}"; path="${entry#*$'\t'}"
    case "$meta" in *" 0") ;; *) die "$path has an unresolved merge conflict" ;; esac
    case "$meta" in "100644 "*|"100755 "*) ;; *) die "$path has an index mode calibrate.sh does not restore (${meta%% *})" ;; esac
    sha="${meta#* }"; sha="${sha%% *}"
    if is_ita "$path" "$sha"; then printf '%s\n' "$path" >> "$state/ita" || die "cannot write $state/ita"
    else printf '%s\t%s\0' "$meta" "$path" >> "$state/index" || die "cannot write $state/index"; fi
  done < "$state/ls-files"
  : > "$state/copies.sha"
  for f in "${files[@]}"; do
    mkdir -p "$state/copies/$(dirname -- "$f")" && cp -p "$top/$f" "$state/copies/$f" || die "cannot save $f"
    h="$(vetdd_sha256 "$state/copies/$f")" || die "cannot fingerprint the saved copy of $f; nothing was changed"
    printf '%s %s\n' "$h" "$f" >> "$state/copies.sha" || die "cannot write $state/copies.sha"
  done
  : > "$state/saved" || die "cannot write $state/saved"  # from here on the working tree may change, so restore must write the copies back
}

# drop_pyc <path>: a .py file's bytecode caches (__pycache__/<stem>.*.pyc), which Python validates by whole
# seconds and size, so a stub and the original of equal size could otherwise be mistaken for each other.
drop_pyc() {
  case "$(printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z')" in *.py) ;; *) return 0 ;; esac
  local dir stem
  dir="$(dirname -- "$top/$1")"; stem="$(basename -- "$1")"; stem="${stem%.*}"
  # A __pycache__ that is a link points somewhere this script has not checked: leave it alone.
  [ -d "$dir/__pycache__" ] && [ ! -L "$dir/__pycache__" ] || return 0
  rm -f "$dir/__pycache__/$stem".*.pyc 2>/dev/null
  return 0
}

# Put every saved file and index entry back, then remove the state atomically. Returns non-zero,
# keeping the state, if anything cannot be verified.
restore() {
  [ -d "$state" ] || return 0
  local f d tmp h meta
  case "$(cat "$state/mode" 2>/dev/null)" in unfix|plant|stub|"") ;; *) warn "$state has an unknown mode; inspect it by hand"; return 1 ;; esac
  if [ ! -f "$state/files" ]; then
    [ ! -e "$state/mode" ] || { warn "$state is incomplete (no file list); inspect it by hand"; return 1; }
  elif [ -f "$state/saved" ]; then
    while IFS= read -r f; do
      case "/$f/" in //|*/../*|*/./*) warn "$state/files holds an unsafe path: $f"; return 1 ;; esac
      h="$(vetdd_sha256 "$state/copies/$f")" && grep -qxF "$h $f" "$state/copies.sha" \
        || { warn "the saved copy of $f changed or is missing; it is in $state/copies"; return 1; }
      # The parent must resolve inside the repository; write an exclusive temp file beside the target
      # and rename over it, so a symlink put in the target's place is replaced, never followed.
      mkdir -p "$top/$(dirname -- "$f")" 2>/dev/null
      d="$(cd "$top/$(dirname -- "$f")" 2>/dev/null && pwd -P)"
      case "$d/" in "$top"/*) ;; *) warn "the directory of $f no longer resolves inside the repository"; return 1 ;; esac
      case "/$(printf '%s' "${d#"$top"}" | tr 'A-Z' 'a-z')/" in */.git/*) warn "the directory of $f now resolves into .git"; return 1 ;; esac
      if [ "$keep_replaced" -eq 1 ] && [ -e "$top/$f" ] && ! cmp -s "$state/copies/$f" "$top/$f"; then
        mkdir -p "$replaced/$(dirname -- "$f")" && cp -p "$top/$f" "$replaced/$f" \
          || { warn "could not keep the current $f before replacing it"; return 1; }
      fi
      # touch the temp file, not the target: the rename is then the last step and follows no link.
      tmp="$(mktemp "$top/$f.XXXXXX")" && cp -p "$state/copies/$f" "$tmp" && touch "$tmp" && mv -f "$tmp" "$top/$f" \
        && [ ! -L "$top/$f" ] && cmp -s "$state/copies/$f" "$top/$f" \
        || { rm -f "$tmp"; warn "could not put back $f; the copy is in $state/copies"; return 1; }
      drop_pyc "$f"
    done < "$state/files"
  fi
  if [ -f "$state/tmps" ]; then
    # Temp files a stub write was interrupted on: only paths inside the repository, never a directory.
    while IFS= read -r f; do
      case "$f" in "$top"/*) ;; *) continue ;; esac
      case "/$f/" in */../*|*/./*) continue ;; esac
      [ ! -d "$f" ] && rm -f -- "$f"
    done < "$state/tmps"
  fi
  if [ -f "$state/saved" ] && [ -f "$state/files" ]; then
    local rec path mode sha restored=$'\n'
    while IFS= read -r -d '' rec; do
      meta="${rec%%$'\t'*}"; path="${rec#*$'\t'}"
      mode="${meta%% *}"; sha="${meta#* }"; sha="${sha%% *}"
      case "$mode" in 100644|100755) ;; *) warn "$state/index holds an unexpected mode for $path"; return 1 ;; esac
      g update-index --add --cacheinfo "$mode,$sha,$path" || { warn "could not put back the index entry of $path"; return 1; }
      restored="$restored$path"$'\n'
    done < "$state/index"
    while IFS= read -r f; do
      case "$restored" in *$'\n'"$f"$'\n'*) continue ;; esac
      g rm -q --cached --ignore-unmatch -- "$f" >/dev/null || { warn "could not drop the index entry of $f"; return 1; }
      if grep -qxF -- "$f" "$state/ita"; then
        g add --intent-to-add -- "$f" || { warn "could not put back the intent-to-add entry of $f"; return 1; }
      fi
    done < "$state/files"
  fi
  [ ! -d "$replaced" ] || warn "kept the replaced content in $replaced"
  mv "$state" "$state.done.$$" 2>/dev/null && rm -rf "$state.done.$$" || { warn "could not remove $state"; return 1; }
}

new_state() {
  mkdir -p "$(dirname -- "$state")" || die "cannot create $(dirname -- "$state")"
  # mkdir without -p succeeds for exactly one caller, so it doubles as the lock for this slice.
  mkdir "$state" 2>/dev/null || die "a calibration for $slice is running or was interrupted; run: calibrate.sh restore $slice"
  trap 'restore || exit 3' EXIT
  trap 'exit 130' INT TERM
  echo "calibrate.sh: saved state for $slice in $state"
  echo $$ > "$state/pid" && printf '%s\n' "${files[@]}" > "$state/files" || die "cannot write $state"
}

# stub_text <path>: the stub for the file's extension on standard output; non-zero when it has none.
# A .cjs or .cts is always CommonJS and a .mjs always an ES module. A .js is an ES module when the nearest
# package.json says "type": "module"; otherwise the stub is valid either way (an empty module in CommonJS,
# a module with no exports in ESM), so a stub never fails on its own syntax.
nearest_package_type() {
  local d="$top/$(dirname -- "$1")"
  while :; do
    if [ -f "$d/package.json" ]; then jq -r '.type // ""' "$d/package.json" 2>/dev/null; return 0; fi
    [ "$d" != "$top" ] && [ "$d" != / ] || break
    d="$(dirname -- "$d")"
  done
  return 0
}
stub_text() {
  case "$(printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z')" in
    *.cjs|*.cts) printf 'module.exports = {};\n' ;;
    *.js)
      if [ "$(nearest_package_type "$1")" = module ]; then printf 'export {};\n'
      else printf 'if (typeof module !== "undefined") { module.exports = {}; }\n'; fi ;;
    *.ts|*.tsx|*.jsx)
      if [ "$(nearest_package_type "$1")" = commonjs ]; then printf 'if (typeof module !== "undefined") { module.exports = {}; }\n'
      else printf 'export {};\n'; fi ;;
    *.mjs|*.mts) printf 'export {};\n' ;;
    *.py) printf "def __getattr__(name):\n    if name.startswith('__') and name.endswith('__'):\n        raise AttributeError(name)\n    return None\n" ;;
    *) return 1 ;;
  esac
}
# mode_of <path>: permission bits in octal (GNU stat first: BSD stat has no -c, and GNU stat -f prints file system data).
mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
# write_stub <path>: a new file in the place of the saved one (the temp file made beside it takes the
# old mode), so a hard link never keeps the stub and a symlink put there is replaced, not followed.
write_stub() {
  local f="$1" tmp
  # Write the stub before taking over the old mode: a read-only original would make the temp file unwritable.
  # The temp file is listed in the state before anything can interrupt the write; restore removes it.
  tmp="$(mktemp "$top/$f.XXXXXX")" && printf '%s\n' "$tmp" >> "$state/tmps" \
    && stub_text "$f" > "$tmp" && chmod "$(mode_of "$top/$f")" "$tmp" \
    && mv -f "$tmp" "$top/$f" && drop_pyc "$f" || { rm -f "$tmp"; return 1; }
}

audit=""  # undefined-imports while a stub run is going
run_oracle() {
  local meta="$top/.vetdd/evidence/$slice/meta.json" last rc outcome audit_opt=()
  # Python reads and writes bytecode only in an empty directory of its own while the stub is in place:
  # no cache of the original can be mistaken for the stub, and none of the stub outlives it (the state
  # directory goes with the run). PYTHONPYCACHEPREFIX redirects both, wherever the caller had put it.
  if [ -n "$audit" ]; then
    audit_opt=(--audit "$audit")
    mkdir -p "$state/pycache" || { warn "cannot create $state/pycache"; return 1; }
    export PYTHONPYCACHEPREFIX="$state/pycache" PYTHONDONTWRITEBYTECODE=1
  fi
  last="$(jq '[.runs[].seq] | max // 0' "$meta" 2>/dev/null || echo 0)"
  [ "${VETDD_TEST_HOOKS:-}" != 1 ] || export VETDD_CALIBRATE_PID=$$
  "$here/evidence.sh" "$slice" calibration ${pass[@]+"${pass[@]}"} ${audit_opt[@]+"${audit_opt[@]}"} -- "${argv[@]}"; rc=$?
  # Only a run this call added counts, and only if evidence.sh itself succeeded.
  outcome="$(jq -r --argjson last "${last:-0}" \
    '[.runs[] | select(.seq > $last and .kind == "calibration")] | last | .outcome // empty' "$meta" 2>/dev/null)"
  if [ "$rc" -ne 0 ] || [ -z "$outcome" ]; then
    warn "no new calibration run was recorded (evidence.sh exit $rc)"
    return 1
  fi
  if [ -n "$audit" ]; then
    if [ "$outcome" = target_failure ]; then
      echo "calibrate.sh: the oracle went red with every product file stubbed; read the log: the red must be the test's own assertion or a TypeError on an undefined export, not an import or syntax error"
      return 0
    fi
    if [ "$outcome" = pass ]; then
      warn "the oracle still passed with every named product file stubbed (all exports undefined): the test is vacuous, it observes nothing; make it call or check the product code, then run stub again"
    else
      warn "the stubbed run ended $outcome, not target_failure, so the audit proves nothing; read the log and run it again"
    fi
    return 1
  fi
  [ "$outcome" = target_failure ] && return 0
  warn "the calibration did not end target_failure (got $outcome); the oracle does not see the defect"
  return 1
}

finish() {
  local rc="$1"
  trap '' INT TERM  # restoring must not be cut short
  trap - EXIT
  restore || exit 3
  exit "$rc"
}

case "$cmd" in
  unfix)
    parse "$@"; require_cmd; require_oracle; require_files
    new_files=()
    for f in "${files[@]}"; do
      if ! g ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
        ! g check-ignore -q -- "$f" || die "$f is ignored by git and cannot be parked; unignore it or leave it out"
        new_files+=("$f")
      fi
    done
    new_state
    save_originals
    echo unfix > "$state/mode"
    for f in ${new_files[@]+"${new_files[@]}"}; do
      g add --intent-to-add -- "$f" || die "could not mark $f with intent-to-add"
    done
    fix_diff "${files[@]}" > "$state/fix.patch" || die "git diff failed"
    [ -s "$state/fix.patch" ] || die "nothing to unfix: the files hold no change against HEAD"
    g apply -R --whitespace=nowarn --binary "$state/fix.patch" || die "could not take the fix out; nothing was changed"
    run_oracle; finish $?
    ;;
  plant)
    parse "$@"; require_oracle; require_files
    [ "$have_cmd" -eq 0 ] || die "plant takes no command; plant the mutation, then run planted"
    new_state
    save_originals
    oracle_prints > "$state/oracle"
    others > "$state/others"
    ! unreadable "$state/oracle" "$state/others" || die "a file could not be fingerprinted; nothing was changed"
    echo plant > "$state/mode" && rm -f "$state/pid" || die "cannot write $state"
    trap - EXIT
    echo "calibrate.sh: plant the mutation in the saved files now, then run: calibrate.sh planted $slice --oracle-file ... -- <command>"
    ;;
  planted)
    parse "$@"; require_cmd; require_oracle
    [ ${#files[@]} -eq 0 ] || die "planted takes no --file; the saved set comes from plant"
    [ "$(cat "$state/mode" 2>/dev/null)" = plant ] || die "no planted state for $slice; run calibrate.sh plant first"
    now_oracle="$(oracle_prints)"; now_others="$(others)"
    ! printf '%s\n%s\n' "$now_oracle" "$now_others" | grep -q '^!' || die "a file could not be fingerprinted"
    [ "$now_oracle" = "$(cat "$state/oracle")" ] \
      || die "the oracle changed since plant, or a different oracle was named; the mutation must be in product files only"
    [ "$now_others" = "$(cat "$state/others")" ] \
      || die "files outside the saved --file set changed since plant; plant the mutation in the saved files only"
    changed=0
    while IFS= read -r f; do
      [ ! -L "$top/$f" ] && [ -f "$top/$f" ] \
        || die "$f is no longer a regular file (a symlink or removed); run: calibrate.sh restore $slice"
      cmp -s "$state/copies/$f" "$top/$f" || changed=1
      if [ -x "$state/copies/$f" ]; then [ -x "$top/$f" ] || changed=1; else [ ! -x "$top/$f" ] || changed=1; fi
    done < "$state/files"
    [ "$changed" -eq 1 ] || die "no mutation was planted in the saved files"
    # mkdir succeeds for exactly one caller, so two planted runs of one slice cannot both start.
    mkdir "$state/run.lock" 2>/dev/null || die "another planted run of $slice is running or was interrupted; run: calibrate.sh restore $slice"
    echo $$ > "$state/pid" || die "cannot claim $state"
    echo "calibrate.sh: saved state for $slice in $state"
    trap 'restore || exit 3' EXIT
    trap 'exit 130' INT TERM
    run_oracle; finish $?
    ;;
  stub)
    parse "$@"; require_cmd; require_oracle; require_files
    # Every extension is checked before anything is parked: a file with no stub changes nothing.
    for f in "${files[@]}"; do
      stub_text "$f" >/dev/null || die "$f has no stub for its extension (.ts .tsx .js .jsx .mjs .cjs .mts .cts, .py); nothing was changed"
    done
    new_state
    save_originals
    echo stub > "$state/mode"
    for f in "${files[@]}"; do
      write_stub "$f" || die "could not write the stub over $f; the original is put back when this script exits"
    done
    audit=undefined-imports
    run_oracle; finish $?
    ;;
  restore)
    [ -d "$state" ] || die "nothing saved for $slice"
    pid="$(cat "$state/pid" 2>/dev/null)"
    if [ -n "$pid" ] && [ "$pid" != "$$" ] && kill -0 "$pid" 2>/dev/null; then
      die "the calibration that owns $slice is still running (pid $pid); wait for it or stop it first"
    fi
    keep_replaced=1
    restore || exit 3
    echo "calibrate.sh: restored $slice"
    ;;
  *) die "unknown command: $cmd (unfix, plant, planted, stub, restore)" ;;
esac
