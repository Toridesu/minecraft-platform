#!/usr/bin/env python3
"""Fixed, short-lived Vanilla lab backup. No automatic restart or cleanup."""

import base64
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import uuid

MAX_DATA_BYTES = 1024**3
MAX_FILES = 100_000
MINECRAFT_VERSION = "26.1"
JDK_VERSION = "25.0.4.1"
JAR_SHA1 = "3872a7f07a1a595e651aef8b058dfc2bb3772f46"
DATA_DIRS = ("world", "players")
JSON_FILES = ("whitelist.json", "ops.json", "banned-players.json", "banned-ips.json")
# Controlled Vanilla lab profile only. Restore regenerates other defaults using
# exactly the same release. Secret-bearing / external-service settings excluded.
PUBLIC_SETTINGS = (
    "level-name", "online-mode", "server-ip", "server-port", "enable-rcon",
    "enable-query", "white-list", "enforce-whitelist", "max-players",
    "view-distance", "simulation-distance", "pause-when-empty-seconds",
    "gamemode", "difficulty", "hardcore", "pvp", "spawn-protection",
    "allow-flight", "force-gamemode", "enable-command-block",
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def utc_now():
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def digest(path, algorithm="sha256"):
    h = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def unique_json_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key")
        result[key] = value
    return result


def write_json(path, value):
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=True, sort_keys=True, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())


def load_config(path):
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and info.st_uid == 0 and
            stat.S_IMODE(info.st_mode) == 0o600, "backup config must be root-owned 0600")
    cfg = json.loads(path.read_text(), object_pairs_hook=unique_json_pairs)
    require(set(cfg) == {"account_id", "region", "bucket", "run_id", "git_sha"},
            "unexpected backup configuration keys")
    require(all(isinstance(v, str) for v in cfg.values()), "config values must be strings")
    require(re.fullmatch(r"[0-9]{12}", cfg["account_id"]), "invalid account ID")
    require(cfg["region"] == "ap-northeast-1", "this lab uses Tokyo only")
    require(re.fullmatch(r"pmp-lab-backup-[a-z0-9-]{1,48}", cfg["bucket"]), "invalid lab bucket")
    require(re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}", cfg["run_id"]), "invalid RunId")
    require(re.fullmatch(r"[a-f0-9]{40}", cfg["git_sha"]), "invalid Git SHA")
    return cfg


