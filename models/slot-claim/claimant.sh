#!/usr/bin/env bash
# One real claimant process: its own $$ is the pid claim() records, exactly as
# a spawner would. The only injection is the mkdir wrapper below (a stall after
# a successful mkdir, inside the mkdir -> slot_lock gap); claim/slot_lock/
# slot_live are the extracted real functions, unchanged.
set -u
id=$1
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/slot-lib.sh"
: "${RUN_DIR:?}"; CAP=${CAP:-2}
export H=$RUN_DIR CAP

mkdir() { /bin/mkdir "$@"; local rc=$?; [ $rc -eq 0 ] || return $rc; [ -z "${MKDIR_STALL:-}" ] || sleep "$MKDIR_STALL"; }

claim; rc=$?
if [ -n "${slot:-}" ]; then
  printf '%s %s %s\n' "$id" "$$" "${slot##*.}" >> "$H/holds"
  while [ ! -e "$H/stop" ]; do sleep 0.05; done
  rm -rf "$slot"
else
  printf '%s %s none rc=%s\n' "$id" "$$" "$rc" >> "$H/missed"
fi
