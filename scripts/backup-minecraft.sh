#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/minecraft-operation-common.sh"
[[ $# -eq 0 ]] || pmp_fail 'this fixed backup operation accepts no arguments'
pmp_acquire_operation_lock
pmp_load_storage_identity
bash "$script_dir/check-minecraft-storage.sh" "$expected_volume" "$expected_uuid"
python3 "$script_dir/minecraft-backup.py" preflight
evidence_dir=$(pmp_new_operation_dir backup)
pmp_capture_stop_evidence "$evidence_dir" "$script_dir/check-minecraft-stop-log.sh"
bash "$script_dir/check-minecraft-storage.sh" "$expected_volume" "$expected_uuid"
# FD 9 is held throughout; do not call the standalone stop script and lose it.
python3 "$script_dir/minecraft-backup.py" backup "$evidence_dir" "$expected_volume" "$expected_uuid"
printf 'Backup checks passed; Minecraft remains stopped. Evidence: %s\n' "$evidence_dir"
