#!/usr/bin/env bash
# One worker per unit in a swarm (parallel/swarm.md): each in its own git worktree outside the repository,
# so tools that walk the tree (the test runner, Stryker, check-evidence's tree hash) never see another
# worker's copy. Run it from the main repository.
# Usage: worktree.sh add <slice> [--base <ref>] [--link <ignored path>]...
#          makes ../<repo>.vetdd-wt/<slice> on a new branch vetdd/<slice> at <ref> (default HEAD) and
#          prints its path; --link links an ignored path of the main repository into it (node_modules)
#        worktree.sh remove <slice>
#          refuses while the worktree holds uncommitted work; brings back .vetdd/evidence/<slice>/,
#          .vetdd/artifacts/, and .vetdd/notes/ (a file the main repository already has must be the
#          same: nothing is overwritten, and on any difference nothing is copied); then removes the
#          worktree, and its branch once merged into HEAD (an unmerged branch is kept and named)
#        worktree.sh list
#          prints "<slice>\t<path>\t<branch>" for each worker worktree
# Exit 0 done; 1 a local step failed or would lose or overwrite work; 2 usage error.
set -u
unset CDPATH

die() { printf 'worktree.sh: %s\n' "$1" >&2; exit "${2:-2}"; }

here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
. "$here/lib/common.sh"

usage="usage: worktree.sh add <slice> [--base <ref>] [--link <ignored path>]... | remove <slice> | list"
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

# files_under <dir>: each regular file below <dir>, relative to it, NUL-separated.
files_under() { [ -d "$1" ] || return 0; (cd "$1" && find . -type f -print0); }

case "$cmd" in
  add)
    slice_arg "$@"; slice="$1"; shift
    base=HEAD; links=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --base) [ $# -ge 2 ] || die "--base needs a ref"; base="$2"; shift 2 ;;
        --link) [ $# -ge 2 ] || die "--link needs a path"; links+=("$2"); shift 2 ;;
        *) die "unknown argument: $(p "$1")" ;;
      esac
    done
    git -C "$root" rev-parse -q --verify "$base^{commit}" >/dev/null || die "--base is not a commit: $(p "$base")"
    for l in ${links[@]+"${links[@]}"}; do
      case "/$l/" in //*|*/../*|*/./*) die "--link takes a relative path without . or ..: $(p "$l")" ;; esac
      [ -e "$root/$l" ] || die "--link $(p "$l") does not exist in the main repository"
      git -C "$root" ls-files --error-unmatch -- "$l" >/dev/null 2>&1 && die "--link $(p "$l") is tracked; only an ignored path can be linked"
      git -C "$root" check-ignore -q -- "$l" || die "--link $(p "$l") is not ignored; only an ignored path can be linked"
    done
    path="$wtroot/$slice"
    [ ! -e "$path" ] && [ ! -L "$path" ] || die "$(p "$path") exists"
    git -C "$root" rev-parse -q --verify "refs/heads/vetdd/$slice" >/dev/null && die "branch vetdd/$(p "$slice") exists"
    mkdir -p -- "$wtroot" || die "cannot create $(p "$wtroot")" 1
    git -C "$root" worktree add -q -b "vetdd/$slice" "$path" "$base" || die "git worktree add failed" 1
    for l in ${links[@]+"${links[@]}"}; do
      mkdir -p -- "$path/$(dirname -- "$l")" && ln -s "$root/$l" "$path/$l" || die "cannot link $(p "$l")" 1
      # Named so remove can tell a link it made from work left behind.
      mkdir -p "$path/.vetdd" && printf '%s\n' "$l" >> "$path/.vetdd/worktree-links"
    done
    printf '%s\n' "$path"
    ;;

  remove)
    slice_arg "$@"; slice="$1"; shift
    [ $# -eq 0 ] || die "$usage"
    path="$wtroot/$slice"
    git -C "$root" worktree list --porcelain | grep -qxF "worktree $path" || die "no worker worktree for $(p "$slice") at $(p "$path")"
    excl=(':(exclude).vetdd')
    if [ -f "$path/.vetdd/worktree-links" ]; then
      while IFS= read -r l; do [ -z "$l" ] || excl+=(":(exclude)$l"); done < "$path/.vetdd/worktree-links"
    fi
    dirty="$(git -C "$path" status --porcelain --untracked-files=all -- . "${excl[@]}")" \
      || die "cannot read the status of $(p "$path")" 1
    [ -z "$dirty" ] || die "the worktree of $(p "$slice") has uncommitted work; commit it (or discard it) first:
$(p "$dirty")" 1

    # Check everything before copying anything: on a difference, the main repository is left as it was.
    src_ev="$path/.vetdd/evidence/$slice"; dst_ev="$root/.vetdd/evidence/$slice"
    if [ -e "$dst_ev" ] && [ -d "$src_ev" ] && ! diff -r -q "$src_ev" "$dst_ev" >/dev/null 2>&1; then
      die "the main repository already has different evidence for $(p "$slice") (.vetdd/evidence/$(p "$slice")); nothing was copied" 1
    fi
    for d in artifacts notes; do
      while IFS= read -r -d '' f; do
        f="${f#./}"
        if [ -e "$root/.vetdd/$d/$f" ] && ! cmp -s -- "$path/.vetdd/$d/$f" "$root/.vetdd/$d/$f"; then
          die "the main repository already has a different .vetdd/$d/$(p "$f"); nothing was copied" 1
        fi
      done < <(files_under "$path/.vetdd/$d")
    done
    if [ -d "$src_ev" ] && [ ! -e "$dst_ev" ]; then
      mkdir -p -- "$root/.vetdd/evidence" && cp -R -- "$src_ev" "$dst_ev" || die "cannot copy the evidence of $(p "$slice")" 1
    fi
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
    if git -C "$root" merge-base --is-ancestor "vetdd/$slice" HEAD 2>/dev/null; then
      git -C "$root" branch -q -D "vetdd/$slice" || die "cannot delete branch vetdd/$(p "$slice")" 1
      printf 'removed %s and its merged branch vetdd/%s\n' "$(p "$path")" "$(p "$slice")"
    else
      printf 'removed %s; kept branch vetdd/%s: not merged into HEAD yet\n' "$(p "$path")" "$(p "$slice")"
    fi
    rmdir -- "$wtroot" 2>/dev/null || true
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
