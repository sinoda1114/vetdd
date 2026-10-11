#!/usr/bin/env bash
# One worker per unit in a swarm (parallel/swarm.md): each in its own git worktree outside the repository,
# so tools that walk the tree (the test runner, Stryker, check-evidence's tree hash) never see another
# worker's copy. Run it from the main repository.
# Usage: worktree.sh add <slice> [--base <ref>] [--link <ignored path>]... [-- <the unit's test command>]
#          makes ../<repo>.vetdd-wt/<slice> on a new branch vetdd/<slice> at <ref> (default HEAD) and
#          prints its path; --link links an ignored path of the main repository into it (node_modules);
#          the command, run from the repository root, is recorded in the git directory, outside any
#          working tree ($GIT_COMMON_DIR/vetdd-swarm/<slice>.cmd), for `evidence.sh <slice> integrated
#          --rerun`, with a checksum of the shared git config and hooks for `check`
#        worktree.sh check <slice>
#          before the parent merges vetdd/<slice>: refuses (exit 1) a branch that touches .vetdd/,
#          a .gitattributes or .gitmodules, or a submodule, and a shared git config or hooks that
#          changed since add (a worker's git config would run in the parent's merge)
#        worktree.sh remove <slice> [--keep-branch] [--no-evidence]
#          refuses while the worktree holds uncommitted work; brings back every .vetdd/evidence/<id>/
#          (also one recorded under another slice id; with none, it refuses unless --no-evidence),
#          .vetdd/artifacts/, and .vetdd/notes/ (a file the main repository already has must be the
#          same: nothing is overwritten, and on any difference nothing is copied); then removes the
#          worktree, and its branch once merged into HEAD (an unmerged branch is kept and named;
#          --keep-branch keeps a merged one too, until the integrated runs pass)
#        worktree.sh review <slice>
#          after `remove <slice> --keep-branch`: checks out vetdd/<slice> again at the same path in a
#          worktree the parent makes (its own .git, never a runner's), with the main repository's
#          .vetdd/evidence/<slice>/ and .vetdd/notes/, so the lane can be checked and laid out for the
#          judge (parallel/arena.md); remove it again with `remove <slice> --keep-branch`
#        worktree.sh list
#          prints "<slice>\t<path>\t<branch>" for each worker worktree
# Exit 0 done; 1 a local step failed or would lose or overwrite work; 2 usage error.
set -u
unset CDPATH

die() { printf 'worktree.sh: %s\n' "$1" >&2; exit "${2:-2}"; }

here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
. "$here/lib/common.sh"