class Aws:
    def __init__(self, cfg):
        self.cfg = cfg

    def call(self, service, operation, *args):
        # Fixed EC2 role credentials and standard AWS endpoints, not an inherited
        # user profile, endpoint override, or credential environment variable.
        env = {k: v for k, v in os.environ.items() if not k.startswith("AWS_")}
        env.update(AWS_CONFIG_FILE="/dev/null", AWS_SHARED_CREDENTIALS_FILE="/dev/null",
                   AWS_REGION=self.cfg["region"], AWS_DEFAULT_REGION=self.cfg["region"],
                   AWS_STS_REGIONAL_ENDPOINTS="regional", AWS_MAX_ATTEMPTS="2")
        command = ["aws", service, operation, *map(str, args), "--region", self.cfg["region"],
                   "--output", "json", "--no-cli-pager"]
        result = subprocess.run(command, check=True, capture_output=True, text=True,
                                timeout=300, env=env)
        return json.loads(result.stdout, object_pairs_hook=unique_json_pairs)

    def preflight(self):
        identity = self.call("sts", "get-caller-identity")
        require(identity.get("Account") == self.cfg["account_id"], "AWS account mismatch")
        expected = f'arn:aws:sts::{self.cfg["account_id"]}:assumed-role/pmp-lab-minecraft-instance/'
        require(identity.get("Arn", "").startswith(expected), "unexpected EC2 role")
        location = self.call("s3api", "get-bucket-location", "--bucket", self.cfg["bucket"],
                             "--expected-bucket-owner", self.cfg["account_id"])
        require(location.get("LocationConstraint") == self.cfg["region"], "bucket region mismatch")

    def put_and_verify(self, path, key, work):
        require(key.startswith(f'backups/{self.cfg["run_id"]}/'), "key outside run prefix")
        sha = digest(path)
        checksum = base64.b64encode(bytes.fromhex(sha)).decode("ascii")
        result = self.call("s3api", "put-object", "--bucket", self.cfg["bucket"], "--key", key,
                           "--body", path, "--if-none-match", "*", "--storage-class", "STANDARD",
                           "--server-side-encryption", "AES256", "--checksum-algorithm", "SHA256",
                           "--checksum-sha256", checksum, "--expected-bucket-owner", self.cfg["account_id"])
        # Preserve the returned version even if later validation fails. No Delete
        # permission / automatic cloud cleanup; partial objects need final cleanup.
        write_json(work / (path.name + ".put-response.json"), result)
        version = result.get("VersionId")
        require(isinstance(version, str) and version and version != "null", "versioning not enabled")
        require(result.get("ServerSideEncryption") == "AES256", "unexpected encryption")
        require(result.get("ChecksumSHA256") == checksum, "upload checksum mismatch")
        downloaded = work / (path.name + ".readback")
        require(not downloaded.exists(), "readback path already exists")
        read = self.call("s3api", "get-object", "--bucket", self.cfg["bucket"], "--key", key,
                         "--version-id", version, "--checksum-mode", "ENABLED",
                         "--expected-bucket-owner", self.cfg["account_id"], downloaded)
        write_json(work / (path.name + ".get-response.json"), read)
        require(read.get("VersionId") == version and read.get("ServerSideEncryption") == "AES256",
                "readback version/encryption mismatch")
        require(read.get("ContentLength") == path.stat().st_size and
                read.get("ChecksumSHA256") == checksum, "readback metadata mismatch")
        require(downloaded.stat().st_size == path.stat().st_size and digest(downloaded) == sha,
                "downloaded data checksum mismatch")
        return {"key": key, "version_id": version, "sha256": sha, "bytes": path.stat().st_size}


def public_properties(source):
    settings = {}
    for line in source.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith(("#", "!")):
            continue
        key, separator, value = line.partition("=")
        require(separator and key not in settings, "unsupported or duplicate property syntax")
        settings[key] = value
    required = {"level-name": "world", "online-mode": "true", "server-ip": "",
                "server-port": "25565", "enable-rcon": "false", "enable-query": "false",
                "white-list": "true", "enforce-whitelist": "true"}
    require(all(settings.get(k) == v for k, v in required.items()), "unexpected lab server settings")
    for key in ("resource-pack", "text-filtering-config"):
        require(not settings.get(key, ""), "external-service settings are unsupported in this lab")
    require(settings.get("management-server-enabled", "false") == "false", "management server must be disabled")
    public = {k: settings[k] for k in PUBLIC_SETTINGS if k in settings}
    require(all("\\" not in v for v in public.values()), "escaped public properties are unsupported")
    numeric = {"server-port": (25565, 25565), "max-players": (1, 2),
               "view-distance": (2, 10), "simulation-distance": (2, 10),
               "pause-when-empty-seconds": (0, 60), "spawn-protection": (0, 16)}
    boolean = {"online-mode", "enable-rcon", "enable-query", "white-list", "enforce-whitelist",
               "hardcore", "pvp", "allow-flight", "force-gamemode", "enable-command-block"}
    for key, value in public.items():
        if key in numeric:
            low, high = numeric[key]
            require(re.fullmatch(r"[0-9]{1,5}", value) and low <= int(value) <= high,
                    "numeric setting outside the controlled lab profile")
        elif key in boolean:
            require(value in ("true", "false"), "invalid boolean setting")
        elif key == "gamemode":
            require(value in ("survival", "creative", "adventure", "spectator"), "invalid gamemode")
        elif key == "difficulty":
            require(value in ("peaceful", "easy", "normal", "hard"), "invalid difficulty")
    return public


