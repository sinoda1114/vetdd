#!/usr/bin/env bash
# Copy one candidate workspace into a judge-ready, origin-free label directory (modes/eval.md, step 5).
# Usage: sanitize-candidates.sh --src <workspace> --label <cN> --dest <run-dir>/candidates
#                               [--strip <word>]... [--variants <variants.json>] [--transcript <file>]
#                               [--words-out <file>] [--allow-secrets <glob>[:<kind>[,<kind>]...]]...
#   <dest>/<label>/artifact/          the workspace without .git, node_modules, .vetdd, and secret-bearing
#                                     files (SECRET_EXCLUDES below: .env, .env.*, .npmrc, .ssh, *.pem, ...)
#   <dest>/<label>/evidence/          the workspace's .vetdd/evidence, when present, without the same
#                                     secret-bearing files
#   <dest>/<label>/transcript.jsonl   a copy of --transcript, when given
#   --words-out <file>                append the strip words (not the model names), one per line,
#                                     for check-blind.sh and judge.sh --extra-words
#   --allow-secrets <glob>[:<kind>[,<kind>]...]
#                                     passed to the self-check (check-blind.sh): paths of the copy
#                                     that match it, relative to <dest>/<label>, skip the secret
#                                     check for the kinds named (transcript.jsonl:email,
#                                     artifact/tests/*:email,assignment), or for every kind without
#                                     them. Only for test data a human confirmed, and only the kinds
#                                     confirmed.
# Every case-insensitive, whole-word occurrence of a strip word (the same boundaries check-blind.sh
# uses) in text contents, file names, and directory names under <dest>/<label> becomes "[redacted]".
# Strip words: the model names in lib/blind-words.sh, the workspace's basename, its git branch when
# the workspace is a repository root, every variant name (the values) in --variants, and every
# --strip word. A strip word must have at least 4 characters, must not start with "#" or begin or
# end with whitespace, and main, master, HEAD, and git's init.defaultBranch are never strip words
# (an explicit one is refused, a derived one skipped).
# With --variants or variants.json in the run directory (the parent of <dest>), as an A/B eval has
# it, absolute paths are redacted too, but not written to --words-out (judge.sh derives them
# itself): the run directory and its git toplevel, each both as `pwd` and as `pwd -P` prints it, and
# each also with every "/" written as JSON's "\/". Without either there is no label-to-variant map
# to hide and judge.sh refuses no path, so none is redacted. With --transcript, git's user.email
# (`git config --get user.email` here and
# in the workspace, when set) is redacted the same way and not written to --words-out either, so
# the committed blind-words.txt never holds an address.
# The source must not contain a symlink (outside .git and node_modules) or a file with more than
# one hard link (outside .git, node_modules, and .vetdd); it is refused, not copied.
# The source and <dest> must not contain each other.
# The copy is built in a temporary directory inside <dest> and must pass
# check-blind.sh --profile judge with the strip words; only then does it replace <dest>/<label>
# (publish). On any failure or interruption <dest>/<label> is left as it was. Prints <dest>/<label>.
# All error output passes through vetdd_printable (no control characters reach the terminal).
# Exit: 0 done, 1 copy, rewrite, or self-check failed, 2 usage error (including a refused source or
# strip word).
set -u
unset CDPATH

here="${BASH_SOURCE[0]%/*}"
. "$here/lib/common.sh"
die() { printf 'sanitize-candidates.sh: %s\n' "$1" | vetdd_printable >&2; exit "${2:-2}"; }

. "$here/lib/blind-words.sh"
. "$here/lib/text.sh"
. "$here/lib/secret-patterns.sh"

MIN_STRIP_LEN=4
# The redaction placeholder; a strip word equal to it only ever remains inside "[redacted]".
PLACEHOLDER_WORD=redacted
NL=$'\n'
# Files that commonly hold credentials; never copied, at any depth (tar --exclude matches any
# path component, a glob matches the file name).
# .DS_Store is not a secret but a binary Finder file that the self-check would refuse.
SECRET_EXCLUDES=".env .env.* .npmrc .netrc .pypirc .envrc .dev.vars .aws .ssh *.pem *.key *.p12 *.pfx *.tfvars
  .git-credentials .pgpass .htpasswd credentials.json id_rsa id_ed25519 id_ecdsa terraform.tfstate *.tfstate
  .docker .kube .DS_Store"

