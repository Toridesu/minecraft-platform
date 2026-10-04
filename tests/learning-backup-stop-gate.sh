#!/usr/bin/env bash
set -euo pipefail

# Learning exercise only: inputs simulate independently verified evidence.
# No Minecraft stop, log inspection, data copy, or AWS access occurs here.
# Production save evidence must belong to this shutdown, not an old log.
if [[ $# -ne 3 ]]; then
  printf 'Usage: bash %s <stopped|running> <confirmed|missing> <clean|failed>\n' "$0" >&2
  exit 2
fi

process_state=$1
save_evidence=$2
stop_result=$3

case "$process_state" in stopped|running) ;; *) exit 2 ;; esac
case "$save_evidence" in confirmed|missing) ;; *) exit 2 ;; esac
case "$stop_result" in clean|failed) ;; *) exit 2 ;; esac

can_begin_backup() {
  if [[ "$process_state" == "stopped" &&
        "$save_evidence" == "confirmed" &&
        "$stop_result" == "clean" ]]; then
    return 0
  fi

  return 1
}

if can_begin_backup; then
  printf 'ALLOW: backup may begin (simulation only)\n'
else
  printf 'DENY: backup must not begin\n' >&2
  exit 1
fi