def stage_archive(source, work):
    require(source.is_dir() and not source.is_symlink(), "invalid source directory")
    require((source / "world/level.dat").is_file(), "world/level.dat is required")
    device = source.stat().st_dev
    paths = []
    total = 0
    for name in DATA_DIRS + JSON_FILES + ("server.properties", "eula.txt"):
        path = source / name
        if not path.exists() and not path.is_symlink():
            require(name in JSON_FILES and name != "whitelist.json", "required backup input is missing")
            continue
        candidates = [path]
        while candidates:
            item = candidates.pop()
            info = item.lstat()
            require(info.st_dev == device, "nested filesystem is unsupported")
            if stat.S_ISDIR(info.st_mode):
                require(name in DATA_DIRS, "expected regular configuration file")
                candidates.extend(sorted(item.iterdir(), reverse=True))
            else:
                require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1, "links/special files are unsupported")
                total += info.st_size
            paths.append(item)
            require(len(paths) <= MAX_FILES and total <= MAX_DATA_BYTES, "backup exceeds lab limits")
        if name in DATA_DIRS:
            require(path.is_dir(), "data directory is required")
    require(shutil.disk_usage(work).free >= total * 4 + 512 * 1024**2, "insufficient staging space")
    public = public_properties(source / "server.properties")
    eula = [line for line in (source / "eula.txt").read_text().splitlines()
            if line and not line.startswith("#")]
    require(eula == ["eula=true"], "EULA acceptance is not confirmed")
    stage = work / "staging"
    stage.mkdir(mode=0o700)
    for item in paths:
        relative = item.relative_to(source)
        if str(relative) in ("server.properties", "eula.txt"):
            continue
        dest = stage / relative
        if item.is_dir():
            dest.mkdir(mode=0o700, parents=True, exist_ok=True)
        else:
            dest.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            if item.name in JSON_FILES and item.parent == source:
                require(isinstance(json.loads(item.read_text(), object_pairs_hook=unique_json_pairs), list),
                        "invalid access-list JSON")
            shutil.copyfile(item, dest, follow_symlinks=False)
            dest.chmod(0o600)
            require(digest(item) == digest(dest), "staging copy mismatch")
    with (stage / "server.properties").open("x", encoding="utf-8") as stream:
        stream.write("# Non-secret Vanilla lab settings; other defaults regenerate on the same release.\n")
        for key, value in public.items():
            stream.write(f"{key}={value}\n")
    with (stage / "eula.txt").open("x", encoding="utf-8") as stream:
        stream.write("eula=true\n")
    archive = work / "world.tar.gz"
    with tarfile.open(archive, "x:gz", dereference=False) as tar:
        for item in sorted(stage.iterdir()):
            tar.add(item, arcname=item.name)
    require(archive.stat().st_size <= MAX_DATA_BYTES + 16 * 1024**2, "archive exceeds lab limit")
    return archive, public, total


def stopped_check():
    result = subprocess.run(["systemctl", "show", "minecraft.service", "--property=ActiveState,MainPID,ControlPID,Result"],
                            check=True, capture_output=True, text=True, timeout=15)
    props = dict(line.split("=", 1) for line in result.stdout.splitlines())
    require(props == {"ActiveState": "inactive", "MainPID": "0", "ControlPID": "0", "Result": "success"},
            "Minecraft is not successfully stopped")


def _run_backup(cfg, source, work, storage, aws, check_stopped):
    require(not (work / "backup-success.json").exists(), "success receipt already exists")
    invocation = (work / "invocation.id").read_text().strip()
    point = (work / "process-stopped.utc").read_text().strip()
    require(re.fullmatch(r"[a-f0-9]{32}", invocation), "missing validated stop invocation")
    dt.datetime.strptime(point, "%Y-%m-%dT%H:%M:%SZ")
    capture = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex
    prefix = f'backups/{cfg["run_id"]}/{capture}/'
    # Persist the prefix before any writes so even an uncertain PutObject response
    # can be investigated and cleaned up without dropping resources from state.
    write_json(work / "attempt.json", {"bucket": cfg["bucket"], "prefix": prefix, "run_id": cfg["run_id"]})
    check_stopped()
    os.sync()
    archive, public, total = stage_archive(source, work)
    check_stopped()
    archive_record = aws.put_and_verify(archive, prefix + "world.tar.gz", work)
    check_stopped()
    manifest = {
        "schema_version": 1, "profile": "vanilla-lab-v1", "run_id": cfg["run_id"],
        "capture_id": capture, "git_sha": cfg["git_sha"], "consistency": "stopped-save-confirmed",
        "consistency_utc": point, "archive_verified_utc": utc_now(), "invocation_id": invocation,
        "minecraft_version": MINECRAFT_VERSION, "jdk_version": JDK_VERSION, "server_jar_sha1": JAR_SHA1,
        "storage_at_backup": storage, "data_bytes": total, "public_settings": public,
        "bucket": cfg["bucket"], "archive": archive_record,
        "includes": [p.name for p in sorted((work / "staging").iterdir())],
    }
    manifest_path = work / "manifest.json"
    write_json(manifest_path, manifest)
    manifest_record = aws.put_and_verify(manifest_path, prefix + "manifest.json", work)
    check_stopped()
    receipt = {"run_id": cfg["run_id"], "capture_id": capture, "bucket": cfg["bucket"],
               "archive": archive_record, "manifest": manifest_record, "transfer_completed_utc": utc_now()}
    write_json(work / "backup-success.json", receipt)
    return receipt


