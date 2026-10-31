#!/usr/bin/env python3
"""Learning tool: save a local release and prepare rollback files. No launch/AWS."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys


ROOT = Path(__file__).resolve().parents[1] / "artifacts/minecraft-rollback"
DATA_FILES = ("server.properties", "eula.txt", "world", "players", "whitelist.json",
              "ops.json", "banned-players.json", "banned-ips.json")


def named_directory(group, name):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", name):
        raise ValueError("Use a simple snapshot/output name without path separators")
    return ROOT / group / name


def copy_entry(source, target):
    # Keep this exercise inside ordinary local files; do not follow links.
    if source.is_symlink() or source.is_dir() and any(p.is_symlink() for p in source.rglob("*")):
        raise ValueError("Use files and directories without symbolic links")
    if source.is_dir():
        shutil.copytree(source, target)
    else:
        shutil.copy2(source, target)


def jar_hash(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def write_record(path, value):
    with path.open("x", encoding="utf-8") as out:
        json.dump(value, out, ensure_ascii=False, indent=2)
        out.write("\n")


def capture(args):
    jar, data = args.server_jar, args.data_dir
    if not jar.is_file() or not (data / "world/level.dat").is_file():
        raise ValueError("Provide the old server.jar and data directory containing world/level.dat")
    for name in ("server.properties", "eula.txt"):
        if not (data / name).is_file():
            raise ValueError("The data directory needs server.properties and eula.txt")
    destination = named_directory("snapshots", args.name)
    if destination.resolve().is_relative_to(data.resolve()):
        raise ValueError("Snapshot destination must be outside the source data directory")
    destination.mkdir(parents=True, exist_ok=False)
    (destination / "server").mkdir()
    (destination / "data").mkdir()
    copy_entry(jar, destination / "server/server.jar")
    for name in DATA_FILES:
        source = data / name
        if source.exists() or source.is_symlink():
            copy_entry(source, destination / "data" / name)
    write_record(destination / "release.json", {
        "name": args.name,
        "minecraft_version": args.minecraft_version,
        "jdk_version": args.jdk_version,
        "server_jar_sha256": jar_hash(destination / "server/server.jar"),
        "captured_at": datetime.now(timezone.utc).isoformat(),
    })
    return destination


def prepare_rollback(args):
    snapshot = named_directory("snapshots", args.snapshot)
    release = json.loads((snapshot / "release.json").read_text())
    if jar_hash(snapshot / "server/server.jar") != release["server_jar_sha256"]:
        raise ValueError("The saved server.jar changed; select an intact snapshot")
    destination = named_directory("prepared", args.name)
    destination.mkdir(parents=True, exist_ok=False)
    # Restore a matching set into a NEW directory. Keep the failed update intact.
    copy_entry(snapshot / "server", destination / "server")
    copy_entry(snapshot / "data", destination / "data")
    write_record(destination / "rollback.json", {
        "snapshot": args.snapshot, "release": release, "reason": args.reason,
        "prepared_at": datetime.now(timezone.utc).isoformat(),
        "game_started": False, "runtime_verified": False,
    })
    return destination


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    save = sub.add_parser("capture", help="save a stopped, local release before editing it")
    save.add_argument("--server-jar", type=Path, required=True)
    save.add_argument("--data-dir", type=Path, required=True)
    save.add_argument("--name", required=True)
    save.add_argument("--minecraft-version", required=True)
    save.add_argument("--jdk-version", required=True)
    restore = sub.add_parser("prepare-rollback", help="copy the old release into a new recovery directory")
    restore.add_argument("--snapshot", required=True)
    restore.add_argument("--name", required=True)
    restore.add_argument("--reason", required=True)
    args = parser.parse_args()
    try:
        destination = capture(args) if args.command == "capture" else prepare_rollback(args)
        print(f"Local files prepared: {destination}")
        return 0
    except (OSError, ValueError, KeyError, shutil.Error) as exc:
        print(f"Preparation failed ({type(exc).__name__}): {exc}", file=sys.stderr)
        print("Existing source/snapshot files were retained; use a new output name after checking the cause.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
