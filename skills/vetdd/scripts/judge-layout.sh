#!/usr/bin/env bash
# Build the final judge's directory that references/final-judge-rubric.md "Layout" defines (test and
# verify modes, Close), so it is never assembled by hand.
# Usage: judge-layout.sh --out <dir> --reply <file> --base <git ref> [--allow-secrets <glob>[:<kind>,...]]...
#                        [--allow-binary <path>]... [--include-new <path>]... [--allow-words <glob>:<word>,...]...
#                        [--verify-artifacts <path>]... [--before-close] [--lane] <slice-id>...
#   --include-new: a new file (not in HEAD, not ignored, outside .vetdd/) that is not staged with content
#   (untracked, or only intent-to-add with git add -N) leaves the machine in the diff only when named
#   here, by its path from the repository root, or when it is one of the slices' oracle files (those go
#   even when .gitignore matches them, since they are copied to artifact/tests anyway); a file
#   staged with git add goes as it is. Any other stops the build (exit 2, nothing written) with the
#   flags to name each one (the first 20), so a scratch file never leaves unseen. A .env file (any case;
#   .env.example, .env.sample, and .env.template excepted) stops it wherever it would go: a new file of
#   any kind, an oracle file (ignored or not), or a path the diff from --base changes.
#   --allow-words: product words a human confirmed (an SDK named after a model's maker), for
#   check-blind.sh and the printed judge command. variant and baseline are not checked for one
#   delivered change (winner still is: a reply names the chosen lane, never a winner); --lane (an
#   arena lane, compared with others) keeps all three.
#   --verify-artifacts: verify mode's artifacts (modes/verify.md), a path from the repository root at or
#   under .vetdd/artifacts/ (a directory or a file; no //, ./, ../, or link on the way): every text file
#   in it goes to artifact/verify-artifacts/<its path below .vetdd/artifacts/>, with the same
#   replacement, rename, and checks as the rest. A file that is not text (a screenshot: the judge's blind
#   check reads text only) stays on the machine and is named on stderr; a link, a file that is not
#   regular, or a .env file in it stops the build (exit 2, nothing written).
#   --allow-secrets: the glob names paths of the layout under c1/artifact/ or c1/evidence/ (c*/ only
#   for an arena lane, --lane, as arena-layout.sh passes it) and starts below them with a literal name
#   (tests, diff.patch, a slice), so the secret check never stops for the whole layout or a whole half
#   of it (exit 2 otherwise, nothing written). check-blind's * crosses "/": a c*/ glob can still reach
#   further into a lane than its text says.
#   --before-close: check-evidence.sh runs with it (an arena lane, laid out before its Close: the
#   mutation audit is not due yet), as arena-layout.sh's gate does
#   <dir>/c1/artifact/diff.patch          git diff --no-ext-diff --binary <base> on the working tree, every
#                                         file not in HEAD outside .vetdd/ included (staged, an oracle
#                                         file, or untracked and named with --include-new)
#                                         through a temporary index (the repository's own index is untouched)
#   <dir>/c1/artifact/reply.md            the reply draft (<file>)
#   <dir>/c1/artifact/check-evidence.txt  check-evidence.sh <slices>, then a last line "exit <code>"
#   <dir>/c1/artifact/tests/<path>        each file in the slices' oracle.files, as it is now (each a plain
#                                         path from the repository root: no empty, . or .. component, and
#                                         no .git one in any case, or the record is refused, exit 1)
#   <dir>/c1/artifact/verify-artifacts/<path>  the text files of each --verify-artifacts path
#   <dir>/c1/evidence/<slice>/meta.json   each slice's record
#   <dir>/c1/evidence/<slice>/runs/...    its red-run logs (accepted before or calibration runs that ended
#                                         target_failure, the undefined-imports audit included, the mutation
#                                         audit not), runs/<seq>-planted.patch next to a red that
#                                         calibrate.sh planted (what was planted, check-evidence rule 12),
#                                         and the copy of the mutation report check-evidence rule 10c
#                                         judges (the latest mutation run after the final green, of the
#                                         final oracle, when its report is usable); green logs stay here
# <dir> must be outside the repository or under its .vetdd/ (anywhere else, its own files would change
# the tree check-evidence hashes). Every copied text file has the repository's absolute path, as a whole
# path, replaced with <repo>, and the user's home directory with <home> (unless HOME is a shared place
# such as /tmp or /usr), each also percent-encoded (a file:// URL); a .claude directory (where verify
# mode keeps its skill) is renamed .agent, in names and text alike, since the judge must not see the
# author's tool (.agent2, .agent3, ... when that name is already in what is sent, in any letter case,
# so two paths never become one; the --allow-secrets and --allow-words globs are renamed alike); then
# check-blind.sh --profile judge runs on <dir>, with each
# --allow-secrets (paths relative to <dir>, e.g. c1/artifact/tests/*:email, only for test data a human
# confirmed), which the printed judge.sh command repeats. Run it on the delivered tree.
# Exit 0 built (it prints the judge.sh command); 1 a local step failed (a record could not be read,
# check-blind could not run); 2 usage error, a binary file in the diff not named with --allow-binary
# (git's base85 text of a binary file passes the blind and secret checks unseen), or an untracked new
# file not named with --include-new, or a --verify-artifacts path or file refused (nothing is written
# in each case);
# 4 the result is not blind
# (check-blind.sh's hits are printed; <dir> is left to inspect, readable by the user only).
# Everything written is private to the user (umask 077), and <dir> must be new, under directories only
# the user or root can change (or sticky ones), so no other user can read it or swap it before the judge.
set -u
unset CDPATH GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_ICASE_PATHSPECS
umask 077

# Every message may carry a value from the command line: strip control characters (vetdd_printable,
# lib/common.sh, once it is loaded).
die() {
  if declare -F vetdd_printable >/dev/null; then printf 'judge-layout.sh: %s\n' "$1" | vetdd_printable >&2
  else printf 'judge-layout.sh: %s\n' "$1" >&2; fi
  exit "${2:-2}"
}

