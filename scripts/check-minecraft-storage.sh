#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'Storage check failed: %s\n' "$1" >&2
  exit 1
}

[[ $# -eq 2 ]] || fail "Usage: $0 EXPECTED_VOLUME_ID EXPECTED_UUID"

expected_volume="$1"
expected_uuid="$2"
mount_dir="/srv/minecraft/world"

[[ -n "$expected_volume" && -n "$expected_uuid" ]] ||
  fail "Volume ID and UUID must not be empty"

source_device=$(findmnt -rn --mountpoint "$mount_dir" -o SOURCE) ||
  fail "$mount_dir is not mounted"

[[ -b "$source_device" ]] ||
  fail "Mount source is not a block device"

[[ "$(findmnt -rn --mountpoint "$mount_dir" -o FSTYPE)" == "ext4" ]] ||
  fail "Filesystem must be ext4"

[[ "$(findmnt -rn --mountpoint "$mount_dir" -o FSROOT)" == "/" ]] ||
  fail "A filesystem root must be mounted"

[[ "$(findmnt -rn --mountpoint "$mount_dir" -o UUID)" == "$expected_uuid" ]] ||
  fail "Filesystem UUID does not match"

serial=$(lsblk -dn -o SERIAL "$source_device") ||
  fail "Cannot read the volume serial"

serial="${serial//[[:space:]]/}"
[[ "$serial" == "${expected_volume//-/}" ]] ||
  fail "EBS volume ID does not match"

printf 'Storage check passed\n'