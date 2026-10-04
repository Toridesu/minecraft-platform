#!/usr/bin/env bash
set -euo pipefail
# Run only in a disposable Linux container as root. No AWS/systemd is used.
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
library="$repo_dir/scripts/minecraft-operation-common.sh"
source "$library"
[[ "$EUID" -eq 0 && "$(uname -s)" == Linux ]] || pmp_fail 'use a disposable Linux container as root'
pmp_acquire_operation_lock
printf 'PASS first_operation_acquires_shared_lock\n'
result=0
bash -c 'set -euo pipefail; source "$1"; pmp_acquire_operation_lock' -- "$library" >/dev/null 2>&1 || result=$?
[[ "$result" -eq 1 ]] || pmp_fail 'second operation was not rejected'
printf 'PASS concurrent_operation_rejected\n'
flock -u 9
bash -c 'set -euo pipefail; source "$1"; pmp_acquire_operation_lock' -- "$library"
printf 'PASS released_lock_can_be_acquired\n'
printf '3 passed, 0 failed\n'
