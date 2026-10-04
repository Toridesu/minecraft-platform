#!/usr/bin/env bash
set -euo pipefail

# Local synthetic-fixture exercise only. This checker never extracts files.
# Not a production EBS, locking, or application-consistency validator.
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
lab_dir="$repo_dir/evidence/t103-archive-learning"
archive="$lab_dir/backup.tar.gz"
target="$lab_dir/restore-target"

fail() { printf 'DENY: %s\n' "$1" >&2; exit 1; }
[[ $# -le 1 ]] || fail 'expected at most one local manifest filename'
manifest_name=${1:-manifest.json}
[[ "$manifest_name" =~ ^[a-zA-Z0-9_-]+\.json$ ]] || fail 'invalid local manifest filename'
manifest="$lab_dir/$manifest_name"
[[ -f "$archive" && ! -L "$archive" ]] || fail 'archive is missing or is a symlink'
[[ -f "$manifest" && ! -L "$manifest" ]] || fail 'manifest is missing or is a symlink'
[[ -d "$target" && ! -L "$target" ]] || fail 'target must be a real directory'

# Node is only used to parse JSON strictly; never source a manifest as shell code.
metadata=$(node - "$manifest" <<'NODE'
const fs = require('fs');
const m = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (m.schema_version !== 1 || m.exercise_only !== true ||
    m.consistency !== 'simulation-only' || m.archive?.file !== 'backup.tar.gz' ||
    !/^[a-f0-9]{64}$/.test(m.archive.sha256) ||
    !Number.isSafeInteger(m.archive.bytes) || m.archive.bytes <= 0 ||
    m.archive.bytes > 10485760) {
  throw new Error('Invalid learning manifest');
}
console.log(m.archive.sha256);
console.log(m.archive.bytes);
NODE
) || fail 'manifest is invalid'
mapfile -t fields <<< "$metadata"
expected_sha256=${fields[0]}
expected_bytes=${fields[1]}
read -r actual_sha256 _ < <(sha256sum "$archive")
actual_bytes=$(stat -c '%s' "$archive")
[[ "$actual_bytes" -le 10485760 ]] || fail 'archive exceeds exercise limit'
target_is_empty=false
first_entry=$(find "$target" -mindepth 1 -maxdepth 1 -print -quit) || fail 'cannot inspect target'
[[ -n "$first_entry" ]] || target_is_empty=true

can_restore() {
  if [[ "$actual_sha256" == "$expected_sha256" &&
        "$actual_bytes" -eq "$expected_bytes" &&
        "$target_is_empty" == true ]]; then
    return 0
  fi

  return 1
}

can_restore || fail 'checksum/size mismatch or target is not empty'

# This exercise accepts only the exact known fixture structure, no links.
# This is deliberately narrower than a general-purpose production restore.
members=$(tar -tzf "$archive") || fail 'cannot list archive'
expected_members=$'world/\nworld/level.dat\nplayers/\nplayers/data/\nplayers/data/test-player.dat\nwhitelist.json\nconfig-public.properties'
[[ "$members" == "$expected_members" ]] || fail 'unexpected archive members'
details=$(tar -tvzf "$archive") || fail 'cannot inspect archive types'
while IFS= read -r entry; do
  case "${entry:0:1}" in -|d) ;; *) fail 'links or special files are not allowed' ;; esac
done <<< "$details"

printf 'ALLOW: verified synthetic archive and empty restore target (no extraction performed)\n'
