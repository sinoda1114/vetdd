#!/usr/bin/env bash
# Build the final judge's directory that references/final-judge-rubric.md "Layout" defines (test and
# verify modes, Close), so it is never assembled by hand.
# Usage: judge-layout.sh --out <dir> --reply <file> --base <git ref> [--allow-secrets <glob>[:<kind>,...]]...
#                        [--allow-binary <path>]... [--before-close] <slice-id>...
#   --before-close: check-evidence.sh runs with it (an arena lane, laid out before its Close: the
#   mutation audit is not due yet), as arena-layout.sh's gate does
#   <dir>/c1/artifact/diff.patch          git diff --no-ext-diff --binary <base> on the working tree, every
#                                         file not in HEAD (untracked or staged) outside .vetdd/ included
#                                         through a temporary index (the repository's own index is untouched)
#   <dir>/c1/artifact/reply.md            the reply draft (<file>)
#   <dir>/c1/artifact/check-evidence.txt  check-evidence.sh <slices>, then a last line "exit <code>"
#   <dir>/c1/artifact/tests/<path>        each file in the slices' oracle.files, as it is now
#   <dir>/c1/evidence/<slice>/meta.json   each slice's record
#   <dir>/c1/evidence/<slice>/runs/...    its red-run logs (accepted before or calibration runs that ended
#                                         target_failure, the undefined-imports audit included, the mutation
#                                         audit not) and the copy of the mutation report check-evidence rule
#                                         10c judges (the latest mutation run after the final green, of the
#                                         final oracle, when its report is usable); green logs stay here
# <dir> must be outside the repository or under its .vetdd/ (anywhere else, its own files would change
# the tree check-evidence hashes). Every copied text file has the repository's absolute path, as a whole
# path, replaced with <repo>, and the user's home directory with <home> (unless HOME is a shared place
# such as /tmp); a .claude directory (where verify mode keeps its skill) is renamed .agent, in names and
# text alike, since the judge must not see the author's tool (.agent2, .agent3, ... when that name is
# already in what is sent, so two paths never become one); then check-blind.sh --profile judge runs on
# <dir>, with each
# --allow-secrets (paths relative to <dir>, e.g. c1/artifact/tests/*:email, only for test data a human
# confirmed), which the printed judge.sh command repeats. Run it on the delivered tree.
# Exit 0 built (it prints the judge.sh command); 1 a local step failed (a record could not be read,
# check-blind could not run); 2 usage error, or a binary file in the diff not named with --allow-binary
# (nothing is written; git's base85 text of a binary file passes the blind and secret checks unseen);
# 4 the result is not blind
# (check-blind.sh's hits are printed; <dir> is left to inspect, readable by the user only).
# Everything written is private to the user (umask 077), and <dir> must be new, under directories only
# the user or root can change (or sticky ones), so no other user can read it or swap it before the judge.
set -u
unset CDPATH GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_ICASE_PATHSPECS
umask 077

die() { printf 'judge-layout.sh: %s\n' "$1" >&2; exit "${2:-2}"; }

here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
. "$here/lib/common.sh"
vetdd_require_jq judge-layout.sh

out=""; reply=""; base=""; slices=(); allow=(); binaries=(); ce_opts=()
while [ $# -gt 0 ]; do
  case "$1" in
    --out) [ $# -ge 2 ] || die "--out needs a directory"; out="$2"; shift 2 ;;
    --reply) [ $# -ge 2 ] || die "--reply needs a file"; reply="$2"; shift 2 ;;
    --base) [ $# -ge 2 ] || die "--base needs a git ref"; base="$2"; shift 2 ;;
    --allow-secrets) [ $# -ge 2 ] || die "--allow-secrets needs <glob>[:<kind>,...]"; allow+=("$2"); shift 2 ;;
    --allow-binary) [ $# -ge 2 ] || die "--allow-binary needs a repository path"; binaries+=("$2"); shift 2 ;;
    --before-close) ce_opts=(--before-close); shift ;;
    -*) die "unknown option: $(printf '%s' "$1" | vetdd_printable)" ;;
    *) slices+=("$1"); shift ;;
  esac