src=""; label=""; dest=""; strip=(); paths=(); variants=""; transcript=""; words_out=""; allow_secrets=()
work=""; stage=""; old_copy=""

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --src) [ $# -ge 2 ] || die "--src needs a value"; src="$2"; shift 2 ;;
      --label) [ $# -ge 2 ] || die "--label needs a value"; label="$2"; shift 2 ;;
      --dest) [ $# -ge 2 ] || die "--dest needs a value"; dest="$2"; shift 2 ;;
      --strip) [ $# -ge 2 ] || die "--strip needs a value"; strip+=("$2"); shift 2 ;;
      --variants) [ $# -ge 2 ] || die "--variants needs a file"; variants="$2"; shift 2 ;;
      --transcript) [ $# -ge 2 ] || die "--transcript needs a file"; transcript="$2"; shift 2 ;;
      --words-out) [ $# -ge 2 ] || die "--words-out needs a file"; words_out="$2"; shift 2 ;;
      --allow-secrets) [ $# -ge 2 ] || die "--allow-secrets needs a glob"
        err="$(vetdd_allow_secret_error "$2")" || die "$err"
        allow_secrets+=("$2"); shift 2 ;;
      *) die "unexpected argument '$1'" ;;
    esac
  done
  [ -n "$src" ] && [ -n "$label" ] && [ -n "$dest" ] \
    || die "usage: sanitize-candidates.sh --src <workspace> --label <cN> --dest <dir> [--strip <word>]... [--variants <file>] [--transcript <file>] [--words-out <file>] [--allow-secrets <glob>[:<kind>,...]]..."
  case "$label" in c[0-9]*) ;; *) die "invalid label '$label' (c1, c2, ...)" ;; esac
  case "${label#c}" in ""|*[!0-9]*) die "invalid label '$label' (c followed by digits: c1, c2, ...)" ;; esac
  [ -d "$src" ] || die "workspace not found: $src"
  if [ -n "$transcript" ]; then
    [ ! -L "$transcript" ] || die "the transcript is a symlink; pass the file itself: $transcript"
    [ -f "$transcript" ] || die "transcript not found: $transcript"
  fi
}

