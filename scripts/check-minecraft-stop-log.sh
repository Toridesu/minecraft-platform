#!/usr/bin/env bash
set -euo pipefail

# Fixed Vanilla 26.1 log format; stdin must contain ONLY this shutdown's logs.
# Caller must establish the invocation/cursor boundary and independently verify
# process exit, unit result, storage identity, and absence of forced termination.
# Never pass all of latest.log: startup/previous save messages are not evidence.
# Conservative: any WARN/ERROR/FATAL in the supplied fragment rejects it.
fail() { printf 'Stop log check failed: %s\n' "$1" >&2; exit 1; }
[[ $# -eq 0 ]] || fail 'Usage: scoped shutdown log | bash check-minecraft-stop-log.sh'

info_pattern='^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\] \[Server thread/INFO\]: (.*)$'
error_pattern='\[[^]]+/(WARN|ERROR|FATAL)\]:'
phase=0
overworld=false
end=false
nether=false
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ ! "$line" =~ $error_pattern ]] || fail 'warning or error in shutdown logs'
  [[ "$line" =~ $info_pattern ]] || continue
  message=${BASH_REMATCH[1]}
  case "$message" in
    'Stopping server')
      [[ "$phase" -eq 0 ]] || fail 'duplicate or out-of-order shutdown'
      phase=1 ;;
    'Saving players')
      [[ "$phase" -eq 1 ]] || fail 'player save out of order'
      phase=2 ;;
    'Saving worlds')
      [[ "$phase" -eq 2 ]] || fail 'world save out of order'
      phase=3 ;;
    'ThreadedAnvilChunkStorage (world): All chunks are saved')
      [[ "$phase" -eq 3 ]] || fail 'dimension save out of order'
      overworld=true ;;
    'ThreadedAnvilChunkStorage (DIM1): All chunks are saved')
      [[ "$phase" -eq 3 ]] || fail 'dimension save out of order'
      end=true ;;
    'ThreadedAnvilChunkStorage (DIM-1): All chunks are saved')
      [[ "$phase" -eq 3 ]] || fail 'dimension save out of order'
      nether=true ;;
    'ThreadedAnvilChunkStorage: All dimensions are saved')
      [[ "$phase" -eq 3 && "$overworld" == true &&
         "$end" == true && "$nether" == true ]] || fail 'incomplete dimension save'
      phase=4 ;;
  esac
done
[[ "$phase" -eq 4 ]] || fail 'shutdown save completion not confirmed'
printf 'Stop log check passed (invocation/process checks required separately)\n'