def run_backup(cfg, source, work, storage, aws, check_stopped=stopped_check):
    try:
        return _run_backup(cfg, source, work, storage, aws, check_stopped)
    except (OSError, ValueError, subprocess.SubprocessError, tarfile.TarError) as exc:
        failure = {"failed_utc": utc_now(), "error_type": type(exc).__name__}
        if isinstance(exc, ValueError):
            failure["reason"] = str(exc)
        if isinstance(exc, subprocess.CalledProcessError):
            failure["returncode"] = exc.returncode
            # Root-private evidence only; never include this file in the archive
            # or print raw CLI stderr / credential-related messages to SSM output.
            failure["private_stderr"] = (exc.stderr or "")[:16384]
        if work.is_dir() and not (work / "backup-failure.json").exists():
            write_json(work / "backup-failure.json", failure)
        raise


def main():
    require(os.geteuid() == 0, "root is required")
    os.umask(0o077)
    require(Path("/proc/self/fd/9").resolve() == Path("/run/minecraft-operations/operation.lock"),
            "shared operation lock must be inherited")
    fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)
    cfg = load_config(Path("/etc/minecraft/backup.json"))
    aws = Aws(cfg)
    aws.preflight()
    jar = Path("/srv/minecraft/server/server.jar")
    require(not jar.is_symlink() and digest(jar, "sha1") == JAR_SHA1, "server JAR version mismatch")
    version = subprocess.run(["/opt/microsoft-jdk-25.0.4.1/bin/java", "-version"], check=True,
                             capture_output=True, text=True, timeout=15)
    require(f'openjdk version "{JDK_VERSION}"' in version.stderr, "JDK version mismatch")
    if sys.argv[1:] == ["preflight"]:
        print("Backup preflight passed; no stop/upload performed.")
        return
    require(len(sys.argv) == 5 and sys.argv[1] == "backup", "invalid fixed operation arguments")
    work = Path(sys.argv[2])
    require(work.parent == Path("/var/lib/minecraft-backup") and not work.is_symlink() and
            work.name.startswith("backup-"), "invalid operation directory")
    require(work.stat().st_uid == 0 and stat.S_IMODE(work.stat().st_mode) == 0o700,
            "operation directory must be root-owned 0700")
    volume, filesystem_uuid = sys.argv[3:]
    require(re.fullmatch(r"vol-(?:[a-f0-9]{8}|[a-f0-9]{17})", volume) and
            re.fullmatch(r"[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}", filesystem_uuid),
            "invalid storage identity")
    def host_stopped_check():
        stopped_check()
        subprocess.run(["bash", str(Path(__file__).parent / "check-minecraft-storage.sh"),
                        volume, filesystem_uuid], check=True, capture_output=True, text=True, timeout=15)

    receipt = run_backup(cfg, Path("/srv/minecraft/world"), work,
                         {"volume_id": volume, "uuid": filesystem_uuid}, aws, host_stopped_check)
    print(json.dumps(receipt, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError, tarfile.TarError) as exc:
        # No credentials, raw CLI stderr or config values printed on failure.
        print(f"Backup failed ({type(exc).__name__}); preserve operation evidence and inspect partial S3 prefix.", file=sys.stderr)
        sys.exit(1)
