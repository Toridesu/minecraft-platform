#!/usr/bin/env python3
"""Restore only a pinned, verified Vanilla backup onto an empty guarded EBS."""
import base64
import fcntl
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import pwd
import re
import shutil
import stat
import subprocess
import sys
import tarfile

spec = importlib.util.spec_from_file_location("backup", Path(__file__).with_name("minecraft-backup.py"))
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)
KEY_PATTERN = r"backups/[A-Za-z0-9][A-Za-z0-9_-]{0,63}/[0-9]{8}T[0-9]{6}Z-[a-f0-9]{32}/manifest\.json"


def download(aws, record, destination, limit):
    b.require(isinstance(record, dict) and set(record) == {"key", "version_id", "sha256", "bytes"}, "invalid object record")
    b.require(isinstance(record["version_id"], str) and
              re.fullmatch(r"[A-Za-z0-9._~+/=-]{1,1024}", record["version_id"]) and
              record["version_id"] != "null", "invalid pinned version")
    b.require(isinstance(record["sha256"], str) and re.fullmatch(r"[a-f0-9]{64}", record["sha256"]), "invalid checksum")
    b.require(type(record["bytes"]) is int and 0 < record["bytes"] <= limit, "object size exceeds limit")
    checksum = base64.b64encode(bytes.fromhex(record["sha256"])).decode()
    args = ("--bucket", aws.cfg["bucket"], "--key", record["key"], "--version-id", record["version_id"],
            "--expected-bucket-owner", aws.cfg["account_id"])
    for operation in ("head-object", "get-object"):
        result = aws.call("s3api", operation, *args, "--checksum-mode", "ENABLED",
                          *([destination] if operation == "get-object" else []))
        b.require(result.get("VersionId") == record["version_id"] and
                  result.get("ContentLength") == record["bytes"] and
                  result.get("ServerSideEncryption") == "AES256" and
                  result.get("ChecksumSHA256") == checksum, "object metadata mismatch")
    b.require(destination.stat().st_size == record["bytes"] and b.digest(destination) == record["sha256"], "download checksum mismatch")


def empty_target(target):
    b.require(target.is_dir() and not target.is_symlink(), "invalid restore target")
    for item in target.iterdir():
        b.require(item.name == "lost+found" and not item.is_symlink() and item.is_dir() and
                  not any(item.iterdir()), "restore target is not empty")


def extract_verified(archive, stage, manifest):
    allowed = set(b.DATA_DIRS + b.JSON_FILES + ("server.properties", "eula.txt"))
    total, seen, roots = 0, set(), set()
    with tarfile.open(archive, "r:gz") as tar:
        members = []
        for member in tar:
            path = PurePosixPath(member.name)
            b.require(member.name and not path.is_absolute() and ".." not in path.parts and
                      "\\" not in member.name and str(path) == member.name and
                      path.parts[0] in allowed and member.name not in seen, "unsafe archive path")
            b.require(member.isdir() or member.isreg(), "archive links/special files are forbidden")
            b.require(member.size >= 0 and (not member.isdir() or member.size == 0), "invalid archive member size")
            b.require(not member.sparse and not any(k in member.pax_headers for k in ("path", "linkpath")), "unsupported archive metadata")
            b.require(path.parts[0] in b.DATA_DIRS or (len(path.parts) == 1 and member.isreg()), "unexpected nested configuration")
            total += member.size
            seen.add(member.name)
            roots.add(path.parts[0])
            members.append(member)
            b.require(len(members) <= b.MAX_FILES and total <= b.MAX_DATA_BYTES, "expanded archive exceeds limits")
        b.require(roots == set(manifest["includes"]) and
                  {"world", "players", "server.properties", "eula.txt", "whitelist.json"} <= roots and
                  "world/level.dat" in seen, "incomplete archive")
        b.require(shutil.disk_usage(stage.parent).free >= total * 2 + 512 * 1024**2, "insufficient extraction space")
        stage.mkdir(mode=0o700)
        for member in members:
            dest = stage / member.name
            dest.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            if member.isdir():
                dest.mkdir(exist_ok=True, mode=0o700)
            else:
                with tar.extractfile(member) as source, dest.open("xb") as out:
                    shutil.copyfileobj(source, out)
                b.require(dest.stat().st_size == member.size, "truncated archive member")
    b.require(b.public_properties(stage / "server.properties") == manifest["public_settings"], "settings disagree with manifest")
    b.require((stage / "world/level.dat").is_file(), "level.dat must be a regular file")
    b.require((stage / "eula.txt").read_text() == "eula=true\n", "invalid EULA record")
    for name in b.JSON_FILES:
        if (stage / name).exists():
            b.require(isinstance(json.loads((stage / name).read_text(), object_pairs_hook=b.unique_json_pairs), list), "invalid access list")
    return total


