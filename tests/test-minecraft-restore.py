#!/usr/bin/env python3
"""Synthetic archives, fake S3 and disposable directories; no AWS/systemd."""
import base64
import importlib.util
import io
import json
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("restore", Path(__file__).parents[1] / "scripts/minecraft-restore.py")
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
CFG = {"account_id": "123456789012", "region": "ap-northeast-1", "bucket": "pmp-lab-backup-test",
       "run_id": "test-run", "git_sha": "a" * 40}
KEY = "backups/test-run/20261004T000000Z-" + "a" * 32 + "/manifest.json"
PROPERTIES = "level-name=world\nonline-mode=true\nserver-ip=\nserver-port=25565\nenable-rcon=false\nenable-query=false\nwhite-list=true\nenforce-whitelist=true\n"


class FakeAws:
    cfg = CFG

    def __init__(self, objects, corrupt=False):
        self.objects = objects
        self.corrupt = corrupt

    def call(self, service, operation, *args):
        assert service == "s3api" and operation in ("head-object", "get-object")
        args = list(args)
        key = args[args.index("--key") + 1]
        assert args[args.index("--version-id") + 1] == "v1"
        assert args[args.index("--expected-bucket-owner") + 1] == CFG["account_id"]
        data = self.objects[key]
        checksum = base64.b64encode(r.b.hashlib.sha256(data).digest()).decode()
        if operation == "get-object":
            Path(args[-1]).write_bytes(data + b"corrupt" if self.corrupt else data)
        return {"ContentLength": len(data), "VersionId": "v1", "ServerSideEncryption": "AES256", "ChecksumSHA256": checksum}


class RestoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.target = self.root / "target"
        self.work = self.root / "work"
        self.target.mkdir()
        self.work.mkdir()
        self.addCleanup(patch.stopall)
        patch.object(r.os, "sync").start()
        self.files = {"world/level.dat": b"World A", "players/data/test.dat": b"Inventory A",
                      "whitelist.json": b"[]", "server.properties": PROPERTIES.encode(), "eula.txt": b"eula=true\n"}

    def prepare(self, extra=None, mutate=None):
        archive = self.root / "archive.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            for name in ("world", "players", "players/data"):
                info = tarfile.TarInfo(name)
                info.type = tarfile.DIRTYPE
                tar.addfile(info)
            for name, data in self.files.items():
                info = tarfile.TarInfo(name)
                info.size = len(data)
                tar.addfile(info, io.BytesIO(data))
            if extra:
                tar.addfile(extra, io.BytesIO(b"x" * extra.size) if extra.isreg() else None)
        manifest = {"schema_version": 1, "profile": "vanilla-lab-v1", "run_id": CFG["run_id"],
                    "bucket": CFG["bucket"], "consistency": "stopped-save-confirmed",
                    "minecraft_version": r.b.MINECRAFT_VERSION, "jdk_version": r.b.JDK_VERSION,
                    "server_jar_sha1": r.b.JAR_SHA1, "capture_id": KEY.split("/")[2],
                    "includes": ["world", "players", "whitelist.json", "server.properties", "eula.txt"],
                    "public_settings": dict(line.split("=", 1) for line in PROPERTIES.splitlines()),
                    "archive": {"key": KEY.replace("manifest.json", "world.tar.gz"), "version_id": "v1",
                                "sha256": r.b.digest(archive), "bytes": archive.stat().st_size}}
        if mutate:
            mutate(manifest)
        payload = json.dumps(manifest).encode()
        self.sha = r.b.hashlib.sha256(payload).hexdigest()
        self.aws = FakeAws({KEY: payload, KEY.replace("manifest.json", "world.tar.gz"): archive.read_bytes()})

    def run_restore(self, guard=lambda: None, sha=None):
        return r.run_restore(CFG, self.target, self.work, KEY, "v1", sha or self.sha, self.aws,
                             guard, (os.getuid(), os.getgid()))

    def refused(self, **kwargs):
        with self.assertRaises((ValueError, OSError)):
            self.run_restore(**kwargs)
        self.assertFalse((self.work / "restore-success.json").exists())

    def test_normal(self):
        self.prepare()
        self.run_restore()
        for name, data in self.files.items():
            self.assertEqual((self.target / name).read_bytes(), data)
            self.assertEqual((self.target / name).stat().st_mode & 0o777, 0o640)

    def test_empty_lost_found(self):
        (self.target / "lost+found").mkdir()
        self.prepare()
        self.run_restore()

    def test_existing_world(self):
        (self.target / "world").mkdir()
        self.prepare()
        self.refused()

    def test_nonempty_lost_found(self):
        (self.target / "lost+found").mkdir()
        (self.target / "lost+found/file").touch()
        self.prepare()
        self.refused()

    def test_bad_hash(self):
        self.prepare()
        self.refused(sha="0" * 64)
        self.assertEqual(list(self.target.iterdir()), [])

    def test_corruption(self):
        self.prepare()
        self.aws.corrupt = True
        self.refused()

    def test_guard_failure(self):
        self.prepare()
        def guard():
            raise ValueError("wrong EBS / UUID / running")
        self.refused(guard=guard)

    def test_guard_changes_before_install(self):
        self.prepare()
        count = 0
        def guard():
            nonlocal count
            count += 1
            if count == 2:
                raise ValueError("changed mount")
        self.refused(guard=guard)
        self.assertEqual(list(self.target.iterdir()), [])

    def test_manifest_profile(self):
        self.prepare(mutate=lambda m: m.update(profile="modded"))
        self.refused()

    def test_archive_key(self):
        self.prepare(mutate=lambda m: m["archive"].update(key="other/world.tar.gz"))
        self.refused()

    def test_wrong_settings(self):
        self.prepare(mutate=lambda m: m["public_settings"].update(**{"online-mode": "false"}))
        self.refused()

    def test_missing_players(self):
        self.prepare(mutate=lambda m: m.update(includes=["world"]))
        self.refused()

    def test_unsafe_members(self):
        for name, kind in (("../outside", tarfile.REGTYPE), ("/outside", tarfile.REGTYPE),
                           ("logs/secret", tarfile.REGTYPE), ("world/link", tarfile.SYMTYPE),
                           ("world/hard", tarfile.LNKTYPE), ("world/fifo", tarfile.FIFOTYPE),
                           ("world/level.dat", tarfile.REGTYPE)):
            with self.subTest(name=name):
                if (self.work / "restore-failure.json").exists():
                    for item in self.work.iterdir():
                        item.unlink()
                member = tarfile.TarInfo(name)
                member.type = kind
                member.linkname = "/etc/passwd" if kind in (tarfile.SYMTYPE, tarfile.LNKTYPE) else ""
                self.prepare(extra=member)
                self.refused()
                self.assertEqual(list(self.target.iterdir()), [])

    def test_expanded_limit(self):
        self.prepare()
        with patch.object(r.b, "MAX_DATA_BYTES", 1):
            self.refused()

    def test_partial_install_preserved(self):
        self.prepare()
        count = 0
        def guard():
            nonlocal count
            count += 1
            if count == 4:
                raise ValueError("storage changed during copy")
        self.refused(guard=guard)
        self.assertTrue(any(self.target.iterdir()))


if __name__ == "__main__":
    unittest.main()