here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
. "$here/lib/common.sh"
. "$here/lib/tree-hash.sh"  # vetdd_sha256
vetdd_require_jq judge-layout.sh

out=""; reply=""; base=""; slices=(); allow=(); binaries=(); news=(); ce_opts=(); awords=(); varts=(); lane=0
while [ $# -gt 0 ]; do
  case "$1" in
    --out) [ $# -ge 2 ] || die "--out needs a directory"; out="$2"; shift 2 ;;
    --reply) [ $# -ge 2 ] || die "--reply needs a file"; reply="$2"; shift 2 ;;
    --base) [ $# -ge 2 ] || die "--base needs a git ref"; base="$2"; shift 2 ;;
    --allow-secrets) [ $# -ge 2 ] || die "--allow-secrets needs <glob>[:<kind>,...]"; allow+=("$2"); shift 2 ;;
    --allow-words) [ $# -ge 2 ] || die "--allow-words needs <glob>:<word>[,<word>]..."
      . "$here/lib/blind-words.sh"; err="$(vetdd_allow_words_error "$2")" || die "$err"; awords+=("$2"); shift 2 ;;
    --allow-binary) [ $# -ge 2 ] || die "--allow-binary needs a repository path"; binaries+=("$2"); shift 2 ;;
    --include-new) [ $# -ge 2 ] || die "--include-new needs a repository path"; news+=("$2"); shift 2 ;;
    --verify-artifacts) [ $# -ge 2 ] || die "--verify-artifacts needs a path under .vetdd/artifacts/"; varts+=("$2"); shift 2 ;;
    --before-close) ce_opts=(--before-close); shift ;;
    --lane) lane=1; shift ;;
    -*) die "unknown option: $(printf '%s' "$1" | vetdd_printable)" ;;
    *) slices+=("$1"); shift ;;
  esac
done
[ -n "$out" ] && [ -n "$reply" ] && [ -n "$base" ] && [ ${#slices[@]} -gt 0 ] \
  || die "usage: judge-layout.sh --out <dir> --reply <file> --base <git ref> [--allow-secrets <glob>[:<kind>,...]]... [--allow-binary <path>]... [--include-new <path>]... [--allow-words <glob>:<word>,...]... [--verify-artifacts <path>]... [--before-close] [--lane] <slice-id>..."
[ -f "$reply" ] && [ ! -L "$reply" ] || die "--reply must be a regular file"
. "$here/lib/secret-patterns.sh"
. "$here/lib/text.sh"
for a in ${allow[@]+"${allow[@]}"}; do
  err="$(vetdd_allow_secret_error "$a")" || die "$(printf '%s' "$err" | vetdd_printable)"
  # The glob (before the last ":" when kinds follow) stays inside one half of the layout, and names a
  # literal entry there (tests, diff.patch, verify-artifacts, a slice): check-blind's * and ? cross
  # "/", so "*", "c1/artifact/*", "c1/artifact/?*", or "c1/artifact/*/*" would stop the secret check
  # for all of it.
  g="$a"; case "$a" in *:*) g="${a%:*}" ;; esac
  # c*/ is the form arena-layout.sh passes to each lane (--lane); for one delivered change its * could
  # reach anywhere in c1 (c1/artifact/verify-artifacts/x/evidence/...), so only c1/ is taken there.
  case "$g" in
    c1/artifact/?*|c1/evidence/?*) ;;
    'c*/artifact/'?*|'c*/evidence/'?*) [ "$lane" -eq 1 ] || g="" ;;
    *) g="" ;;
  esac
  first="${g#*/*/}"; first="${first%%/*}"
  case "$first" in ""|*'*'*|*'?'*|*'['*) g="" ;; esac
  [ -n "$g" ] || die "--allow-secrets $(printf '%s' "$a" | vetdd_printable): the glob must name paths under c1/artifact/ or c1/evidence/ (c*/... only for an arena lane, --lane) and start below them with a literal name, no * ? or [ (e.g. c1/artifact/tests/*:email)"
done
# The .claude rename, also applied to the globs (see below). An arena lane (--lane): arena-layout.sh
# repeats each glob as given for the judge, and each lane picks its free name on its own, so a glob
# naming .claude would match in the lane and miss in the judge's copy: write it as the name it is sent
# under instead.
RENAME='s{(?:(?<=^-)|(?<![\w.-]))\.claude(?=\\?/|\.(?![\w-])|[^\w.-]|$)}{$ENV{TOK}}g'
if [ "$lane" -eq 1 ]; then
  for a in ${allow[@]+"${allow[@]}"} ${awords[@]+"${awords[@]}"}; do
    [ "$(printf '%s' "$a" | TOK=.agent perl -pe "$RENAME")" = "$a" ] \
      || die "$(printf '%s' "$a" | vetdd_printable): an arena lane is judged with the glob as given, so name the directory as the lanes send it (.agent/, as their layouts show), not .claude/"
  done
fi
[ ! -e "$out" ] && [ ! -L "$out" ] || die "--out $out exists; give a new directory"

