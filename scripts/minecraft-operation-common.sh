#!/usr/bin/env bash
# Library for fixed host operations. Source from a root-owned entry point with
# set -euo pipefail. Keep FD 9 locked through stop, staging, transfer or restore.

pmp_fail() { printf 'Minecraft operation refused: %s\n' "$1" >&2; exit 1; }

pmp_load_storage_identity() {
  local config=/etc/minecraft/storage.conf line
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
}

pmp_new_operation_dir() {
  local kind=$1 evidence_root=/var/lib/minecraft-backup
  [[ "$kind" == stop || "$kind" == backup || "$kind" == restore ]] || pmp_fail 'invalid operation kind'
  [[ ! -L "$evidence_root" ]] || pmp_fail 'evidence root is a symlink'
  if [[ ! -e "$evidence_root" ]]; then
    install -d -o root -g root -m 0700 "$evidence_root" || pmp_fail 'cannot create evidence root'
  fi
  [[ -d "$evidence_root" && "$(stat -c '%u:%a' "$evidence_root")" == '0:700' ]] ||
    pmp_fail 'evidence root must be root-owned mode 0700'
  mktemp -d "$evidence_root/$kind-XXXXXXXX" || pmp_fail 'cannot create operation directory'
}

pmp_acquire_operation_lock() {
  [[ "$EUID" -eq 0 ]] || pmp_fail 'root is required'
  local lock_dir=/run/minecraft-operations
  [[ ! -L "$lock_dir" ]] || pmp_fail 'lock directory is a symlink'
  if [[ ! -e "$lock_dir" ]]; then
    install -d -o root -g root -m 0700 "$lock_dir" || pmp_fail 'cannot create lock directory'
  fi
  [[ -d "$lock_dir" && "$(stat -c '%u:%a' "$lock_dir")" == '0:700' ]] ||
    pmp_fail 'lock directory must be root-owned mode 0700'
  [[ ! -L "$lock_dir/operation.lock" ]] || pmp_fail 'lock file is a symlink'
  if [[ -e "$lock_dir/operation.lock" ]]; then
    [[ -f "$lock_dir/operation.lock" && "$(stat -c '%u:%a' "$lock_dir/operation.lock")" == '0:600' ]] ||
      pmp_fail 'invalid lock file ownership or mode'
  fi
  umask 077
  exec 9>"$lock_dir/operation.lock" || pmp_fail 'cannot open operation lock'
  flock -n 9 || pmp_fail 'another backup/restore operation is running'
}

pmp_property() {
  local snapshot=$1 property=$2
  awk -F= -v key="$property" '
    $1 == key { count++; value = substr($0, length(key)+2) }
    END { if (count != 1) exit 1; print value }
  ' "$snapshot" || pmp_fail "missing or duplicate systemd property: $property"
}

pmp_service_snapshot() {
  systemctl show minecraft.service \
    --property=ActiveState,MainPID,ControlPID,InvocationID,ExecMainPID,ExecMainCode,ExecMainStatus,ExecMainStartTimestampMonotonic,Result \
    >"$1" || pmp_fail 'cannot read systemd service state'
}

