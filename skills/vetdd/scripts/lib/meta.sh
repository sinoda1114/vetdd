# The writers of a slice's meta.json (evidence.sh, oracle-version.sh, audit-note.sh) share its skeleton
# and its lock here (bash 3.2 compatible; jq required).

# vetdd_meta_skeleton <slice>: the meta.json a slice starts with, on standard output. oracle_versions is
# there from the start, so check-evidence rule 8d asks every new slice for the entry of a bumped version
# (evidence recorded before the version log has no key and stays exempt). There is no audits key: an
# empty one would opt the slice in to rule 10b.
vetdd_meta_skeleton() {
  jq -n --arg s "$1" '{slice_id: $s, oracle: {seam: null, version: null, files: []}, runs: [], oracle_versions: []}'
}

# vetdd_pid_ns: this process's pid namespace (Linux), "-" where there is none to read (macOS).
vetdd_pid_ns() {
  local ns
  ns="$(readlink /proc/self/ns/pid 2>/dev/null)" || ns=""
  ns="$(printf '%s' "$ns" | LC_ALL=C sed -e 's/[^A-Za-z0-9]/_/g')"
  printf '%s\n' "${ns:--}"
}
# vetdd_proc_start <pid>: when the process started (ps lstart, spaces as _), or nothing when ps cannot say.
vetdd_proc_start() {
  LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | LC_ALL=C sed -e 's/^ *//' -e 's/ *$//' -e 's/ /_/g' | LC_ALL=C tr -cd 'A-Za-z0-9:_'
}

# vetdd_slice_lock <slice>: hold <git dir>/vetdd-lock/<slice> while this process reads, changes, and
# writes the slice's meta.json, so no two writers interleave (a lost write, or a version entry whose
# after_seq misses a red that was running). It lives in the git dir, outside .vetdd/, so worktree.sh never
# carries it back and the judge never gets it; the writers therefore need to write the git dir (as
# calibrate.sh always has). The lock is a symbolic link naming its holder, pid:<pid>:<pid namespace>:<start
# time>, made in one step (ln -sn fails when the name exists, and never follows a link there). Anything
# at the lock's name other than such a link (a directory, or a link to one) is refused.
# A lock is stale when its holder is gone: no live process with its pid, or one that started at another
# time (the pid was reused), or this process's own pid (an earlier process it was reused from). A lock
# made in another pid namespace is never judged (its pid means nothing here): it is refused, to be removed
# by hand. A lock without a start time (pid:<pid>) is held while its pid lives. A stale lock is taken
# over: a guard link puts two takeovers one after the other, the owner is read again under it, and the
# new owner goes in with one rename, checked after. The guard and the new link are named
# .takeover.<slice> and .new.<slice>.<pid>: a slice id never starts with a dot, so no slice's lock has
# those names. A guard a killed takeover left is not removed automatically (removing it would let two
# takeovers race): the message names it. On success it sets VETDD_SLICE_LOCK; the caller removes it with
# vetdd_slice_unlock (on EXIT). On failure it returns 1 with the reason in VETDD_SLICE_LOCK_ERR; a lock a
# live process holds is never touched.
VETDD_SLICE_LOCK=""
VETDD_SLICE_LOCK_ERR=""
vetdd_slice_lock() {
  local slice="$1" gdir dir lock guard new me owner rest opid ons ostart now
  gdir="$(git rev-parse --absolute-git-dir 2>/dev/null)" && [ -n "$gdir" ] \
    || { VETDD_SLICE_LOCK_ERR="cannot locate the git dir for the lock of slice $slice"; return 1; }
  dir="$gdir/vetdd-lock"; lock="$dir/$slice"; guard="$dir/.takeover.$slice"; new="$dir/.new.$slice.$$"
  mkdir -p "$dir" 2>/dev/null || { VETDD_SLICE_LOCK_ERR="cannot create $dir (the slice lock lives in the git dir, which must be writable)"; return 1; }
  me="pid:$$:$(vetdd_pid_ns):$(vetdd_proc_start "$$")"
  if [ -d "$lock" ] || { [ -e "$lock" ] && [ ! -L "$lock" ]; }; then
    VETDD_SLICE_LOCK_ERR="$lock is not a lock a vetdd script made; inspect it and remove it by hand"; return 1
  fi
  if ln -sn "$me" "$lock" 2>/dev/null && [ "$(readlink "$lock" 2>/dev/null)" = "$me" ]; then
    VETDD_SLICE_LOCK="$lock"; return 0
  fi
  if [ ! -L "$lock" ]; then
    VETDD_SLICE_LOCK_ERR="$lock is not a lock a vetdd script made; inspect it and remove it by hand"; return 1
  fi
  owner="$(readlink "$lock" 2>/dev/null)"
  case "$owner" in pid:[1-9]*) rest="${owner#pid:}" ;; *) rest="" ;; esac
  opid="${rest%%:*}"; ons=""; ostart=""
  case "$rest" in *:*) rest="${rest#*:}"; ons="${rest%%:*}"; case "$rest" in *:*) ostart="${rest#*:}" ;; esac ;; esac
  case "$opid" in ''|*[!0123456789]*)
    VETDD_SLICE_LOCK_ERR="the lock $lock of slice $slice is unreadable; if no vetdd script is recording the slice, remove it (rm $lock) and run again"; return 1 ;;
  esac
  if [ -n "$ons" ] && [ "$ons" != - ] && [ "$ons" != "$(vetdd_pid_ns)" ]; then
    VETDD_SLICE_LOCK_ERR="the lock $lock of slice $slice was made in another pid namespace (a sandbox, a container), so whether pid $opid still runs cannot be told here; if no vetdd script is recording the slice, remove $lock and run again"
    return 1
  fi
  if [ "$opid" != "$$" ] && { kill -0 "$opid" 2>/dev/null || ps -p "$opid" >/dev/null 2>&1; }; then
    # kill -0 fails for another user's live process too (EPERM): ps sees it. A start time that is not
    # the live process's own means the pid was reused.
    now="$(vetdd_proc_start "$opid")"
    if [ -z "$ostart" ] || [ -z "$now" ] || [ "$now" = "$ostart" ]; then
      VETDD_SLICE_LOCK_ERR="another vetdd script (pid $opid) is recording slice $slice ($lock); wait for it to end, then run again. If pid $opid is not one (check with: ps -p $opid), its run was killed and the pid reused: remove $lock"
      return 1
    fi
  fi
  if { [ ! -e "$guard" ] && [ ! -L "$guard" ]; } && ln -sn "$me" "$guard" 2>/dev/null; then
    if [ "$(readlink "$lock" 2>/dev/null)" = "$owner" ] && [ ! -d "$lock" ] && rm -f "$new" \
       && ln -sn "$me" "$new" 2>/dev/null && mv -f "$new" "$lock" && [ "$(readlink "$lock" 2>/dev/null)" = "$me" ]; then
      rm -f "$guard"; VETDD_SLICE_LOCK="$lock"; return 0
    fi
    rm -f "$new" "$guard"
  fi
  VETDD_SLICE_LOCK_ERR="another vetdd script is taking over the lock $lock of slice $slice; run again (if none is running, remove $guard)"
  return 1
}

# vetdd_slice_unlock: remove the lock this process holds (only while it still names this process).
vetdd_slice_unlock() {
  [ -n "$VETDD_SLICE_LOCK" ] || return 0
  case "$(readlink "$VETDD_SLICE_LOCK" 2>/dev/null)" in "pid:$$:"*) rm -f "$VETDD_SLICE_LOCK" ;; esac
  VETDD_SLICE_LOCK=""
}