root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
root="$(cd "$root" && pwd -P)"
# The spellings the repository's path can take in a log: its physical path, the same without a /private
# prefix (macOS links /var, /tmp, and /etc there), and the logical path the caller's shell shows.
prefix="$(git rev-parse --show-prefix 2>/dev/null)"; prefix="${prefix%/}"
logical_root="${PWD%/}"; [ -z "$prefix" ] || logical_root="${logical_root%/"$prefix"}"
case "$root" in /private/*) short_root="${root#/private}" ;; *) short_root="$root" ;; esac
# Built in a linked worktree (a swarm unit, an arena lane under review): the main repository's path
# shows in logs too (a linked node_modules, the parent's commands).
main_root=""; main_short=""
if gc="$(cd "$root" && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)" \
   && [ "${gc##*/}" = .git ] && [ "${gc%/.git}" != "$root" ]; then
  main_root="${gc%/.git}"
  case "$main_root" in /private/*) main_short="${main_root#/private}" ;; *) main_short="" ;; esac
fi
git -C "$root" rev-parse --verify -q "$base^{commit}" >/dev/null || die "--base is not a commit: $(printf '%s' "$base" | vetdd_printable)"
for s in "${slices[@]}"; do
  vetdd_is_slice_id "$s" || die "invalid slice id"
  [ -f "$root/.vetdd/evidence/$s/meta.json" ] && [ ! -L "$root/.vetdd/evidence/$s/meta.json" ] \
    || die "no evidence for slice $s"
done

# Where --out really is: the deepest existing ancestor resolved physically, the rest as written.
case "$out" in /*) abs="$out" ;; *) abs="$PWD/$out" ;; esac
while [ "$abs" != / ] && [ "${abs%/}" != "$abs" ]; do abs="${abs%/}"; done
[ "$abs" != / ] || die "--out must name a new directory"
# A . or .. in the path would be resolved later, by mkdir, past this check.
case "/$abs/" in */./*|*/../*) die "--out must not hold a . or .. component" ;; esac
d="$(dirname -- "$abs")"; tail="/${abs##*/}"
while [ ! -d "$d" ] && [ "$d" != / ]; do tail="/${d##*/}$tail"; d="$(dirname -- "$d")"; done
d="$(cd -P -- "$d" 2>/dev/null && pwd -P)" || die "--out is not a usable path"
abs="${d%/}$tail"
case "$abs/" in
  "$root"/.vetdd/*) ;;
  "$root"/*) die "--out must be outside the repository or under its .vetdd/: its own files would change the tree check-evidence hashes" ;;
esac
# Every existing ancestor (resolved physically, so no link on the way can be swapped later) must be the
# user's or root's, and not writable by group or others unless sticky; otherwise someone else could
# rename the layout away and put another in its place before the judge reads it. ACLs are not checked.
a="$d"
while :; do
  [ -n "$(find "$a" -maxdepth 0 \( -user "$(id -u)" -o -user 0 \) \( \( ! -perm -020 ! -perm -002 \) -o -perm -1000 \) -print 2>/dev/null)" ] \
    || die "--out: its parent $(printf '%s' "$a" | vetdd_printable) is not the user's or root's, or is writable by group or others without the sticky bit; use a directory of your own (e.g. under \${TMPDIR:-/tmp})"
  [ "$a" != / ] || break
  a="$(dirname -- "$a")"
done
# From here on, only the checked physical path is used.
out="$abs"

# The diff, with new files: a temporary index (in a private temporary directory) holds HEAD plus
# intent-to-add entries for every new file: those not in HEAD, listed against that index, and files the
# repository's own index added (git add -f of an ignored file included), and the slices' oracle files
# not in HEAD, ignored or not. The same list decides what may
# go: a file staged with content, a slice's oracle file, or one named with --include-new; any other
# stops the build before anything is written. Each name given must be one of the new files, so a
# mistyped path never passes for an allowed one.
# A .env file (any case) may hold secrets and never goes, however it became new: staged (git add -f
# included), an oracle file, or named. Its examples are product files.
is_env() {
  case "$(printf '%s' "${1##*/}" | tr '[:upper:]' '[:lower:]')" in
    .env.example|.env.sample|.env.template) return 1 ;;
    .env|.env.*) return 0 ;;
  esac
  return 1
}
oracles=()
for s in "${slices[@]}"; do
  # A malformed record stops here as malformed, before anything is written: read as empty, its oracle
  # files would be reported as unnamed new files to delete.
  # One JSON document: an empty file or two concatenated objects are malformed too.
  # A path with a control character (C0, DEL, C1) would split the NUL-separated list below; the same
  # rule as evidence.sh's for an inherited path, whatever jq's regex library takes for a control.
  # A run's log and seq become lines of the list below too, so they get the same rule.
  jq -e -s 'def plain: type == "string" and (explode | all(. > 31 and (. < 127 or . > 159)));
         def files_ok: type == "array" and all(.[]; type == "object" and (.path | plain));
         def oracle_ok: . == null or (type == "object" and (.files == null or (.files | files_ok)));
         length == 1 and (.[0] | type == "object" and (.oracle | oracle_ok)
           and (.runs | type) == "array"
           and all(.runs[]; type == "object" and (.oracle | oracle_ok)
                            and (.log == null or (.log | plain)) and (.seq == null or (.seq | type) == "number")))' \
    "$root/.vetdd/evidence/$s/meta.json" >/dev/null 2>&1 \
    || die "could not read the evidence of slice $s (its meta.json is malformed)" 1
  # evidence.sh records each oracle file as git spells it, a plain path from the repository root: one
  # with an empty, . or .. component (a//b, ./b, a/../b, /b, b/) was edited by hand, and every later
  # comparison with git's list would go wrong; a .git component in any case (.GIT on a
  # case-insensitive disk) would send the repository's own files past check-blind's .git rule.
  bad="$(jq -r '[.oracle.files[]? | .path | strings
                 | select(. == "" or (split("/") | any(. == "" or . == "." or . == ".." or ascii_downcase == ".git")))]
                | if length > 0 then "[" + .[0] + "]" else empty end' \
    "$root/.vetdd/evidence/$s/meta.json" 2>/dev/null)" || die "could not read the evidence of slice $s (its meta.json is malformed)" 1
  [ -z "$bad" ] || die "$(printf 'the record of slice %s names the oracle file %s, which is not a plain path from the repository root (no empty, . or .. component, and no .git one in any case, as evidence.sh records it); record the slice again instead of editing meta.json' \
    "$s" "$bad" | vetdd_printable)" 1
  while IFS= read -r -d '' f; do oracles+=("$f"); done \
    < <(jq -j '[.oracle.files[]? | .path | strings] | .[] | . + "\u0000"' "$root/.vetdd/evidence/$s/meta.json" 2>/dev/null)
done
# Staged with content against HEAD (or against nothing, before the first commit); an intent-to-add
# entry (git add -N) has none, so it is not here.
staged=()
while IFS= read -r -d '' f; do staged+=("$f"); done \
  < <(git -C "$root" diff --cached --no-renames --name-only --diff-filter=A -z)
