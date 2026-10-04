#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
checker="$repo_dir/scripts/check-minecraft-stop-log.sh"

# Synthetic messages, not real player/server data.
prefix='[12:00:00] [Server thread/INFO]: '
stopping="${prefix}Stopping server"
players="${prefix}Saving players"
worlds="${prefix}Saving worlds"
overworld="${prefix}ThreadedAnvilChunkStorage (world): All chunks are saved"
end="${prefix}ThreadedAnvilChunkStorage (DIM1): All chunks are saved"
nether="${prefix}ThreadedAnvilChunkStorage (DIM-1): All chunks are saved"
complete="${prefix}ThreadedAnvilChunkStorage: All dimensions are saved"
error='[12:00:01] [Server thread/ERROR]: Failed to save player data'
warning='[12:00:01] [Server thread/WARN]: Unexpected shutdown condition'
normal=$(printf '%s\n' "$stopping" "$players" "$worlds" "$overworld" "$end" "$nether" "$complete")
passed=0
run_case() {
  local name=$1 expected=$2 fragment=$3 actual=0 output
  output=$(printf '%s\n' "$fragment" | bash "$checker" 2>&1) || actual=$?
  if [[ "$actual" -ne "$expected" ]]; then
    printf 'FAIL %s: expected %s, got %s: %s\n' "$name" "$expected" "$actual" "$output" >&2
    exit 1
  fi
  printf 'PASS %s\n' "$name"
  passed=$((passed+1))
}
run_case normal 0 "$normal"
run_case dimension_order_can_vary 0 "$(printf '%s\n' "$stopping" "$players" "$worlds" "$nether" "$overworld" "$end" "$complete")"
run_case empty 1 ''
run_case startup_save_only 1 "$(printf '%s\n' "$overworld" "$end" "$nether" "$complete")"
run_case stale_completion_before_stop 1 "$(printf '%s\n' "$complete" "$normal")"
run_case missing_players 1 "$(printf '%s\n' "$stopping" "$worlds" "$overworld" "$end" "$nether" "$complete")"
run_case missing_dimension 1 "$(printf '%s\n' "$stopping" "$players" "$worlds" "$overworld" "$end" "$complete")"
run_case missing_completion 1 "$(printf '%s\n' "$stopping" "$players" "$worlds" "$overworld" "$end" "$nether")"
run_case error_before_completion 1 "$(printf '%s\n' "$stopping" "$players" "$error" "$worlds" "$overworld" "$end" "$nether" "$complete")"
run_case error_after_completion 1 "$(printf '%s\n' "$normal" "$error")"
run_case warning_after_completion 1 "$(printf '%s\n' "$normal" "$warning")"
run_case duplicate_shutdown 1 "$(printf '%s\n' "$normal" "$stopping")"
printf '%s passed, 0 failed\n' "$passed"
