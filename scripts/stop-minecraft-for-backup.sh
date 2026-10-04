#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/minecraft-operation-common.sh"
[[ $# -eq 0 ]] || pmp_fail 'this fixed host operation accepts no arguments'
pmp_acquire_operation_lock

pmp_load_storage_identity
bash "$script_dir/check-minecraft-storage.sh" "$expected_volume" "$expected_uuid"

evidence_dir=$(pmp_new_operation_dir stop)
pmp_capture_stop_evidence "$evidence_dir" "$script_dir/check-minecraft-stop-log.sh"
bash "$script_dir/check-minecraft-storage.sh" "$expected_volume" "$expected_uuid"
printf 'Stop checks passed; no archive/upload performed; Minecraft remains stopped.\n'
