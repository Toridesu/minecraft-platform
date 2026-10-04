#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_dir/scripts/minecraft-operation-common.sh"

# Only shell mocks are used: no systemd, real process signals, EBS, or AWS.
test_invocation=11111111111111111111111111111111
prefix='[12:00:00] [Server thread/INFO]: '
normal=$(printf '%s\n' "${prefix}Stopping server" "${prefix}Saving players" \
  "${prefix}Saving worlds" "${prefix}ThreadedAnvilChunkStorage (world): All chunks are saved" \
  "${prefix}ThreadedAnvilChunkStorage (DIM1): All chunks are saved" \
  "${prefix}ThreadedAnvilChunkStorage (DIM-1): All chunks are saved" \
  "${prefix}ThreadedAnvilChunkStorage: All dimensions are saved")

systemctl() {
  [[ "$*" == *minecraft.service* ]] || return 2
  case "$1" in
    stop)
      [[ "$test_case" != stop_failure ]] || return 1
      phase=stopped ;;
    show)
      local active=active main=424242 result=success code=1 status=143 start=1000 id=$test_invocation control=0
      if [[ "$phase" == stopped ]]; then
        active=inactive; main=0; id=
        case "$test_case" in
          unit_failure) result=timeout ;;
          running_after_stop) active=active; main=424242 ;;
          control_process_alive) control=77 ;;
          forced_kill) code=2; status=9 ;;
          changed_process) start=2000 ;;
          changed_invocation) id=22222222222222222222222222222222 ;;
          exit_zero) status=0 ;;
        esac
      else
        [[ "$test_case" != not_running ]] || active=inactive
        [[ "$test_case" != bad_invocation ]] || id=invalid
        # Each show runs in this shell (output redirected, no command substitution).
        shows=$((shows+1))
        [[ "$test_case" != changed_before_stop || "$shows" -lt 2 ]] || start=2000
      fi
      printf '%s\n' "ActiveState=$active" "MainPID=$main" "ControlPID=$control" \
        "InvocationID=$id" 'ExecMainPID=424242' "ExecMainCode=$code" \
        "ExecMainStatus=$status" "ExecMainStartTimestampMonotonic=$start" "Result=$result" ;;
    *) return 2 ;;
  esac
}

timeout() {
  [[ "$1" == 150 ]] || return 2
  shift
  "$@"
}

kill() {
  [[ "$1" == -0 && "$2" == 424242 ]] || return 2
  [[ "$test_case" == process_alive ]]
}

journalctl() {
  if [[ "$1" == --sync ]]; then
    [[ "$test_case" != journal_sync_failure ]]
    return
  fi
  # Ensure every read is bounded to the fixed unit and original invocation.
  [[ "$*" == *"_SYSTEMD_UNIT=minecraft.service"* &&
     "$*" == *"_SYSTEMD_INVOCATION_ID=$test_invocation"* ]] || return 2
  if [[ "$*" == *--after-cursor=* ]]; then
    [[ "$*" == *'--after-cursor=s=111;i=1;b=111;m=1;t=1;x=1'* ]] || return 2
    case "$test_case" in
      journal_read_failure) return 1 ;;
      missing_stop_log) return 0 ;;
      save_error) printf '%s\n' "$normal" '[12:00:01] [Server thread/ERROR]: Save failed' ;;
      *) printf '%s\n' "$normal" ;;
    esac
  elif [[ "$*" == *--show-cursor* ]]; then
    printf '%sDone (1.0s)!\n' "$prefix"
    [[ "$test_case" == no_cursor ]] || printf '%s\n' '-- cursor: s=111;i=1;b=111;m=1;t=1;x=1'
  else
    [[ "$test_case" != not_ready ]] || return 0
    printf '%sDone (1.0s)!\n' "$prefix"
    [[ "$test_case" != startup_error ]] || printf '%s\n' '[12:00:00] [Server thread/ERROR]: Startup problem'
  fi
}

passed=0
run_case() {
  local name=$1 expected=$2 actual=0 work output
  work=$(mktemp -d)
  if output=$(
    test_case=$name
    phase=running
    shows=0
    pmp_capture_stop_evidence "$work" "$repo_dir/scripts/check-minecraft-stop-log.sh" 2>&1
  ); then actual=0; else actual=$?; fi
  if [[ "$actual" -ne "$expected" ]]; then
    printf 'FAIL %s: expected %s got %s: %s\n' "$name" "$expected" "$actual" "$output" >&2
    exit 1
  fi
  if [[ "$expected" -ne 0 && -e "$work/invocation.id" ]]; then
    printf 'FAIL %s: success marker published on failure\n' "$name" >&2
    exit 1
  fi
  # This mktemp directory contains only this test's generated evidence.
  # Explicit filenames, no recursive deletion or computed broad target.
  rm -f -- "$work/before.properties" "$work/pre-stop.properties" "$work/after.properties" \
    "$work/invocation-before.log" "$work/journal.cursor" "$work/stop-requested.utc" \
    "$work/process-stopped.utc" "$work/shutdown.log" "$work/invocation.id"
  rmdir -- "$work"
  printf 'PASS %s\n' "$name"
  passed=$((passed+1))
}
run_case normal 0
run_case exit_zero 0
for test in not_running bad_invocation not_ready startup_error no_cursor \
  changed_before_stop stop_failure unit_failure running_after_stop control_process_alive \
  forced_kill changed_process changed_invocation process_alive journal_sync_failure \
  journal_read_failure missing_stop_log save_error; do
  run_case "$test" 1
done
printf '%s passed, 0 failed\n' "$passed"
