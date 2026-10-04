#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/minecraft-operation-common.sh"
[[ $# -eq 3 ]] || pmp_fail 'provide pinned manifest key, version and SHA-256'
pmp_acquire_operation_lock
pmp_load_storage_identity
bash "$script_dir/check-minecraft-storage.sh" "$expected_volume" "$expected_uuid"
evidence_dir=$(pmp_new_operation_dir restore)
python3 "$script_dir/minecraft-restore.py" "$evidence_dir" "$expected_volume" "$expected_uuid" "$1" "$2" "$3"
printf 'Restore checks passed; Minecraft remains stopped. Evidence: %s\n' "$evidence_dir"