check_paths() {
  src_abs="$(cd "$src" && pwd -P)" || die "cannot enter $src"
  mkdir -p "$dest" || die "cannot create $dest"
  dest_abs="$(cd "$dest" && pwd -P)" || die "cannot enter $dest"
  case "$dest_abs/" in "$src_abs"/*) die "--dest must be outside the workspace" ;; esac
  # Replacing <dest>/<label> would delete a source that lives there.
  case "$src_abs/" in "$dest_abs"/*) die "--src must be outside --dest" ;; esac
  out="${dest%/}/$label"
  [ -z "$words_out" ] || : >> "$words_out" || die "cannot write $words_out"

  [ ! -L "$src_abs/.vetdd" ] || die ".vetdd is a symlink; the evidence must be a directory inside the workspace"
  # A symlink can point outside the workspace; copying it would carry the target, or the link, into
  # the judge's input. Refuse instead of guessing.
  local links hard special
  links="$(
    find "$src_abs" \( -name .git -o -name node_modules -o -name .vetdd \) -prune -o -type l -print
    [ ! -e "$src_abs/.vetdd/evidence" ] && [ ! -L "$src_abs/.vetdd/evidence" ] \
      || find "$src_abs/.vetdd/evidence" -type l -print
  )"
  [ -z "$links" ] || refuse_list "the workspace contains symlinks; replace them with regular files first:" "$links"
  # A hard link is the same file under another name, possibly outside the workspace.
  hard="$(
    find "$src_abs" \( -name .git -o -name node_modules -o -name .vetdd \) -prune -o -type f -links +1 -print
    [ ! -d "$src_abs/.vetdd/evidence" ] || find "$src_abs/.vetdd/evidence" -type f -links +1 -print
  )"
  [ -z "$hard" ] \
    || refuse_list "the workspace contains hard links (files with more than one name); replace them with independent copies first:" "$hard"
  # A FIFO, socket, or device would be copied as is, and the judge could block reading it.
  special="$(
    find "$src_abs" \( -name .git -o -name node_modules -o -name .vetdd \) -prune -o ! -type f ! -type d ! -type l -print
    [ ! -d "$src_abs/.vetdd/evidence" ] || find "$src_abs/.vetdd/evidence" ! -type f ! -type d ! -type l -print
  )"
  [ -z "$special" ] \
    || refuse_list "the workspace contains special files (FIFOs, sockets, devices); remove them first:" "$special"
}

# refuse_list <message> <paths>: exit 2 with the message and each path, relative to the workspace.
refuse_list() {
  local msg="$1" l
  while IFS= read -r l; do msg="$msg
  ${l#"$src_abs"/}"; done <<< "$2"
  die "$msg"
}

# Words that must never be stripped: redacting them would mangle ordinary git text.
is_protected() {
  local w
  w="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
  case "$w" in main|master|head) return 0 ;; esac
  [ -n "$default_branch" ] && [ "$w" = "$(printf '%s' "$default_branch" | tr 'A-Z' 'a-z')" ]
}
# check_strip <word> <where>: refuse a word that is protected, too short, or one vetdd_word_file
# would change (it drops a line starting with "#" and trims surrounding whitespace), since such a
# word would be neither redacted nor checked as given.
check_strip() {
  case "$1" in
    '#'*|[[:space:]]*|*[[:space:]]|*"$NL"*) die "refusing to strip '$1' ($2): a strip word must not start with #, begin or end with whitespace, or span lines" ;;
  esac
  ! is_protected "$1" || die "refusing to strip '$1' ($2): main, master, HEAD, and init.defaultBranch are never strip words"
  [ "${#1}" -ge "$MIN_STRIP_LEN" ] \
    || die "refusing to strip '$1' ($2): strip words need at least $MIN_STRIP_LEN characters"
}

collect_strip_words() {
  default_branch="$(git config --get init.defaultBranch 2>/dev/null || true)"
  local w names base branch
  for w in ${strip[@]+"${strip[@]}"}; do check_strip "$w" "--strip"; done
  if [ -n "$variants" ]; then
    [ -f "$variants" ] || die "variants file not found: $variants"
    command -v jq >/dev/null 2>&1 || die "jq is required for --variants but not found"
    names="$(jq -r 'if type == "object" and all(.[]; type == "string" and (test("\n") | not))
                    then .[] else error("must be an object of one-line variant names") end' "$variants" 2>&1)" \
      || die "invalid variants file $variants: $names"
    while IFS= read -r w; do
      [ -z "$w" ] && continue
      check_strip "$w" "variant name in $variants"
      strip+=("$w")
    done <<< "$names"
  fi
  # Derived words: the workspace basename, its branch (only when src is the repository root).
  base="${src_abs##*/}"
  is_protected "$base" || { check_strip "$base" "the workspace name; rename the workspace"; strip+=("$base"); }
  if [ "$(git -C "$src_abs" rev-parse --show-toplevel 2>/dev/null)" = "$src_abs" ]; then
    branch="$(git -C "$src_abs" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    if [ -n "$branch" ] && ! is_protected "$branch"; then
      check_strip "$branch" "the workspace's branch; rename the branch"
      strip+=("$branch")
    fi
  fi
}

# collect_path_words: for an A/B eval (--variants, or variants.json in the run directory, the parent
# of <dest>), the run directory and its git toplevel, each as `pwd` and as `pwd -P` prints it. A
# transcript or a log names them. Otherwise none: judge.sh refuses paths only in the same case.
# The same paths as judge.sh's write_path_words.
collect_path_words() {
  local dest_l run_l run_p top top_p cdup d p list=()
  # The run directory is the parent of <dest> as written, even when <dest> is a symlink: judge.sh
  # takes the parent of --candidates the same way, so both look for variants.json and the git
  # toplevel in the same place.
  dest_l="$(cd "$dest" && pwd)" || die "cannot enter $dest"
  run_l="${dest_l%/*}"; [ -n "$run_l" ] || run_l="/"
  { [ -n "$variants" ] || [ -f "$run_l/variants.json" ]; } || return 0
  run_p="$(cd "$run_l" && pwd -P)" || die "cannot enter the parent of $dest"
  list=("$dest_l" "$dest_abs" "$run_l" "$run_p")
  if top="$(git -C "$run_l" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$top" ]; then
    top_p="$(cd "$top" && pwd -P)" && cdup="$(git -C "$run_l" rev-parse --show-cdup)" && [ -n "$top_p" ] \
      || die "cannot resolve the git toplevel of $run_l"
    list+=("$top" "$top_p")
    # The toplevel as the user wrote it: git's "../" steps count from the resolved path, so through
    # a symlink they may land elsewhere ($HOME, "/"); such a form is not the toplevel and is dropped.
    if d="$(cd "$run_l" && { [ -z "$cdup" ] || cd "$cdup"; } 2>/dev/null && pwd)" \
       && [ "$(cd "$d" 2>/dev/null && pwd -P)" = "$top_p" ]; then
      list+=("$d")
    fi
  fi
  # "/" would match every path; it is dropped, as judge.sh drops it.
  for p in "${list[@]}"; do
    [ "$p" != / ] || continue
    [ -n "$p" ] || die "cannot determine an absolute path of the run directory (the parent of $dest) to redact"
    # No check_strip: a path always starts with "/", is never a protected word, and may be short
    # (a repository mounted at /w in a container).
    paths+=("$p")
  done
  # A JSON string may write "/" as "\/" (\/Users\/x\/...); each path is a word in that form too.
  for p in ${paths[@]+"${paths[@]}"}; do paths+=("$(printf '%s' "$p" | sed 's|/|\\/|g')"); done
}