pmp_capture_stop_evidence() {
  # Caller holds the shared lock and checks expected storage before and after.
  # Output directory must be fresh. Failure preserves evidence and never restarts.
  local evidence_dir=$1 log_checker=$2
  local invocation pid start cursor boundary latest state status code
  [[ -d "$evidence_dir" && ! -L "$evidence_dir" ]] || pmp_fail 'invalid evidence directory'
  [[ -z "$(find "$evidence_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]] ||
    pmp_fail 'evidence directory must be empty'
  [[ -f "$log_checker" && ! -L "$log_checker" ]] || pmp_fail 'missing stop log checker'

  pmp_service_snapshot "$evidence_dir/before.properties"
  [[ "$(pmp_property "$evidence_dir/before.properties" ActiveState)" == active ]] ||
    pmp_fail 'Minecraft must be running for a new consistent backup'
  [[ "$(pmp_property "$evidence_dir/before.properties" ControlPID)" == 0 ]] ||
    pmp_fail 'a service transition is running'
  invocation=$(pmp_property "$evidence_dir/before.properties" InvocationID)
  pid=$(pmp_property "$evidence_dir/before.properties" MainPID)
  start=$(pmp_property "$evidence_dir/before.properties" ExecMainStartTimestampMonotonic)
  [[ "$invocation" =~ ^[a-f0-9]{32}$ && "$pid" =~ ^[1-9][0-9]*$ &&
     "$start" =~ ^[1-9][0-9]*$ ]] || pmp_fail 'invalid running process identity'

  journalctl --sync || pmp_fail 'cannot synchronize journal before stop'
  journalctl --quiet --no-pager -o cat \
    "_SYSTEMD_UNIT=minecraft.service" "_SYSTEMD_INVOCATION_ID=$invocation" \
    >"$evidence_dir/invocation-before.log" || pmp_fail 'cannot read current invocation logs'
  grep -Eq '^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\] \[Server thread/INFO\]: Done \(' \
    "$evidence_dir/invocation-before.log" || pmp_fail 'current invocation did not finish startup'
  if grep -Eq '\[[^]]+/(ERROR|FATAL)\]:' "$evidence_dir/invocation-before.log"; then
    pmp_fail 'current invocation contains an error'
  fi
  boundary=$(journalctl --quiet --no-pager -o cat -n 1 --show-cursor \
    "_SYSTEMD_UNIT=minecraft.service" "_SYSTEMD_INVOCATION_ID=$invocation") ||
    pmp_fail 'cannot establish journal boundary'
  cursor=$(printf '%s\n' "$boundary" | sed -n 's/^-- cursor: //p')
  [[ "$cursor" =~ ^[a-zA-Z0-9=\;]+$ ]] || pmp_fail 'missing or invalid journal cursor'
  printf '%s\n' "$cursor" >"$evidence_dir/journal.cursor"

  pmp_service_snapshot "$evidence_dir/pre-stop.properties"
  for state in MainPID InvocationID ExecMainStartTimestampMonotonic ActiveState ControlPID; do
    [[ "$(pmp_property "$evidence_dir/before.properties" "$state")" == "$(pmp_property "$evidence_dir/pre-stop.properties" "$state")" ]] ||
      pmp_fail 'service changed while preparing stop'
  done
  date -u +'%Y-%m-%dT%H:%M:%SZ' >"$evidence_dir/stop-requested.utc"
  timeout 150 systemctl stop minecraft.service || pmp_fail 'stop failed or timed out'
  date -u +'%Y-%m-%dT%H:%M:%SZ' >"$evidence_dir/process-stopped.utc"
  pmp_service_snapshot "$evidence_dir/after.properties"
  [[ "$(pmp_property "$evidence_dir/after.properties" ActiveState)" == inactive &&
     "$(pmp_property "$evidence_dir/after.properties" MainPID)" == 0 &&
     "$(pmp_property "$evidence_dir/after.properties" ControlPID)" == 0 &&
     "$(pmp_property "$evidence_dir/after.properties" Result)" == success ]] ||
    pmp_fail 'service did not stop successfully'
  [[ "$(pmp_property "$evidence_dir/after.properties" ExecMainPID)" == "$pid" &&
     "$(pmp_property "$evidence_dir/after.properties" ExecMainStartTimestampMonotonic)" == "$start" ]] ||
    pmp_fail 'service process changed during stop'
  latest=$(pmp_property "$evidence_dir/after.properties" InvocationID)
  [[ -z "$latest" || "$latest" == "$invocation" ]] || pmp_fail 'another invocation appeared'
  code=$(pmp_property "$evidence_dir/after.properties" ExecMainCode)
  status=$(pmp_property "$evidence_dir/after.properties" ExecMainStatus)
  [[ "$code" == 1 && ( "$status" == 0 || "$status" == 143 ) ]] ||
    pmp_fail 'process did not exit normally with expected status'
  if kill -0 "$pid" 2>/dev/null; then pmp_fail 'original process is still present'; fi

  journalctl --sync || pmp_fail 'cannot synchronize journal after stop'
  journalctl --quiet --no-pager -o cat "--after-cursor=$cursor" \
    "_SYSTEMD_UNIT=minecraft.service" "_SYSTEMD_INVOCATION_ID=$invocation" \
    >"$evidence_dir/shutdown.log" || pmp_fail 'cannot read scoped shutdown logs'
  bash "$log_checker" <"$evidence_dir/shutdown.log" || pmp_fail 'save completion not confirmed'
  # Not backup success: expected storage and subsequent staging/upload still need checks.
  printf '%s\n' "$invocation" >"$evidence_dir/invocation.id"
  printf 'Stop evidence captured: %s\n' "$evidence_dir"
}