tmpd="$(mktemp -d "${TMPDIR:-/tmp}/judge-layout.XXXXXX")" || die "cannot create a temporary directory" 1
trap 'rm -rf "$tmpd"' EXIT
idx="$tmpd/index"
if git -C "$root" rev-parse --verify -q HEAD >/dev/null; then
  GIT_INDEX_FILE="$idx" git -C "$root" read-tree HEAD || die "could not read HEAD into a temporary index" 1
else
  GIT_INDEX_FILE="$idx" git -C "$root" read-tree --empty || die "could not make a temporary index" 1
fi
newfiles=(); unnamed=(); envs=()
# The list: the untracked files, the staged ones, and each oracle file of a slice not in HEAD, even
# when .gitignore matches it (#63), since the judge reads the tests in the diff; one ls-files call
# per oracle path, so a bad one drops only itself; only a regular file, so a directory never brings
# the ignored files under it. No comment inside the list: bash 3.2 misreads an
# apostrophe in a comment within a process substitution.
while IFS= read -r -d '' f; do
  case "$f" in .vetdd|.vetdd/*) continue ;; esac
  # A file staged and then removed is not in the delivered tree.
  [ -e "$root/$f" ] || [ -L "$root/$f" ] || continue
  if is_env "$f"; then envs+=("$f"); continue; fi
  newfiles+=("$f")
  ok=0
  for o in ${staged[@]+"${staged[@]}"} ${oracles[@]+"${oracles[@]}"} ${news[@]+"${news[@]}"}; do [ "$o" = "$f" ] && ok=1; done
  [ "$ok" -eq 1 ] || unnamed+=("$f")
done < <({ GIT_INDEX_FILE="$idx" git -C "$root" ls-files --others --exclude-standard -z
           [ ${#staged[@]} -eq 0 ] || printf '%s\0' "${staged[@]}"
           for o in ${oracles[@]+"${oracles[@]}"}; do
             [ -f "$root/$o" ] && [ ! -L "$root/$o" ] || continue
             GIT_LITERAL_PATHSPECS=1 GIT_INDEX_FILE="$idx" git -C "$root" ls-files --others -z -- "$o" 2>/dev/null
           done; } | LC_ALL=C sort -zu)
# An oracle file is copied whole, ignored or not: a .env among them is refused here too (once, when
# the list above already took it).
for o in ${oracles[@]+"${oracles[@]}"}; do
  is_env "$o" || continue
  # An oracle path is a plain path (checked when the record was read), so it compares as git spells it.
  dup=0; for e in ${envs[@]+"${envs[@]}"}; do [ "$e" = "$o" ] && dup=1; done
  [ "$dup" -eq 1 ] || envs+=("$o")
done
[ ${#envs[@]} -eq 0 ] \
  || die "$(printf 'a .env file may hold secrets and never goes to the judge:%s\nunstage it (git rm --cached <path>), or move it out of the repository or into .gitignore' \
    "$(printf ' %s' "${envs[@]}")" | vetdd_printable)"
# A new oracle file git did not list (behind a symbolic link, say) would be copied to artifact/tests
# but be missing from the diff, as in #63: stop instead. A path that is not a regular file of the
# repository is left to the copy below, which refuses it as missing, a link, or outside.
for o in ${oracles[@]+"${oracles[@]}"}; do
  case "$o" in .vetdd|.vetdd/*) continue ;; esac
  vetdd_inside_repo "$root" "$o" && [ -f "$root/$o" ] || continue
  # A file of another repository (a submodule, a nested one) was never in this diff: copied only, as before.
  [ "$(git -C "$(dirname -- "$root/$o")" rev-parse --show-toplevel 2>/dev/null)" = "$root" ] || continue
  GIT_LITERAL_PATHSPECS=1 GIT_INDEX_FILE="$idx" git -C "$root" ls-files --error-unmatch -- "$o" >/dev/null 2>&1 && continue
  ok=0; for f in ${newfiles[@]+"${newfiles[@]}"}; do [ "$f" = "$o" ] && ok=1; done
  [ "$ok" -eq 1 ] || die "$(printf 'oracle file %s is new, but git does not list it as a file of this repository (it is behind a symbolic link, say), so the diff would leave it out' "$o" | vetdd_printable)"
done
for n in ${news[@]+"${news[@]}"}; do
  ok=0; for f in ${newfiles[@]+"${newfiles[@]}"}; do [ "$f" = "$n" ] && ok=1; done
  [ "$ok" -eq 1 ] || die "--include-new $(printf '%s' "$n" | vetdd_printable): not a new file of this repository (give its path from the repository root, as git status --untracked-files=all shows it)"
done
# The flags for the first 20; more than that is usually build output that belongs in .gitignore.
if [ ${#unnamed[@]} -gt 0 ]; then
  flags=""; i=0
  for f in "${unnamed[@]}"; do
    [ "$i" -lt 20 ] || break
    flags="$flags --include-new $(printf '%q' "$f")"; i=$((i + 1))
  done
  more=""; [ ${#unnamed[@]} -le 20 ] || more="$(printf '\n... and %s more; put build output and scratch directories in .gitignore' "$((${#unnamed[@]} - 20))")"
  die "$(printf 'untracked new files would leave the machine in the diff; name each one a human allowed to leave with these flags, and delete the others:\n%s%s' \
    "$flags" "$more" | vetdd_printable)"
fi
for f in ${newfiles[@]+"${newfiles[@]}"}; do
  # -f: a file the repository's index added with git add -f, or a slice's oracle file (#63), may be ignored.
  GIT_LITERAL_PATHSPECS=1 GIT_INDEX_FILE="$idx" git -C "$root" add -f --intent-to-add -- "$f" \
    || die "could not add $(printf '%s' "$f" | vetdd_printable) to the temporary index" 1
  # Every new file leaves the machine in the diff: name each one, so the caller can see what goes out.
  printf 'judge-layout.sh: new file in the diff: %s\n' "$f" | vetdd_printable >&2
done
# Plumbing-stable output: no color, no textconv, the a/ b/ prefixes whatever the user's config says.
diffopts=(--no-ext-diff --no-color --no-textconv --src-prefix=a/ --dst-prefix=b/)
# The diff runs from --base, not HEAD: a .env committed in between, or a tracked one changed, is in it.
envs=()
while IFS= read -r -d '' f; do ! is_env "$f" || envs+=("$f"); done \
  < <(GIT_INDEX_FILE="$idx" git -C "$root" diff "${diffopts[@]}" --name-only -z --no-renames --end-of-options "$base" -- . ':(exclude).vetdd')
[ ${#envs[@]} -eq 0 ] \
  || die "$(printf 'a .env file may hold secrets and never goes to the judge, and the diff from --base changes:%s\nleave it out of the delivered change, or take a --base after it' \
    "$(printf ' %s' "${envs[@]}")" | vetdd_printable)"
# A binary change would go out as base85 text, which neither check-blind nor the secret check reads.
# -z: paths as they are (not quoted by core.quotePath); --no-renames: a renamed file under its new name.
unallowed=""
while IFS= read -r -d '' rec; do
  added="${rec%%$'\t'*}"; rest="${rec#*$'\t'}"; removed="${rest%%$'\t'*}"; path="${rest#*$'\t'}"
  [ "$added" = - ] && [ "$removed" = - ] || continue
  ok=0; for b in ${binaries[@]+"${binaries[@]}"}; do [ "$b" = "$path" ] && ok=1; done
  [ "$ok" -eq 1 ] || unallowed="$unallowed $path"
done < <(GIT_INDEX_FILE="$idx" git -C "$root" diff "${diffopts[@]}" --numstat -z --no-renames --end-of-options "$base" -- . ':(exclude).vetdd')
[ -z "$unallowed" ] || die "binary changes in the diff:$(printf '%s' "$unallowed" | vetdd_printable); name each one a human allowed to leave with --allow-binary <path>"
# A planted red's patch (calibrate.sh plant and planted) goes with its log, so it gets the diff's
# rules: it must match the sha256 its record holds (check-evidence rule 12), a .env file in it never
# goes, a binary change in it only when named with --allow-binary, a file git ignores now never, and a
# file not in HEAD only when it goes in the diff as a new file. A file the diff does not change is
# named on stderr (its planted lines leave with the patch). Paths are read as git reads the patch (and
# - - for a binary change); a missing patch stops the copy below.
PLANTED_SENT='
[.runs[] | select(type == "object" and (.kind == "before" or .kind == "calibration") and .outcome == "target_failure"
                  and (.audit.kind? // "") != "mutation" and has("planted") and (.seq | type) == "number")
 | "runs/" + (.seq | floor | tostring | if length < 3 then ("00" + .)[-3:] else . end) + "-planted.patch"
   + "\t" + (.planted.sha256? | if type == "string" then . else "-" end)] | .[]'
penvs=""; pbins=""; pgone=""
indiff="$tmpd/indiff"
GIT_INDEX_FILE="$idx" git -C "$root" diff "${diffopts[@]}" --name-only -z --no-renames --end-of-options "$base" -- . ':(exclude).vetdd' > "$indiff" \
  || die "git diff failed" 1
for s in "${slices[@]}"; do
  plist="$(jq -r "$PLANTED_SENT" "$root/.vetdd/evidence/$s/meta.json" 2>/dev/null)" \
    || die "could not read the evidence of slice $s (its meta.json is malformed)" 1
  while IFS="$(printf '\t')" read -r p psum; do
    [ -n "$p" ] || continue
    rel=".vetdd/evidence/$s/$p"
    vetdd_inside_repo "$root" "$rel" && [ -f "$root/$rel" ] || continue  # missing: the copy below stops on it
    [ "$(vetdd_sha256 "$root/$rel")" = "$psum" ] \
      || die "$(printf 'the planted patch %s of slice %s does not match the sha256 its record holds (check-evidence rule 12); take the red again (calibrate.sh plant and planted)' "$p" "$s" | vetdd_printable)" 1
    nslist="$tmpd/planted-numstat"
    git -C "$root" -c apply.whitespace=nowarn apply --numstat -z -- "$root/$rel" > "$nslist" 2>/dev/null \
      || die "$(printf 'the planted patch %s of slice %s cannot be read as a patch; take the red again (calibrate.sh plant and planted)' "$p" "$s" | vetdd_printable)" 1
    while IFS= read -r -d '' rec; do
      added="${rec%%$'\t'*}"; rest="${rec#*$'\t'}"; removed="${rest%%$'\t'*}"; path="${rest#*$'\t'}"
      if is_env "$path"; then penvs="$penvs $s:$path"; continue; fi
      rc=0; GIT_LITERAL_PATHSPECS=0 git -C "$root" check-ignore -q --no-index -- "./$path" 2>/dev/null || rc=$?
      [ "$rc" -le 1 ] || die "$(printf 'git check-ignore failed on %s of a planted patch (exit %s)' "$path" "$rc" | vetdd_printable)" 1
      [ "$rc" -ne 0 ] || { pgone="$pgone $path (git ignores it now)"; continue; }
      if ! GIT_LITERAL_PATHSPECS=1 git -C "$root" cat-file -e "HEAD:$path" 2>/dev/null; then
        ok=0; for f in ${newfiles[@]+"${newfiles[@]}"}; do [ "$f" = "$path" ] && ok=1; done
        [ "$ok" -eq 1 ] || { pgone="$pgone $path (not in HEAD and not a new file of the diff)"; continue; }
      fi
      if ! tr '\0' '\n' < "$indiff" | grep -qxF -- "$path"; then
        printf 'judge-layout.sh: the planted patch of slice %s holds lines of %s, which the diff does not change\n' "$s" "$path" | vetdd_printable >&2
      fi
      [ "$added" = - ] && [ "$removed" = - ] || continue
      ok=0; for b in ${binaries[@]+"${binaries[@]}"}; do [ "$b" = "$path" ] && ok=1; done
      [ "$ok" -eq 1 ] || pbins="$pbins $path"
    done < "$nslist"
  done <<< "$plist"
done
[ -z "$penvs" ] || die "$(printf 'a .env file may hold secrets and never goes to the judge, and a planted patch holds one:%s\ntake that red again with the defect planted in another file' "$penvs" | vetdd_printable)"
[ -z "$pgone" ] || die "$(printf 'a planted patch holds a file that does not go to the judge:%s\ntake that red again with the defect planted in a file that goes' "$pgone" | vetdd_printable)"
[ -z "$pbins" ] || die "binary changes in a planted patch:$(printf '%s' "$pbins" | vetdd_printable); name each one a human allowed to leave with --allow-binary <path>"
# The verify artifacts, all checked before anything is written: each --verify-artifacts path is a plain
# path at or under .vetdd/artifacts/ (where the verify scripts write them), inside the repository with
# no link on the way; every entry below it must be a directory or a regular file, and no .env file.
# A file that is not text stays: check-blind would stop the layout on it, unread (a screenshot).
# first_link <rel>: print the first component of <rel> (a path from the repository root) that is a
# symbolic link, and succeed; fail when none is.
first_link() {
  local c="" rest="$1/"
  while [ -n "$rest" ]; do
    c="$c${rest%%/*}"; rest="${rest#*/}"
    [ ! -L "$root/$c" ] || { printf '%s' "$c"; return 0; }
    c="$c/"
  done
  return 1
}
vsrc=(); ferr=0
for v in ${varts[@]+"${varts[@]}"}; do
  vp="--verify-artifacts $(printf '%s' "$v" | vetdd_printable)"
  case "$v" in .vetdd/artifacts|.vetdd/artifacts/?*) ;; *) die "$vp: give a path from the repository root at or under .vetdd/artifacts/" ;; esac
  case "/$v/" in *//*|*/./*|*/../*) die "$vp: give a plain path at or under .vetdd/artifacts/ (no //, ./, ../, or trailing /)" ;; esac
  # No link on the way, not even one that stays inside the repository (latest -> ../../src): what is
  # sent is what lies under .vetdd/artifacts/ by name.
  if c="$(first_link "$v")"; then
    die "$vp: $(printf '%s' "$c" | vetdd_printable) is a symbolic link; give the directory it names, under .vetdd/artifacts/"
  fi
  vetdd_inside_repo "$root" "$v" && { [ -d "$root/$v" ] || { [ -f "$root/$v" ] && [ "$v" != .vetdd/artifacts ]; }; } \
    || die "$vp: not a directory or regular file under .vetdd/artifacts/ of this repository (missing, or outside)"
  # Listed into a file first, so a find that could not read a directory stops the build instead of
  # leaving the files below it out unseen.
  vlist="$tmpd/verify-artifacts"
  find "$root/$v" -print0 > "$vlist" 2>/dev/null || ferr=1
  while IFS= read -r -d '' f; do
    rel="${f#"$root"/}"
    if [ -L "$f" ] || { [ ! -f "$f" ] && [ ! -d "$f" ]; }; then
      die "$vp: $(printf '%s' "$rel" | vetdd_printable) is a symbolic link or not a regular file; only files and directories go to the judge"
    fi
    # A name with a control character (a newline) would split the lists below: the oracle files' rule.
    vetdd_inside_repo "$root" "$rel" \
      || die "$vp: $(printf '%s' "$rel" | vetdd_printable) has a control character in its name; rename it"
    # check-blind refuses these names in a judge input (exit 4, after the layout is written): stop here.
    case "$(printf '%s' "${rel##*/}" | tr '[:upper:]' '[:lower:]')" in
      .git|node_modules) die "$vp: $(printf '%s' "$rel" | vetdd_printable) is named .git or node_modules, which never goes to the judge; give the artifact paths below it that matter" ;;
    esac
    # An unreadable file would pass for one that is not text, and an unreadable directory would hide
    # what is below it: either way the judge would get less than the reply cites.
    if [ ! -r "$f" ] || { [ -d "$f" ] && [ ! -x "$f" ]; }; then
      die "$vp: $(printf '%s' "$rel" | vetdd_printable) cannot be read; make it readable (chmod u+r, and u+x for a directory) or leave it out"
    fi
    [ -f "$f" ] || continue
    ! is_env "$rel" || die "$vp: $(printf '%s' "$rel" | vetdd_printable) is a .env file, which may hold secrets and never goes to the judge"
    if vetdd_is_text "$f"; then
      vsrc+=("$rel")
    else
      printf 'judge-layout.sh: verify artifact left on the machine (not text, which the blind check of the judge input cannot read): %s\n' "$rel" | vetdd_printable >&2
    fi
  done < "$vlist"
  [ "${ferr:-0}" -eq 0 ] || die "$vp: find could not list all of it (a directory below it cannot be read); make it readable or leave it out"