# collect_email: with --transcript, git's user.email, which a harness transcript carries: the one
# this script runs under and the one the workspace sees (its own repository may set another). Like
# the paths, they are redacted and self-checked but never written to --words-out.
collect_email() {
  local mine theirs
  [ -n "$transcript" ] || return 0
  mine="$(git config --get user.email 2>/dev/null || true)"
  theirs="$(git -C "$src_abs" config --get user.email 2>/dev/null || true)"
  if [ -n "$mine" ]; then check_strip "$mine" "git's user.email"; paths+=("$mine"); fi
  if [ -n "$theirs" ] && [ "$theirs" != "$mine" ]; then
    check_strip "$theirs" "the workspace's git user.email"
    paths+=("$theirs")
  fi
}

# tar_copy <from> <to> [<exclude>...]: copy the tree <from> into <to> without SECRET_EXCLUDES and
# the given names, at any depth.
tar_copy() {
  local from="$1" to="$2"
  shift 2
  mkdir -p "$to" || return 1
  # pipefail, so a file the archiver cannot read fails the copy instead of leaving it short.
  ( set -o pipefail
    local x excludes=()
    for x in "$@"; do excludes+=(--exclude "$x"); done
    set -f  # SECRET_EXCLUDES holds globs for tar, not for the shell
    for x in $SECRET_EXCLUDES; do excludes+=(--exclude "$x"); done
    set +f
    (cd "$from" && tar "${excludes[@]}" -cf - .) | (cd "$to" && tar -xf -) )
}

# copy_into <dir>: the workspace, its evidence, and the transcript.
copy_into() {
  tar_copy "$src_abs" "$1/artifact" .git node_modules .vetdd || die "copying $src failed" 1
  if [ -d "$src_abs/.vetdd/evidence" ]; then
    tar_copy "$src_abs/.vetdd/evidence" "$1/evidence" || die "copying the evidence failed" 1
  fi
  if [ -n "$transcript" ]; then
    cp "$transcript" "$1/transcript.jsonl" || die "copying the transcript failed" 1
  fi
}

# redact_tree <dir>: contents first, then names.
redact_tree() {
  local f p base new
  # Contents: text files only, rewritten in place (mode kept) only when something changed.
  while IFS= read -r -d '' f; do
    vetdd_is_text "$f" || continue
    vetdd_redact "$words" "$f" > "$work/redacted"
    case $? in
      0) cat "$work/redacted" > "$f" || die "cannot rewrite ${f#"$1"/}" 1 ;;
      3) ;;
      *) die "redacting ${f#"$1"/} failed" 1 ;;
    esac
  done < <(find "$1" -type f -print0)

  # Names: deepest first, so a parent is renamed after its children.
  while IFS= read -r -d '' p; do
    base="${p##*/}"
    printf '%s\n' "$base" > "$work/name"
    new="$(vetdd_redact "$words" "$work/name")"
    case $? in 0) ;; 3) continue ;; *) die "redacting the name ${p#"$1"/} failed" 1 ;; esac
    [ ! -e "${p%/*}/$new" ] || die "cannot rename ${p#"$1"/}: $new exists beside it" 1
    mv "$p" "${p%/*}/$new" || die "cannot rename ${p#"$1"/}" 1
  done < <(find "$1" -mindepth 1 -depth -print0)
}

