# extracted verbatim from bin/spawn at 65810a9; regenerate with extract-slot-lib.sh
slot_live() { # $1=slot dir $2=pid: live if the spawner answers with a matching start time, or (kill -9 of spawn) its worker still runs
  local wp
  if kill -0 "$2" 2>/dev/null; then
    [ -s "$1/start" ] || return 0
    [ "$(LC_ALL=C TZ=UTC ps -o lstart= -p "$2" 2>/dev/null)" != "$(cat "$1/start" 2>/dev/null)" ] || return 0
  fi
  wp=$(cat "$1/wpid" 2>/dev/null); [ -n "$wp" ] && kill -0 "$wp" 2>/dev/null
}

slot_lock() { local l=$1 s=$2 own opid ost
  ln -s "$$ $s" "$l" 2>/dev/null && return 0
  own=$(readlink "$l" 2>/dev/null); opid=${own%% *}
  # the lock names its owner (pid + start): steal only a dead or reused owner, never by age; re-read before rm so a fresh lock is spared
  if [ -z "$own" ]; then [ -d "$l" ] && rm -rf "$l" # a legacy dir lock has no owner; a symlink that vanished mid-read is not ours to judge
  elif ! kill -0 "$opid" 2>/dev/null; then [ "$(readlink "$l" 2>/dev/null)" = "$own" ] && rm -rf "$l"
  else ost=${own#* }
    if [ -n "$ost" ] && [ "$(LC_ALL=C TZ=UTC ps -o lstart= -p "$opid" 2>/dev/null)" != "$ost" ] && [ "$(readlink "$l" 2>/dev/null)" = "$own" ]; then rm -rf "$l"; fi
  fi
  ln -s "$$ $s" "$l" 2>/dev/null
}

claim() { local n d p lock live s pp st
  self=${self:-$(LC_ALL=C TZ=UTC ps -o lstart= -p $$ 2>/dev/null)} # one sample per spawn, shared with claim_id
  n=1; while [ "$n" -le "$CAP" ]; do d=$H/run/slot.$n; lock=$d.lock
    # the lock comes first: mkdir and the pid write are one claim, so a reclaimer or another
    # spawner cannot see, free or replace a dir whose owner has not published its pid yet
    if slot_lock "$lock" "$self"; then
      if mkdir "$d" 2>/dev/null; then
        # pid first: until it exists a reclaimer may treat the dir as abandoned
        if ! echo $$ > "$d/pid" 2>/dev/null; then rm -rf "$d"; rm -f "$lock"; n=$((n+1)); continue; fi # pitfall-ok: decimal-arith internal counter
        # CAP may have been lowered while higher slots live; a fresh dir must not push the live count over it
        live=0; for s in "$H"/run/slot.*; do case $s in "$d"|*.lock) continue;; esac
          [ -d "$s" ] || continue; pp=$(cat "$s/pid" 2>/dev/null); [ -n "$pp" ] || continue
          slot_live "$s" "$pp" && live=$((live+1)); done # pitfall-ok: decimal-arith internal counter
        if [ "$live" -ge "$CAP" ]; then rm -rf "$d"
        else [ -z "$self" ] || echo "$self" > "$d/start" 2>/dev/null
          # we hold the lock, so only a verified pid means the slot is ours
          if [ "$(cat "$d/pid" 2>/dev/null)" = "$$" ]; then slot=$d; rm -f "$lock"; return 0; fi; fi
        rm -f "$lock"
      else
        p=$(cat "$d/pid" 2>/dev/null)
        if [ -z "$p" ]; then sleep 1; p=$(cat "$d/pid" 2>/dev/null); fi
        if [ -z "$p" ] || ! slot_live "$d" "$p"; then
          # fence: move the pid we judged dead aside; a fresh claim writes a new one, so a late rm cannot free it
          st="$d/pid.reap.$$"; mv "$d/pid" "$st" 2>/dev/null
          if [ "$(cat "$st" 2>/dev/null)" = "$p" ]; then rm -rf "$d"
          elif [ -e "$st" ]; then mv -f "$st" "$d/pid" 2>/dev/null; fi
          rm -f "$st"
        fi
        rm -f "$lock"
      fi
    fi
    n=$((n+1)) # pitfall-ok: decimal-arith internal counter
  done; return 1; }