done

# The missing directories, then --out itself, one level at a time and each new (no -p, so nothing put
# there in the meantime is followed), private to the user (umask 077).
a="${d%/}"; rest="${tail#/}"
while [ "${rest#*/}" != "$rest" ]; do
  a="$a/${rest%%/*}"; rest="${rest#*/}"
  mkdir -- "$a" || die "cannot create $(printf '%s' "$a" | vetdd_printable)" 1
done
mkdir -- "$abs" || die "--out $(printf '%s' "$abs" | vetdd_printable) exists or cannot be created; give a new directory"
C="$out/c1"
mkdir -p "$C/artifact/tests" || die "cannot create $out" 1
GIT_INDEX_FILE="$idx" git -C "$root" diff "${diffopts[@]}" --binary --end-of-options "$base" -- . ':(exclude).vetdd' > "$C/artifact/diff.patch" \
  || die "git diff failed" 1

cp -- "$reply" "$C/artifact/reply.md" || die "cannot copy the reply" 1
for f in ${vsrc[@]+"${vsrc[@]}"}; do
  dst="$C/artifact/verify-artifacts/${f#.vetdd/artifacts/}"
  # Checked again right before the copy (the app may still write there); -P copies a link as a link,
  # which check-blind then refuses, never the file it points to.
  ! first_link "$f" >/dev/null && vetdd_inside_repo "$root" "$f" && [ -f "$root/$f" ] \
    || die "the verify artifact $(printf '%s' "$f" | vetdd_printable) changed since it was checked (now missing, behind a link, or not a regular file)" 1
  mkdir -p -- "$(dirname -- "$dst")" && cp -P -- "$root/$f" "$dst" || die "cannot copy the verify artifact $(printf '%s' "$f" | vetdd_printable)" 1
