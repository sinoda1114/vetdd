# The writers of a slice's meta.json (evidence.sh, oracle-version.sh, audit-note.sh) share its skeleton
# and its lock here (bash 3.2 compatible; jq required).

# vetdd_meta_skeleton <slice>: the meta.json a slice starts with, on standard output. oracle_versions is
# there from the start, so check-evidence rule 8d asks every new slice for the entry of a bumped version
# (evidence recorded before the version log has no key and stays exempt). There is no audits key: an
# empty one would opt the slice in to rule 10b.
vetdd_meta_skeleton() {
  jq -n --arg s "$1" '{slice_id: $s, oracle: {seam: null, version: null, files: []}, runs: [], oracle_versions: []}'
}

# vetdd_slice_lock <slice>: hold <git dir>/vetdd-lock/<slice> while this process reads, changes, and
# writes the slice's meta.json, so no two writers interleave (a lost write, or a version entry whose
# after_seq misses a red that was running). It lives in the git dir, outside .vetdd/, so worktree.sh never
# carries it back and the judge never gets it. The lock is a symbolic link naming the holder (pid:<pid>),
# made in one step (ln -s fails when the name exists). A lock whose holder is gone (kill -0, so the pid
# namespace must be the one it was made in) is taken over: a guard link puts two takeovers one after the
# other, the owner is read again under it, and the new owner goes in with one rename. On success it sets
# VETDD_SLICE_LOCK; the caller removes it with vetdd_slice_unlock (on EXIT). On failure it returns 1
# with the reason in VETDD_SLICE_LOCK_ERR; a lock a live process holds is never touched.
VETDD_SLICE_LOCK=""
VETDD_SLICE_LOCK_ERR=""
vetdd_slice_lock() {
  local slice="$1" gdir lock owner opid
  gdir="$(git rev-parse --absolute-git-dir 2>/dev/null)" && [ -n "$gdir" ] \
    || { VETDD_SLICE_LOCK_ERR="cannot locate the git dir for the lock of slice $slice"; return 1; }
  lock="$gdir/vetdd-lock/$slice"
  mkdir -p "$gdir/vetdd-lock" 2>/dev/null || { VETDD_SLICE_LOCK_ERR="cannot create $gdir/vetdd-lock"; return 1; }
  if ln -s "pid:$$" "$lock" 2>/dev/null; then VETDD_SLICE_LOCK="$lock"; return 0; fi
  if [ ! -L "$lock" ]; then
    VETDD_SLICE_LOCK_ERR="$lock is not a lock a vetdd script made; inspect it and remove it by hand"; return 1
  fi
  owner="$(readlink "$lock" 2>/dev/null)"; opid="${owner#pid:}"
  case "$owner" in pid:[1-9]*) ;; *) opid="" ;; esac
  case "$opid" in *[!0123456789]*) opid="" ;; esac
  if [ -z "$opid" ]; then
    VETDD_SLICE_LOCK_ERR="the lock $lock of slice $slice is unreadable; if no vetdd script is recording the slice, remove it (rm $lock) and run again"; return 1
  fi
  if kill -0 "$opid" 2>/dev/null; then
    VETDD_SLICE_LOCK_ERR="another vetdd script (pid $opid) is recording slice $slice ($lock); wait for it to end, then run again. If pid $opid is not one (check with: ps -p $opid), its run was killed and the pid reused: remove $lock"
    return 1
  fi
  if ln -s "pid:$$" "$lock.takeover" 2>/dev/null; then
    if [ "$(readlink "$lock" 2>/dev/null)" = "$owner" ] && ln -s "pid:$$" "$lock.new.$$" 2>/dev/null \
       && mv -f "$lock.new.$$" "$lock"; then
      rm -f "$lock.takeover"; VETDD_SLICE_LOCK="$lock"; return 0
    fi
    rm -f "$lock.new.$$" "$lock.takeover"
  fi
  VETDD_SLICE_LOCK_ERR="another vetdd script is taking over the lock $lock of slice $slice; run again (if none is running, remove $lock.takeover)"
  return 1
}

# vetdd_slice_unlock: remove the lock this process holds (only while it still names this process).
vetdd_slice_unlock() {
  [ -n "$VETDD_SLICE_LOCK" ] || return 0
  [ "$(readlink "$VETDD_SLICE_LOCK" 2>/dev/null)" != "pid:$$" ] || rm -f "$VETDD_SLICE_LOCK"
  VETDD_SLICE_LOCK=""
}