# self_check <dir>: the copy must be blind for the judge before it is published.
self_check() {
  local hits
  local g args=()
  for g in ${allow_secrets[@]+"${allow_secrets[@]}"}; do args+=(--allow-secrets "$g"); done
  hits="$("$here/check-blind.sh" "$1" --profile judge --extra-words "$work/strip-words" ${args[@]+"${args[@]}"})"
  case $? in
    0) ;;
    1) printf '%s\n' "$hits" >&2
       die "the sanitized copy fails the judge check (origin words, model names, secrets, binaries, node_modules or .git); the hits are listed above; nothing was replaced" 1 ;;
    *) die "check-blind.sh could not run on the copy" 1 ;;
  esac
}

# publish <stage>: replace <dest>/<label> with <stage> without a moment where both are lost. The
# previous copy is first renamed into <dest>/.old-<label>.XXXXXX, then <stage> is renamed into
# place, then the previous copy is removed. If the stage cannot be moved, or the script stops in
# between (the EXIT trap calls settle_previous), the previous copy is put back.
publish() {
  local target="$dest_abs/$label"
  if [ -e "$target" ]; then
    old_copy="$(mktemp -d "$dest_abs/.old-$label.XXXXXX")" || die "cannot create a temporary directory in $dest" 1
    mv "$target" "$old_copy/$label" || die "cannot set the previous $out aside" 1
  fi
  if ! mv "$1" "$target"; then
    settle_previous
    die "cannot move the copy to $out; the previous copy is kept" 1
  fi
  stage=""
  settle_previous
}

# settle_previous: put a set-aside previous copy back when nothing took its place, else remove it.
# If it cannot be put back, it is kept and its place is printed.
settle_previous() {
  [ -n "$old_copy" ] || return 0
  if [ -e "$old_copy/$label" ] && [ ! -e "$dest_abs/$label" ]; then
    if ! mv "$old_copy/$label" "$dest_abs/$label"; then
      printf 'sanitize-candidates.sh: the previous copy could not be put back; it is in %s\n' "$old_copy" >&2
      old_copy=""
      return 1
    fi
  fi
  rm -rf "$old_copy"
  old_copy=""
}

main() {
  parse_args "$@"
  check_paths
  collect_strip_words
  collect_path_words
  collect_email

  work="$(mktemp -d "${TMPDIR:-/tmp}/vetdd-strip.XXXXXX")" || die "cannot create a temporary directory" 1
  trap 'rm -rf "$work" ${stage:+"$stage"}; settle_previous' EXIT
  # A signal ends the script through exit, so the EXIT trap runs.
  trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
  words="$work/words"
  # shellcheck disable=SC2086 # the default list is space-separated words
  vetdd_word_file "$words" $VETDD_MODEL_WORDS ${strip[@]+"${strip[@]}"} ${paths[@]+"${paths[@]}"}
  local w
  for w in ${strip[@]+"${strip[@]}"}; do
    [ "$(printf '%s' "$w" | tr 'A-Z' 'a-z')" = "$PLACEHOLDER_WORD" ] || printf '%s\n' "$w"
  done > "$work/words-out"
  # The self-check also looks for the paths (and the email), which --words-out leaves out.
  { cat "$work/words-out"; [ "${#paths[@]}" -eq 0 ] || printf '%s\n' "${paths[@]}"; } > "$work/strip-words"

  # Build beside <dest>/<label> (same file system, so the final mv is a rename); the leading dot
  # keeps it out of judge.sh's c[0-9]* glob.
  stage="$(mktemp -d "$dest_abs/.sanitize-$label.XXXXXX")" || die "cannot create a temporary directory in $dest" 1
  copy_into "$stage"
  redact_tree "$stage"
  self_check "$stage"

  # Before publishing: a word list that outlives a failed publish only makes later checks stricter.
  if [ -n "$words_out" ]; then
    cat "$work/words-out" >> "$words_out" || die "cannot write $words_out" 1
  fi
  publish "$stage"
  printf '%s\n' "$out"
}

# Every message, including bash's own and the tools', may carry a candidate's file name: strip
# control characters from all of stderr, not only from die.
exec 3>&1
main "$@" 2>&1 >&3 3>&- | vetdd_printable >&2
exit "${PIPESTATUS[0]}"