done

ce_rc=0
# A layout built before Close says so first: a final judge never reads an OK that skipped the audit.
[ ${#ce_opts[@]} -eq 0 ] || printf 'mode: before-close (the mutation audit is not due yet)\n' > "$C/artifact/check-evidence.txt"
(cd "$root" && "$here/check-evidence.sh" ${ce_opts[@]+"${ce_opts[@]}"} "${slices[@]}") >> "$C/artifact/check-evidence.txt" 2>&1 || ce_rc=$?
printf 'exit %s\n' "$ce_rc" >> "$C/artifact/check-evidence.txt"
# 126 and 127: check-evidence.sh did not run; the judge would read a FAIL that is not one.
[ "$ce_rc" -lt 126 ] || die "check-evidence.sh could not run (exit $ce_rc)" 1

# The files to send for one slice, read from its record before anything is copied: a record that cannot
# be read stops the build (exit 1) rather than ship an empty layout.
SEND='
def green: .kind == "after" or .kind == "integrated";
def oid: {v: (.oracle.version // null), f: ((.oracle.files // []) | map({path, sha256}) | sort_by(.path))};
# The check before anything is written (see oracle_ok there) already refuses a run whose oracle is
# not null or an object; usable keeps also refusing one with no oracle, so the two stay in step.
def usable: (.oracle | type) == "object" and (.oracle.files | type) == "array";
[.runs[] | select(.accepted != false)] as $all
| [$all[] | select(usable)] as $acc
| ($acc | map(select(green and .outcome == "pass")) | sort_by(.seq) | last) as $g
| ([.oracle.files[]? | .path | strings] | map("O\t" + .))
  + ([$all[] | select((.kind == "before" or .kind == "calibration") and .outcome == "target_failure"
                      and (.audit.kind? // "") != "mutation")
       # A planted red goes with what was planted, named from its own seq (check-evidence rule 12).
       | (.log | strings), (select(has("planted") and (.seq | type) == "number")
                            | "runs/" + (.seq | floor | tostring | if length < 3 then ("00" + .)[-3:] else . end) + "-planted.patch")]
     | map("L\t" + .))
  + (if $g == null then [] else
       ([$acc[] | select(.kind == "calibration" and .audit.kind? == "mutation" and .seq > $g.seq and oid == ($g | oid))]
        | sort_by(.seq) | last) as $m
       | if $m != null and $m.audit.report.status? == "ok"
         then ["M\t" + ("runs/" + ($m.seq | tostring | if length < 3 then ("00" + .)[-3:] else . end) + "-mutation.json")]
         else [] end
     end)
| .[]'

for s in "${slices[@]}"; do
  meta="$root/.vetdd/evidence/$s/meta.json"
  list="$(jq -r "$SEND" "$meta" 2>/dev/null)" || die "could not read the evidence of slice $s (its meta.json is malformed)" 1
  mkdir -p "$C/evidence/$s/runs" || die "cannot create $C/evidence/$s" 1
  cp -- "$meta" "$C/evidence/$s/meta.json" || die "cannot copy the evidence of $s" 1
  while IFS="$(printf '\t')" read -r what p; do
    [ -n "$what" ] || continue
    case "$what" in
      O)
        vetdd_inside_repo "$root" "$p" && [ -f "$root/$p" ] \
          || die "oracle file of $s is missing, a link, or outside the repository: $(printf '%s' "$p" | vetdd_printable)" 1
        mkdir -p "$C/artifact/tests/$(dirname -- "$p")" && cp -- "$root/$p" "$C/artifact/tests/$p" || die "cannot copy an oracle file" 1 ;;
      L|M)
        # Named only by the runs/<seq>-<kind> pattern, and read only from inside the repository.
        # A red-run log the record names must be there: without it the judge cannot see why the oracle failed.
        bad="the record of $s names $(printf '%s' "$p" | vetdd_printable), which"
        case "$p" in runs/[0-9][0-9][0-9]*-*.log|runs/[0-9][0-9][0-9]*-mutation.json|runs/[0-9][0-9][0-9]*-planted.patch) ;; *) die "$bad is not a runs/<seq>-<kind> file" 1 ;; esac
        case "$p" in */../*|*/./*) die "$bad is not a runs/<seq>-<kind> file" 1 ;; esac
        rel=".vetdd/evidence/$s/$p"
        vetdd_inside_repo "$root" "$rel" && [ -f "$root/$rel" ] || die "$bad is missing, a link, or outside the repository" 1
        cp -- "$root/$rel" "$C/evidence/$s/$p" || die "cannot copy $p of $s" 1 ;;
    esac
  done <<< "$list"
done

# Absolute paths of this machine never go to the judge: each spelling of a swarm worker's worktree
# (<root>.vetdd-wt/<slice>) and of the repository's path (and of the main repository's, when built in
# a linked worktree), then of the user's home directory, each also JSON-escaped and percent-encoded (a
# file:// URL: only what a URL must encode, as Node's pathToFileURL does, or everything but the
# unreserved characters), only as a whole path: after file://, after a character that is not part of a
# path, or right after a color code (ESC[...m, raw or JSON-escaped), an escaped newline or tab (\n,
# \r, \t), a one-letter option (-I, -L), or the - of a removed line of the diff; followed by /, the
# end, a period that ends a sentence, or a character that is not part of a name. A longer path that
# only contains it (/mnt<root>) is kept.
home_phys="$(cd -P -- "${HOME:-/}" 2>/dev/null && pwd -P)" || home_phys=""
case "$home_phys" in /private/*) home_short="${home_phys#/private}" ;; *) home_short="" ;; esac
home_log="${HOME:-}"; home_log="${home_log%/}"
# A HOME in a shared place would turn other paths there into <home>: leave those alone.
case "$home_phys" in
  ""|/|/tmp|/private/tmp|/var|/private/var|/var/tmp|/private/var/tmp|/var/folders|/private/var/folders|/private|/etc|/private/etc \
  |/usr|/usr/local|/opt|/srv|/home|/Users|/Users/Shared|/mnt|/media|/Volumes)
    home_phys=""; home_short=""; home_log="" ;;
esac
# The name a .claude directory is sent as: .agent, or the first of .agent2, .agent3, ... that appears
# nowhere in what is sent, in any letter case (a case-insensitive disk takes .AGENT for .agent): as a
# name below <dir>, or in text as a path component (followed by /, the end, a period that ends a
# sentence, or a character that is not part of a name), so two paths never become one.
tok=.agent; n=1
while [ -n "$(find "$out" -mindepth 1 -iname "$tok" -print 2>/dev/null | head -n 1)" ] \
      || LC_ALL=C grep -rIqiE '(^|[^[:alnum:]_.])\.'"${tok#.}"'(\\?/|\.([^[:alnum:]_-]|$)|[^[:alnum:]_.-]|$)' "$out"; do
  n=$((n + 1)); tok=".agent$n"
done
# -mindepth 1: <dir> itself keeps its name, whatever it is.
find "$out" -mindepth 1 -depth -type d -name .claude | while IFS= read -r d; do
  mv -- "$d" "$(dirname -- "$d")/$tok" || exit 1
done || die "could not rename a .claude directory in the layout" 1
# A .claude path component (also JSON-escaped, on a removed line of the diff, and at the end of a path
# or a sentence) goes under the free name chosen above: in text, and in the --allow-secrets and
# --allow-words globs, which check-blind matches against the renamed paths.
renamed() { printf '%s' "$1" | TOK="$tok" perl -pe "$RENAME"; }
find "$out" -type f -print0 | while IFS= read -r -d '' f; do
  LC_ALL=C grep -Iq . "$f" 2>/dev/null || continue
  ROOT="$root" LROOT="$logical_root" SROOT="$short_root" MROOT="$main_root" MSROOT="$main_short" H1="$home_phys" H2="$home_short" H3="$home_log" TOK="$tok" perl -pi -e '
    BEGIN {
      # What a URL path must encode (controls, space, " # % < > ? ` { } \, and every byte past ASCII),
      # and everything but the unreserved characters and /.
      sub enc_url { (my $e = $_[0]) =~ s{([\x00-\x20"#%<>?`{}\\\x7f-\xff])}{sprintf("%%%02X", ord $1)}ge; $e }
      sub enc_all { (my $e = $_[0]) =~ s{([^A-Za-z0-9\-._~/])}{sprintf("%%%02X", ord $1)}ge; $e }
      sub spell { my %s; sort { length($b) <=> length($a) } grep { length && !$s{$_}++ }
                  map { ($_, do { (my $e = $_) =~ s{/}{\\/}g; $e }) } map { ($_, enc_url($_), enc_all($_)) } grep { length } @_ }
      @R = spell(@ENV{qw(ROOT LROOT SROOT MROOT MSROOT)}); @H = spell(@ENV{qw(H1 H2 H3)});
      $L = qr{(?:\e\[[0-9;]*m|\\u001[bB]\[[0-9;]*m|(?<=\\[nrt])|(?<=^-)|(?<=^-[A-Za-z])|(?<=[\s"\x27=,(]-[A-Za-z])|(?<=file://)|(?<=file:\\/\\/)|(?<![\w.\-/\\]))};
      $B = qr{(?=/|\\/|\.(?![\w-])|[^\w.-]|$)};
    }
    # A swarm worker ran in <root>.vetdd-wt/<slice> (worktree.sh): its logs name that path.
    for my $r (@R) { s{$L\K\Q$r\E\.vetdd-wt(?:/|\\/)[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9_-])?$B}{<repo>}g }
    for my $r (@R) { s{$L\K\Q$r\E\.vetdd-wt$B}{<worktrees>}g }
    for my $r (@R) { s{$L\K\Q$r\E$B}{<repo>}g }
    for my $r (@H) { s{$L\K\Q$r\E$B}{<home>}g }
    '"$RENAME" "$f" || exit 1
done || die "could not replace the paths of this machine" 1

allow_args=(); allow_out=(); awords_out=()
for a in ${allow[@]+"${allow[@]}"}; do allow_out+=("$(renamed "$a")"); done
for a in ${awords[@]+"${awords[@]}"}; do awords_out+=("$(renamed "$a")"); done
for a in ${allow_out[@]+"${allow_out[@]}"}; do allow_args+=(--allow-secrets "$a"); done
for a in ${awords_out[@]+"${awords_out[@]}"}; do allow_args+=(--allow-words "$a"); done
blind_rc=0
# One delivered change: variant and baseline are product words here (--final; winner stays checked),
# as judge.sh treats a final verdict. An arena lane (--lane) is compared with others, so all three
# stay checked, as there.
[ "$lane" -eq 1 ] || allow_args+=(--final)
blind="$("$here/check-blind.sh" "$out" --profile judge ${allow_args[@]+"${allow_args[@]}"} 2>&1)" || blind_rc=$?
if [ "$blind_rc" -eq 1 ]; then
  printf '%s\n' "$blind" | vetdd_printable >&2
  die "the layout is not blind (check-blind.sh above); fix the reply or the logs and build it again in a new directory" 4
elif [ "$blind_rc" -ne 0 ]; then
  printf '%s\n' "$blind" | vetdd_printable >&2
  die "check-blind.sh could not run (exit $blind_rc)" 1
fi

printf 'judge-layout.sh: built %s\n' "$out"
printf 'next: %q --rubric %q --candidates %q --out <judge.json> --eval-id <id> --run-id <id> --rubric-version <n>' \
  "$here/judge.sh" "${here%/scripts}/references/final-judge-rubric.md" "$out"
for a in ${allow_out[@]+"${allow_out[@]}"}; do printf ' --allow-secrets %q' "$a"; done
for a in ${awords_out[@]+"${awords_out[@]}"}; do printf ' --allow-words %q' "$a"; done
printf '\n'