done
[ -n "$out" ] && [ -n "$reply" ] && [ -n "$base" ] && [ ${#slices[@]} -gt 0 ] \
  || die "usage: judge-layout.sh --out <dir> --reply <file> --base <git ref> [--allow-secrets <glob>[:<kind>,...]]... <slice-id>..."
[ -f "$reply" ] && [ ! -L "$reply" ] || die "--reply must be a regular file"
. "$here/lib/secret-patterns.sh"
for a in ${allow[@]+"${allow[@]}"}; do
  err="$(vetdd_allow_secret_error "$a")" || die "$(printf '%s' "$err" | vetdd_printable)"
done
[ ! -e "$out" ] && [ ! -L "$out" ] || die "--out $out exists; give a new directory"

root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
root="$(cd "$root" && pwd -P)"
# The spellings the repository's path can take in a log: its physical path, the same without a /private
# prefix (macOS links /var, /tmp, and /etc there), and the logical path the caller's shell shows.
prefix="$(git rev-parse --show-prefix 2>/dev/null)"; prefix="${prefix%/}"
logical_root="${PWD%/}"; [ -z "$prefix" ] || logical_root="${logical_root%/"$prefix"}"
case "$root" in /private/*) short_root="${root#/private}" ;; *) short_root="$root" ;; esac
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
# intent-to-add entries for every file not in it: untracked ones listed against that index, and files the
# repository's own index added (git add -f of an ignored file included).
tmpd="$(mktemp -d "${TMPDIR:-/tmp}/judge-layout.XXXXXX")" || die "cannot create a temporary directory" 1
trap 'rm -rf "$tmpd"' EXIT
idx="$tmpd/index"
if git -C "$root" rev-parse --verify -q HEAD >/dev/null; then
  GIT_INDEX_FILE="$idx" git -C "$root" read-tree HEAD || die "could not read HEAD into a temporary index" 1
else
  GIT_INDEX_FILE="$idx" git -C "$root" read-tree --empty || die "could not make a temporary index" 1
fi
while IFS= read -r -d '' f; do
  case "$f" in .vetdd|.vetdd/*) continue ;; esac
  # A file staged and then removed is not in the delivered tree.
  [ -e "$root/$f" ] || [ -L "$root/$f" ] || continue
  # -f: a file the repository's index added with git add -f is ignored; the untracked list has no ignored file.
  GIT_LITERAL_PATHSPECS=1 GIT_INDEX_FILE="$idx" git -C "$root" add -f --intent-to-add -- "$f" \
    || die "could not add $(printf '%s' "$f" | vetdd_printable) to the temporary index" 1
  # Every new file leaves the machine in the diff: name each one, so the caller can see what goes out.
  printf 'judge-layout.sh: new file in the diff: %s\n' "$f" | vetdd_printable >&2
done < <({ GIT_INDEX_FILE="$idx" git -C "$root" ls-files --others --exclude-standard -z
             git -C "$root" diff --cached --no-renames --name-only --diff-filter=A -z HEAD 2>/dev/null; } | LC_ALL=C sort -zu)
# Plumbing-stable output: no color, no textconv, the a/ b/ prefixes whatever the user's config says.
diffopts=(--no-ext-diff --no-color --no-textconv --src-prefix=a/ --dst-prefix=b/)
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

ce_rc=0
(cd "$root" && "$here/check-evidence.sh" ${ce_opts[@]+"${ce_opts[@]}"} "${slices[@]}") > "$C/artifact/check-evidence.txt" 2>&1 || ce_rc=$?
printf 'exit %s\n' "$ce_rc" >> "$C/artifact/check-evidence.txt"
# 126 and 127: check-evidence.sh did not run; the judge would read a FAIL that is not one.
[ "$ce_rc" -lt 126 ] || die "check-evidence.sh could not run (exit $ce_rc)" 1

# The files to send for one slice, read from its record before anything is copied: a record that cannot
# be read stops the build (exit 1) rather than ship an empty layout.
SEND='
def green: .kind == "after" or .kind == "integrated";
def oid: {v: (.oracle.version // null), f: ((.oracle.files // []) | map({path, sha256}) | sort_by(.path))};
def usable: (.oracle | type) == "object" and (.oracle.files | type) == "array";
[.runs[] | select(.accepted != false)] as $all
| [$all[] | select(usable)] as $acc
| ($acc | map(select(green and .outcome == "pass")) | sort_by(.seq) | last) as $g
| ([.oracle.files[]? | .path | strings] | map("O\t" + .))
  + ([$all[] | select((.kind == "before" or .kind == "calibration") and .outcome == "target_failure"
                      and (.audit.kind? // "") != "mutation") | .log | strings] | map("L\t" + .))
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
        case "$p" in runs/[0-9][0-9][0-9]*-*.log|runs/[0-9][0-9][0-9]*-mutation.json) ;; *) die "$bad is not a runs/<seq>-<kind> file" 1 ;; esac
        case "$p" in */../*|*/./*) die "$bad is not a runs/<seq>-<kind> file" 1 ;; esac
        rel=".vetdd/evidence/$s/$p"
        vetdd_inside_repo "$root" "$rel" && [ -f "$root/$rel" ] || die "$bad is missing, a link, or outside the repository" 1
        cp -- "$root/$rel" "$C/evidence/$s/$p" || die "cannot copy $p of $s" 1 ;;
    esac
  done <<< "$list"
done

# Absolute paths of this machine never go to the judge: each spelling of a swarm worker's worktree
# (<root>.vetdd-wt/<slice>) and of the repository's path, then of
# the user's home directory, only as a whole path (after file:// or a character that is not part of a
# path; followed by /, the end, a period that ends a sentence, or a character that is not part of a name).
home_phys="$(cd -P -- "${HOME:-/}" 2>/dev/null && pwd -P)" || home_phys=""
case "$home_phys" in /private/*) home_short="${home_phys#/private}" ;; *) home_short="" ;; esac
home_log="${HOME:-}"; home_log="${home_log%/}"
# A HOME in a shared place would turn other paths there into <home>: leave those alone.
case "$home_phys" in ""|/|/tmp|/private/tmp|/var|/private/var|/var/tmp|/private/var/tmp) home_phys=""; home_short=""; home_log="" ;; esac
# The name a .claude directory is sent as: .agent, or the first of .agent2, .agent3, ... that appears
# nowhere in what is sent (as a name, or as a path component in text), so two paths never become one.
tok=.agent; n=1
while [ -n "$(find "$out" -name "$tok" -print 2>/dev/null | head -n 1)" ] \
      || LC_ALL=C grep -rIqE '(^|[^[:alnum:]_.])\.'"${tok#.}"'(\\)?/' "$out"; do
  n=$((n + 1)); tok=".agent$n"
done
find "$out" -depth -type d -name .claude | while IFS= read -r d; do
  mv -- "$d" "$(dirname -- "$d")/$tok" || exit 1
done || die "could not rename a .claude directory in the layout" 1
find "$out" -type f -print0 | while IFS= read -r -d '' f; do
  LC_ALL=C grep -Iq . "$f" 2>/dev/null || continue
  ROOT="$root" LROOT="$logical_root" SROOT="$short_root" H1="$home_phys" H2="$home_short" H3="$home_log" TOK="$tok" perl -pi -e '
    BEGIN { sub spell { my %s; sort { length($b) <=> length($a) } grep { length && !$s{$_}++ }
                        map { ($_, do { (my $e = $_) =~ s{/}{\\/}g; $e }) } @_ }
            @R = spell(@ENV{qw(ROOT LROOT SROOT)}); @H = spell(@ENV{qw(H1 H2 H3)}) }
    # A swarm worker ran in <root>.vetdd-wt/<slice> (worktree.sh): its logs name that path.
    for my $r (@R) { s{(?:(?<=file://)|(?<=file:\\/\\/)|(?<![\w.\-/\\]))\Q$r\E\.vetdd-wt(?:/|\\/)[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9_-])?(?=/|\\/|\.(?![\w-])|[^\w.-]|$)}{<repo>}g }
    for my $r (@R) { s{(?:(?<=file://)|(?<=file:\\/\\/)|(?<![\w.\-/\\]))\Q$r\E\.vetdd-wt(?=/|\\/|\.(?![\w-])|[^\w.-]|$)}{<worktrees>}g }
    for my $r (@R) { s{(?:(?<=file://)|(?<=file:\\/\\/)|(?<![\w.\-/\\]))\Q$r\E(?=/|\\/|\.(?![\w-])|[^\w.-]|$)}{<repo>}g }
    for my $r (@H) { s{(?:(?<=file://)|(?<=file:\\/\\/)|(?<![\w.\-/\\]))\Q$r\E(?=/|\\/|\.(?![\w-])|[^\w.-]|$)}{<home>}g }
    # A .claude directory, as a path component (also JSON-escaped, and on a removed line of the diff), is
    # sent under the free name chosen above.
    s{(?:(?<=^-)|(?<![\w.-]))\.claude(?=\\?/)}{$ENV{TOK}}g' "$f" || exit 1
done || die "could not replace the paths of this machine" 1

allow_args=()
for a in ${allow[@]+"${allow[@]}"}; do allow_args+=(--allow-secrets "$a"); done
blind_rc=0
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
for a in ${allow[@]+"${allow[@]}"}; do printf ' --allow-secrets %q' "$a"; done
printf '\n'