usage="usage: worktree.sh add <slice> [--base <ref>] [--link <ignored path>]... [-- <command...>] | check <slice> | remove <slice> [--keep-branch] [--no-evidence] | review <slice> | list"
[ $# -ge 1 ] || die "$usage"
cmd="$1"; shift

root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
root="$(cd "$root" && pwd -P)"
gitdir="$(cd "$root" && cd "$(git rev-parse --git-dir)" && pwd -P)"
common="$(cd "$root" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
[ "$gitdir" = "$common" ] || die "run worktree.sh from the main repository, not from a worker's worktree"
wtroot="${root%/*}/${root##*/}.vetdd-wt"
p() { printf '%s' "$1" | vetdd_printable; }

slice_arg() {
  [ $# -ge 1 ] || die "$usage"
  vetdd_is_slice_id "$1" || die "invalid slice id: $(p "$1")"
}

# safe_wtroot: <repo>.vetdd-wt is the user's own private directory (not a link, not writable by group or
# others), so no other user can put a worktree, or a .git, in place of a worker's.
safe_wtroot() {
  if [ -e "$wtroot" ] || [ -L "$wtroot" ]; then
    [ ! -L "$wtroot" ] && [ -d "$wtroot" ] \
      && [ -n "$(find "$wtroot" -maxdepth 0 -user "$(id -u)" ! -perm -020 ! -perm -002 -print 2>/dev/null)" ] \
      || die "$(p "$wtroot") is a link, not a directory, not yours, or writable by others; remove it or fix its permissions" 1
  else
    mkdir -m 700 -- "$wtroot" || die "cannot create $(p "$wtroot")" 1
  fi
}

# admin_dir <path>: the git directory git keeps for the worktree at <path> ($common/worktrees/<name>),
# found from the main repository's side and checked against the worktree's .git file. The parent never
# lets a worker's .git choose which git directory (and so which config, hooks, or fsmonitor) runs.
admin_dir() {
  local a found=""
  for a in "$common"/worktrees/*/; do
    a="${a%/}"
    [ -f "$a/gitdir" ] && [ "$(cat "$a/gitdir")" = "$1/.git" ] && { found="$a"; break; }
  done
  [ -n "$found" ] || return 1
  [ -f "$1/.git" ] && [ ! -L "$1/.git" ] && [ "$(cat "$1/.git")" = "gitdir: $found" ] || return 1
  printf '%s' "$found"
}
# wgit_run <admin dir> <path> <git args...>: git on a worker's tree with the parent's git directory and
# no fsmonitor or hooks.
wgit_run() {
  local a="$1" w="$2"; shift 2
  git --git-dir="$a" --work-tree="$w" -c core.fsmonitor= -c core.hooksPath=/dev/null -C "$w" "$@"
}

# The parent's own git, with no hooks or fsmonitor a worker could have set.
pgit() { git -c core.hooksPath=/dev/null -c core.fsmonitor= -C "$root" "$@"; }
swarmdir="$common/vetdd-swarm"
# shared_sum: a checksum of what every worktree's git reads and a worker could change: the shared
# config, the hooks, and info/attributes.
shared_sum() {
  {
    for f in "$common/config" "$common/info/attributes"; do
      printf '%s ' "$f"; [ -f "$f" ] && pgit hash-object --no-filters -- "$f" || echo none
    done
    if [ -d "$common/hooks" ]; then
      find "$common/hooks" -type f -print | LC_ALL=C sort | while IFS= read -r f; do
        printf '%s %s\n' "$f" "$(pgit hash-object --no-filters -- "$f")"
      done
    fi
  } | pgit hash-object --stdin
}

# files_under <dir>: each regular file below <dir>, relative to it, NUL-separated.
files_under() { [ -d "$1" ] || return 0; (cd "$1" && find . -type f -print0); }

case "$cmd" in
  add)
    slice_arg "$@"; slice="$1"; shift
    base=HEAD; links=(); ucmd=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --base) [ $# -ge 2 ] || die "--base needs a ref"; base="$2"; shift 2 ;;
        --link) [ $# -ge 2 ] || die "--link needs a path"; links+=("$2"); shift 2 ;;
        --) shift; [ $# -ge 1 ] || die "-- needs the unit's test command"; ucmd=("$@"); break ;;
        *) die "unknown argument: $(p "$1")" ;;
      esac
    done
    git -C "$root" rev-parse -q --verify "$base^{commit}" >/dev/null || die "--base is not a commit: $(p "$base")"
    norm=()
    for l in ${links[@]+"${links[@]}"}; do
      while [ "${l%/}" != "$l" ]; do l="${l%/}"; done
      norm+=("$l")
    done
    links=(${norm[@]+"${norm[@]}"})
    # The same path twice, or one inside another, would link into the main repository's own directory.
    for a in ${links[@]+"${links[@]}"}; do
      seen=0
      for b in ${links[@]+"${links[@]}"}; do
        [ "$a" = "$b" ] && { seen=$((seen + 1)); continue; }
        case "$b/" in "$a"/*) die "--link $(p "$b") is inside --link $(p "$a"); name one of them" ;; esac
      done
      [ "$seen" -le 1 ] || die "--link $(p "$a") is named twice"
    done
    for l in ${links[@]+"${links[@]}"}; do
      case "/$l/" in //*|*/../*|*/./*) die "--link takes a relative path without . or ..: $(p "$l")" ;; esac
      [ -e "$root/$l" ] || die "--link $(p "$l") does not exist in the main repository"
      case "${l##*/}" in .env*) die "--link $(p "$l"): a file that may hold secrets is never shared with a worker" ;; esac
      git -C "$root" ls-files --error-unmatch -- "$l" >/dev/null 2>&1 && die "--link $(p "$l") is tracked; only an ignored path can be linked"
      git -C "$root" check-ignore -q -- "$l" || die "--link $(p "$l") is not ignored; only an ignored path can be linked"
    done
    path="$wtroot/$slice"
    [ ! -e "$path" ] && [ ! -L "$path" ] || die "$(p "$path") exists"
    git -C "$root" rev-parse -q --verify "refs/heads/vetdd/$slice" >/dev/null && die "branch vetdd/$(p "$slice") exists"
    safe_wtroot
    git -C "$root" worktree add -q -b "vetdd/$slice" "$path" "$base" || die "git worktree add failed" 1
    # The worktree's own git directory: the worker cannot write there through the tree.
    wgit="$(admin_dir "$path")" || die "cannot find the git directory of $(p "$path")" 1
    for l in ${links[@]+"${links[@]}"}; do
      if ! { mkdir -p -- "$path/$(dirname -- "$l")" && ln -s "$root/$l" "$path/$l"; }; then
        git -C "$root" worktree remove --force "$path" >/dev/null 2>&1
        git -C "$root" branch -q -D "vetdd/$slice" >/dev/null 2>&1
        die "cannot link $(p "$l"); the worktree and its branch were removed again" 1
      fi
      # Named so remove can tell a link it made from work left behind.
      printf '%s\n' "$l" >> "$wgit/vetdd-links"
      # A link is not a directory: a rule such as node_modules/ does not ignore it. The rule added is
      # anchored, escaped, added once, and harmless to keep (the path is ignored anyway).
      if ! wgit_run "$wgit" "$path" check-ignore -q -- "$l"; then
        rule="/$(printf '%s' "$l" | sed 's/[][*?\\!#]/\\&/g')"
        { mkdir -p "$common/info" && { grep -qxF -- "$rule" "$common/info/exclude" 2>/dev/null \
            || printf '%s\n' "$rule" >> "$common/info/exclude"; }; } \
          || die "cannot add $(p "$rule") to $(p "$common/info/exclude")" 1
      fi
    done
    { [ -d "$swarmdir" ] || mkdir -m 700 -- "$swarmdir"; } && [ ! -L "$swarmdir" ] || die "cannot use $(p "$swarmdir")" 1
    rm -f -- "$swarmdir/$slice.cmd"
    if [ ${#ucmd[@]} -gt 0 ]; then
      printf '%s\0' "${ucmd[@]}" > "$swarmdir/$slice.cmd" || die "cannot record the command of $(p "$slice")" 1
    fi
    shared_sum > "$swarmdir/$slice.sum" || die "cannot record the shared git config of $(p "$slice")" 1
    printf '%s\n' "$path"
    ;;

  check)
    slice_arg "$@"; slice="$1"; shift
    [ $# -eq 0 ] || die "$usage"
    pgit rev-parse -q --verify "refs/heads/vetdd/$slice" >/dev/null || die "no branch vetdd/$(p "$slice")" 1
    [ -f "$swarmdir/$slice.sum" ] || die "no record of worktree.sh add for $(p "$slice")" 1
    [ "$(shared_sum)" = "$(cat "$swarmdir/$slice.sum")" ] \
      || die "the shared git config, hooks, or info/attributes changed since worktree.sh add $(p "$slice"); a worker's git settings would run in your merge: look at $(p "$common/config") and $(p "$common/hooks") before merging anything" 1
    names="$(pgit diff --name-only --no-renames --no-ext-diff -z HEAD...vetdd/"$slice" | tr '\0' '\n')" \
      || die "cannot read the changes of vetdd/$(p "$slice")" 1
    bad=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      # Any case: a case-insensitive file system takes .VETDD for .vetdd.
      lf="$(printf '%s' "$f" | tr 'A-Z' 'a-z')"
      case "/$lf" in /.vetdd|/.vetdd/*|*/.gitattributes|*/.gitmodules) bad="$bad$f
" ;; esac
    done <<EOF_NAMES
$names
EOF_NAMES
    # A submodule (gitlink, mode 160000) on either side.
    links="$(pgit diff --raw --no-renames --no-ext-diff HEAD...vetdd/"$slice" | awk '$1 == ":160000" || $2 == "160000" { sub(/^[^\t]*\t/, ""); print }')"
    bad="$bad$links"
    [ -z "$bad" ] || die "vetdd/$(p "$slice") touches what a unit never changes (.vetdd/, .gitattributes, .gitmodules, a submodule); do not merge it:
$(p "$bad")" 1
    printf 'vetdd/%s can be merged\n' "$(p "$slice")"
    ;;

  remove)
    slice_arg "$@"; slice="$1"; shift
    keep=0; noev=0
    while [ $# -gt 0 ]; do
      case "$1" in --keep-branch) keep=1; shift ;; --no-evidence) noev=1; shift ;; *) die "$usage" ;; esac
    done
    path="$wtroot/$slice"
    git -C "$root" worktree list --porcelain | grep -qxF "worktree $path" || die "no worker worktree for $(p "$slice") at $(p "$path")"
    excl=(':(exclude).vetdd')
    safe_wtroot
    wgit="$(admin_dir "$path")" \
      || die "the .git of $(p "$path") does not point at its own git directory; it was changed, so nothing was run there" 1
    if [ -f "$wgit/vetdd-links" ]; then
      while IFS= read -r l; do
        # Only a link add made that is still that link: anything else is work to account for.
        [ -n "$l" ] && [ -L "$path/$l" ] && [ "$(readlink "$path/$l")" = "$root/$l" ] && excl+=(":(exclude,literal)$l")
      done < "$wgit/vetdd-links"
    fi
    head="$(wgit_run "$wgit" "$path" symbolic-ref -q HEAD)" || head="(detached)"
    [ "$head" = "refs/heads/vetdd/$slice" ] \
      || die "the worktree of $(p "$slice") is on $(p "$head"), not vetdd/$(p "$slice"); put its commits on that branch first, or they would be lost" 1
    dirty="$(wgit_run "$wgit" "$path" status --porcelain --untracked-files=all -- . "${excl[@]}")" \
      || die "cannot read the status of $(p "$path")" 1
    [ -z "$dirty" ] || die "the worktree of $(p "$slice") has uncommitted work; commit it (or discard it) first:
