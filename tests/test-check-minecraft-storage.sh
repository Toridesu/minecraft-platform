#!/usr/bin/env bash
set -euo pipefail

# Use a disposable Linux container. No real disk is opened or mounted.
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
checker="$repo_dir/scripts/check-minecraft-storage.sh"
task_tmp=$(mktemp -d)
mkdir "$task_tmp/bin"
cleanup() {
  rm -f -- "$task_tmp/bin/findmnt" "$task_tmp/bin/lsblk" "$task_tmp/device"
  rmdir -- "$task_tmp/bin" "$task_tmp"
}
trap cleanup EXIT

# Only the block-device file type is inspected; this node is never opened.
mknod "$task_tmp/device" b 7 255
export PMP_TEST_DEVICE="$task_tmp/device"
export PMP_TEST_UUID="11111111-2222-3333-4444-555555555555"
expected_volume="vol-0123456789abcdef0"

cat > "$task_tmp/bin/findmnt" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 5 && "$1" == "-rn" && "$2" == "--mountpoint" &&
   "$3" == "/srv/minecraft/world" && "$4" == "-o" ]] || exit 2
[[ "$PMP_TEST_CASE" != "missing_mount" ]] || exit 1
case "$5" in
  SOURCE)
    if [[ "$PMP_TEST_CASE" == "not_block_device" ]]; then
      printf '/dev/null\n'
    else
      printf '%s\n' "$PMP_TEST_DEVICE"
    fi ;;
  FSTYPE)
    if [[ "$PMP_TEST_CASE" == "wrong_filesystem" ]]; then
      printf 'xfs\n'
    else
      printf 'ext4\n'
    fi ;;
  FSROOT)
    if [[ "$PMP_TEST_CASE" == "subdirectory_mount" ]]; then
      printf '/other-world\n'
    else
      printf '/\n'
    fi ;;
  UUID)
    if [[ "$PMP_TEST_CASE" == "wrong_uuid" ]]; then
      printf 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\n'
    else
      printf '%s\n' "$PMP_TEST_UUID"
    fi ;;
  *) exit 2 ;;
esac
MOCK

cat > "$task_tmp/bin/lsblk" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 4 && "$1" == "-dn" && "$2" == "-o" &&
   "$3" == "SERIAL" && "$4" == "$PMP_TEST_DEVICE" ]] || exit 2
[[ "$PMP_TEST_CASE" != "serial_read_error" ]] || exit 1
if [[ "$PMP_TEST_CASE" == "wrong_volume" ]]; then
  printf 'volfffffffffffffffff\n'
else
  printf '  vol0123456789abcdef0  \n'
fi
MOCK

chmod 0755 "$task_tmp/bin/findmnt" "$task_tmp/bin/lsblk"
export PATH="$task_tmp/bin:$PATH"
passed=0
failed=0

run_case() {
  local case_name="$1" expected_exit="$2" expected_message="$3"
  local output actual_exit
  shift 3
  if output=$(PMP_TEST_CASE="$case_name" bash "$checker" "$@" 2>&1); then
    actual_exit=0
  else
    actual_exit=$?
  fi
  if [[ "$actual_exit" -eq "$expected_exit" && "$output" == "$expected_message" ]]; then
    printf 'PASS %s\n' "$case_name"
    passed=$((passed + 1))
  else
    printf 'FAIL %s: expected exit=%s, actual exit=%s\n%s\n' \
      "$case_name" "$expected_exit" "$actual_exit" "$output" >&2
    failed=$((failed + 1))
  fi
}

run_case normal 0 'Storage check passed' "$expected_volume" "$PMP_TEST_UUID"
run_case missing_mount 1 'Storage check failed: /srv/minecraft/world is not mounted' "$expected_volume" "$PMP_TEST_UUID"
run_case wrong_uuid 1 'Storage check failed: Filesystem UUID does not match' "$expected_volume" "$PMP_TEST_UUID"
run_case wrong_volume 1 'Storage check failed: EBS volume ID does not match' "$expected_volume" "$PMP_TEST_UUID"
run_case wrong_filesystem 1 'Storage check failed: Filesystem must be ext4' "$expected_volume" "$PMP_TEST_UUID"
run_case subdirectory_mount 1 'Storage check failed: A filesystem root must be mounted' "$expected_volume" "$PMP_TEST_UUID"
run_case not_block_device 1 'Storage check failed: Mount source is not a block device' "$expected_volume" "$PMP_TEST_UUID"
run_case serial_read_error 1 'Storage check failed: Cannot read the volume serial' "$expected_volume" "$PMP_TEST_UUID"
run_case missing_arguments 1 "Storage check failed: Usage: $checker EXPECTED_VOLUME_ID EXPECTED_UUID"
run_case empty_volume 1 'Storage check failed: Volume ID and UUID must not be empty' '' "$PMP_TEST_UUID"
run_case empty_uuid 1 'Storage check failed: Volume ID and UUID must not be empty' "$expected_volume" ''

printf '%s passed, %s failed\n' "$passed" "$failed"
[[ "$failed" -eq 0 ]]