def run_restore(cfg, target, work, key, version, sha, aws, guard, owner):
    try:
        b.require(re.fullmatch(KEY_PATTERN, key) and key.startswith(f'backups/{cfg["run_id"]}/'), "manifest outside selected run")
        guard()
        empty_target(target)
        # Bound the manifest before downloading; all data objects use exact versions.
        head = aws.call("s3api", "head-object", "--bucket", cfg["bucket"], "--key", key,
                        "--version-id", version, "--expected-bucket-owner", cfg["account_id"])
        record = {"key": key, "version_id": version, "sha256": sha, "bytes": head.get("ContentLength")}
        download(aws, record, work / "manifest.json", 1024 * 1024)
        manifest = json.loads((work / "manifest.json").read_text(), object_pairs_hook=b.unique_json_pairs)
        expected = {"schema_version": 1, "profile": "vanilla-lab-v1", "run_id": cfg["run_id"],
                    "bucket": cfg["bucket"], "consistency": "stopped-save-confirmed",
                    "minecraft_version": b.MINECRAFT_VERSION, "jdk_version": b.JDK_VERSION,
                    "server_jar_sha1": b.JAR_SHA1, "capture_id": key.split("/")[2]}
        b.require(isinstance(manifest, dict) and all(manifest.get(k) == v for k, v in expected.items()), "unsupported manifest")
        b.require(isinstance(manifest.get("includes"), list) and all(isinstance(x, str) for x in manifest["includes"]) and
                  len(set(manifest["includes"])) == len(manifest["includes"]), "invalid manifest inventory")
        archive_record = manifest.get("archive")
        b.require(isinstance(archive_record, dict) and archive_record.get("key") == key.rsplit("/", 1)[0] + "/world.tar.gz", "archive outside capture")
        download(aws, archive_record, work / "world.tar.gz", b.MAX_DATA_BYTES + 16 * 1024**2)
        stage = work / "staging"
        total = extract_verified(work / "world.tar.gz", stage, manifest)
        guard()
        empty_target(target)
        b.require(shutil.disk_usage(target).free >= total + 256 * 1024**2, "insufficient target space")
        b.write_json(work / "restore-attempt.json", {"manifest": record, "started_utc": b.utc_now()})
        # No overwrite / restart / automatic cleanup. An interrupted installation
        # leaves partial data and no success receipt; operator must inspect it.
        for src in sorted(stage.rglob("*"), key=lambda p: (len(p.parts), str(p))):
            guard()
            dest = target / src.relative_to(stage)
            if src.is_dir():
                dest.mkdir(mode=0o750)
            else:
                with src.open("rb") as inp, dest.open("xb") as out:
                    shutil.copyfileobj(inp, out)
                    out.flush()
                    os.fsync(out.fileno())
                b.require(b.digest(src) == b.digest(dest), "installed file checksum mismatch")
                dest.chmod(0o640)
            os.chown(dest, *owner)
        os.sync()
        guard()
        receipt = {"manifest": record, "archive": archive_record, "restored_utc": b.utc_now(), "run_id": cfg["run_id"]}
        b.write_json(work / "restore-success.json", receipt)
        return receipt
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError, tarfile.TarError) as exc:
        b.write_json(work / "restore-failure.json", {"failed_utc": b.utc_now(), "error_type": type(exc).__name__})
        raise


def main():
    b.require(os.geteuid() == 0 and len(sys.argv) == 7, "root and fixed arguments required")
    os.umask(0o077)
    b.require(Path("/proc/self/fd/9").resolve() == Path("/run/minecraft-operations/operation.lock"), "shared lock is required")
    fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)
    work, volume, filesystem_uuid, key, version, sha = sys.argv[1:]
    work = Path(work)
    info = work.lstat()
    b.require(work.parent == Path("/var/lib/minecraft-backup") and work.name.startswith("restore-") and
              stat.S_ISDIR(info.st_mode) and info.st_uid == 0 and stat.S_IMODE(info.st_mode) == 0o700, "invalid private workspace")
    cfg = b.load_config(Path("/etc/minecraft/backup.json"))
    aws = b.Aws(cfg)
    aws.preflight()
    b.require(b.digest(Path("/srv/minecraft/server/server.jar"), "sha1") == b.JAR_SHA1, "JAR mismatch")
    java = subprocess.run(["/opt/microsoft-jdk-25.0.4.1/bin/java", "-version"], check=True, capture_output=True, text=True, timeout=15)
    b.require(f'openjdk version "{b.JDK_VERSION}"' in java.stderr, "JDK mismatch")
    def guard():
        b.stopped_check()
        enabled = subprocess.run(["systemctl", "is-enabled", "minecraft.service"], capture_output=True, text=True, timeout=15)
        b.require(enabled.stdout.strip() in ("disabled", "masked"), "disable Minecraft before restore")
        subprocess.run(["bash", str(Path(__file__).with_name("check-minecraft-storage.sh")), volume, filesystem_uuid],
                       check=True, capture_output=True, text=True, timeout=15)
    account = pwd.getpwnam("minecraft")
    print(json.dumps(run_restore(cfg, Path("/srv/minecraft/world"), work, key, version, sha,
                                 aws, guard, (account.pw_uid, account.pw_gid)), sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError, tarfile.TarError) as exc:
        print(f"Restore refused/failed ({type(exc).__name__}); do not start Minecraft or erase partial evidence.", file=sys.stderr)
        sys.exit(1)