$(p "$dirty")" 1

    # Check everything before copying anything: on a difference, the main repository is left as it was.
    src_ev="$path/.vetdd/evidence/$slice"; dst_ev="$root/.vetdd/evidence/$slice"
    [ ! -L "$path/.vetdd" ] || die "the .vetdd of $(p "$slice")'s worktree is a link; nothing was copied" 1
    if [ -d "$path/.vetdd" ] && [ -n "$(find "$path/.vetdd" -type l -print 2>/dev/null | head -n 1)" ]; then
      die "the .vetdd of $(p "$slice")'s worktree holds a link; nothing was copied (a link would send the parent's reads or writes outside)" 1
    fi
    # Every slice the worker recorded comes back, also one under another id: the worktree holds the
    # only copy of its runs. A worktree with none is removed only with --no-evidence.
    evs=()
    for d in "$path/.vetdd/evidence"/*/; do
      [ -d "$d" ] || continue
      d="${d%/}"; s="${d##*/}"
      vetdd_is_slice_id "$s" || die "the worktree of $(p "$slice") holds evidence under a name that is not a slice id: $(p "$s"); nothing was copied" 1
      evs+=("$s")
      if [ -e "$root/.vetdd/evidence/$s" ] && ! diff -r -q "$d" "$root/.vetdd/evidence/$s" >/dev/null 2>&1; then
        die "the main repository already has different evidence for $(p "$s") (.vetdd/evidence/$(p "$s")); nothing was copied" 1
      fi
    done
    if [ ${#evs[@]} -eq 0 ] && [ "$noev" -eq 0 ]; then
      die "the worktree of $(p "$slice") holds no evidence; remove it with --no-evidence if the worker recorded nothing" 1
    fi
    for d in artifacts notes; do
      while IFS= read -r -d '' f; do
        f="${f#./}"
        if [ -e "$root/.vetdd/$d/$f" ] && ! cmp -s -- "$path/.vetdd/$d/$f" "$root/.vetdd/$d/$f"; then
          die "the main repository already has a different .vetdd/$d/$(p "$f"); nothing was copied" 1
        fi
      done < <(files_under "$path/.vetdd/$d")
    done
    for s in ${evs[@]+"${evs[@]}"}; do
      [ -e "$root/.vetdd/evidence/$s" ] && continue
      mkdir -p -- "$root/.vetdd/evidence" && cp -R -- "$path/.vetdd/evidence/$s" "$root/.vetdd/evidence/$s" \
        || die "cannot copy the evidence of $(p "$s")" 1
      [ "$s" = "$slice" ] || printf 'brought back evidence recorded under another slice id: %s\n' "$(p "$s")"
    done
    for d in artifacts notes; do
      while IFS= read -r -d '' f; do
        f="${f#./}"
        [ -e "$root/.vetdd/$d/$f" ] && continue
        mkdir -p -- "$root/.vetdd/$d/$(dirname -- "$f")" && cp -p -- "$path/.vetdd/$d/$f" "$root/.vetdd/$d/$f" \
          || die "cannot copy .vetdd/$d/$(p "$f")" 1
      done < <(files_under "$path/.vetdd/$d")
    done

    # Its own .vetdd and the links it made are all that is left untracked, and they are copied or not ours.
    git -C "$root" worktree remove --force "$path" || die "git worktree remove failed" 1
    if [ "$keep" -eq 1 ]; then
      printf 'removed %s; kept branch vetdd/%s (--keep-branch)\n' "$(p "$path")" "$(p "$slice")"
    elif git -C "$root" merge-base --is-ancestor "vetdd/$slice" HEAD 2>/dev/null; then
      git -C "$root" branch -q -D "vetdd/$slice" || die "cannot delete branch vetdd/$(p "$slice")" 1
      printf 'removed %s and its merged branch vetdd/%s\n' "$(p "$path")" "$(p "$slice")"
    else
      printf 'removed %s; kept branch vetdd/%s: not merged into HEAD yet\n' "$(p "$path")" "$(p "$slice")"
    fi
    rmdir -- "$wtroot" 2>/dev/null || true
    ;;

  review)
    slice_arg "$@"; slice="$1"; shift
    [ $# -eq 0 ] || die "$usage"
    pgit rev-parse -q --verify "refs/heads/vetdd/$slice" >/dev/null || die "no branch vetdd/$(p "$slice")"
    ! pgit rev-parse -q --verify "refs/tags/vetdd/$slice" >/dev/null \
      || die "a tag shares the name vetdd/$(p "$slice"); delete or rename it first, so the branch is what is checked out" 1
    # The evidence and notes come from the main repository, never from the branch (in any case).
    ! pgit ls-tree -r --name-only "refs/heads/vetdd/$slice" | grep -qi '^\.vetdd/' \
      || die "vetdd/$(p "$slice") tracks files under .vetdd/; a lane never does: leave it out of the arena" 1
    for d in "$root/.vetdd/evidence/$slice" "$root/.vetdd/notes"; do
      [ ! -d "$d" ] || [ -z "$(find "$d" -type l -print 2>/dev/null | head -n 1)" ] \
        || die "$(p "${d#"$root"/}") holds a link; nothing is copied through a link" 1
    done
    path="$wtroot/$slice"
    [ ! -e "$path" ] && [ ! -L "$path" ] || die "$(p "$path") exists: remove the runner's worktree first (worktree.sh check, then remove --keep-branch)"
    [ -d "$root/.vetdd/evidence/$slice" ] && [ ! -L "$root/.vetdd/evidence/$slice" ] \
      || die "no evidence for $(p "$slice") in the main repository; bring it back with worktree.sh remove $(p "$slice") --keep-branch"
    safe_wtroot
    pgit worktree add -q "$path" "vetdd/$slice" || die "git worktree add failed" 1
    # Anything that fails from here takes the worktree away again.
    undo() { pgit worktree remove --force "$path" >/dev/null 2>&1; die "$1" 1; }
    { mkdir -p "$path/.vetdd/evidence" && cp -R -- "$root/.vetdd/evidence/$slice" "$path/.vetdd/evidence/$slice"; } \
      || undo "cannot copy the evidence of $(p "$slice")"
    if [ -d "$root/.vetdd/notes" ]; then
      cp -R -- "$root/.vetdd/notes" "$path/.vetdd/notes" || undo "cannot copy the notes"
    fi
    printf '%s\n' "$path"
    ;;

  list)
    [ $# -eq 0 ] || die "$usage"
    git -C "$root" worktree list --porcelain | awk -v pre="$wtroot/" '
      /^worktree / { path = substr($0, 10); branch = "" }
      /^branch /   { branch = substr($0, 8); sub(/^refs\/heads\//, "", branch) }
      /^$/         { if (index(path, pre) == 1) printf "%s\t%s\t%s\n", substr(path, length(pre) + 1), path, branch; path = "" }
      END          { if (path != "" && index(path, pre) == 1) printf "%s\t%s\t%s\n", substr(path, length(pre) + 1), path, branch }' \
      | vetdd_printable
    ;;

  *) die "$usage" ;;
esac
