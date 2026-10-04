#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/minecraft-operation-common.sh"
[[ $# -eq 0 ]] || pmp_fail 'this fixed host operation accepts no arguments'
pmp_acquire_operation_lock

# Root-controlled configuration is parsed as data, never executed as shell code.
config=/etc/minecraft/storage.conf
[[ -f "$config" && ! -L "$config" && "$(stat -c '%u:%a' "$config")" == '0:600' ]] ||
  pmp_fail 'storage.conf must be root-owned mode 0600'
expected_volume=
expected_uuid=
while IFS= read -r line || [[ -n "$line" ]]; do
  case "$line" in
    EXPECTED_VOLUME_ID=*)
      [[ -z "$expected_volume" ]] || pmp_fail 'duplicate volume ID'
      expected_volume=${line#*=} ;;
    EXPECTED_UUID=*)
      [[ -z "$expected_uuid" ]] || pmp_fail 'duplicate UUID'
      expected_uuid=${line#*=} ;;
    ''|'#'*) ;;
    *) pmp_fail 'unexpected storage.conf content' ;;
  esac
done <"$config"
[[ "$expected_volume" =~ ^vol-([a-f0-9]{8}|[a-f0-9]{17})$ &&
   "$expected_uuid" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$ ]] ||
  pmp_fail 'invalid expected storage identity'
bash "$script_dir/check-minecraft-storage.sh" "$expected_volume" "$expected_uuid"

evidence_root=/var/lib/minecraft-backup
[[ ! -L "$evidence_root" ]] || pmp_fail 'evidence root is a symlink'
if [[ ! -e "$evidence_root" ]]; then
  install -d -o root -g root -m 0700 "$evidence_root"
fi
[[ -d "$evidence_root" && "$(stat -c '%u:%a' "$evidence_root")" == '0:700' ]] ||
  pmp_fail 'evidence root must be root-owned mode 0700'
evidence_dir=$(mktemp -d "$evidence_root/stop-XXXXXXXX")
pmp_capture_stop_evidence "$evidence_dir" "$script_dir/check-minecraft-stop-log.sh"
bash "$script_dir/check-minecraft-storage.sh" "$expected_volume" "$expected_uuid"
printf 'Stop checks passed; no archive/upload performed; Minecraft remains stopped.\n'
