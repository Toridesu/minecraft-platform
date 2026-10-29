#!/usr/bin/env python3
"""Disposable Linux fixtures and fake AWS only; never invokes AWS CLI."""
import base64
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import tarfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("pmp_backup", Path(__file__).parents[1] / "scripts/minecraft-backup.py")
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)

CFG = {"account_id": "123456789012", "region": "ap-northeast-1",
       "bucket": "pmp-lab-backup-test", "run_id": "test-run", "git_sha": "a" * 40}
STORAGE = {"volume_id": "vol-0123456789abcdef0", "uuid": "11111111-2222-3333-4444-555555555555"}
PROPERTIES = """level-name=world
online-mode=true
server-ip=
server-port=25565
enable-rcon=false
enable-query=false
white-list=true
enforce-whitelist=true
view-distance=6
rcon.password=SYNTHETIC_DO_NOT_INCLUDE
management-server-secret=SYNTHETIC_DO_NOT_INCLUDE
"""


class FakeAws(backup.Aws):
    def __init__(self, mode="normal"):
        super().__init__(CFG)
        self.mode = mode
        self.objects = {}
        self.calls = []

    def call(self, service, operation, *args):
        self.calls.append((service, operation, args))
        if operation == "get-caller-identity":
            return {"Account": CFG["account_id"] if self.mode != "wrong_account" else "000000000000",
                    "Arn": f'arn:aws:sts::{CFG["account_id"]}:assumed-role/pmp-lab-minecraft-instance/session'
                    if self.mode != "wrong_role" else "arn:unexpected"}
        if operation == "get-bucket-location":
            return {"LocationConstraint": CFG["region"] if self.mode != "wrong_region" else "us-east-1"}
        values = list(args)
        key = values[values.index("--key") + 1]
        if operation == "put-object":
            if (self.mode == "archive_upload_failure" and key.endswith("world.tar.gz") or
                    self.mode == "manifest_upload_failure" and key.endswith("manifest.json")):
                raise ValueError("simulated upload failure")
            if key in self.objects:
                raise ValueError("simulated conditional write collision")
            assert values[values.index("--if-none-match") + 1] == "*"
            assert values[values.index("--expected-bucket-owner") + 1] == CFG["account_id"]
            body = Path(values[values.index("--body") + 1]).read_bytes()
            checksum = base64.b64encode(bytes.fromhex(backup.hashlib.sha256(body).hexdigest())).decode()
            assert checksum == values[values.index("--checksum-sha256") + 1]
            version = f"v{len(self.objects)+1}"
            self.objects[key] = (body, version, checksum)
            return {"VersionId": version if self.mode != "no_version" else "null",
                    "ServerSideEncryption": "AES256", "ChecksumSHA256": checksum}
        if operation == "get-object":
            body, version, checksum = self.objects[key]
            assert values[values.index("--version-id") + 1] == version
            assert values[values.index("--checksum-mode") + 1] == "ENABLED"
            assert values[values.index("--expected-bucket-owner") + 1] == CFG["account_id"]
            payload = body
            if self.mode == "readback_corruption":
                payload = bytes([body[0] ^ 1]) + body[1:]
            Path(values[-1]).write_bytes(payload)
            return {"VersionId": version if self.mode != "wrong_version" else "different",
                    "ServerSideEncryption": "AES256", "ContentLength": len(body), "ChecksumSHA256": checksum}
        raise AssertionError("unmocked operation")


class BackupTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="pmp-backup-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root / "source"
        self.work = self.root / "operation"
        self.source.mkdir()
        self.work.mkdir()
        (self.source / "world").mkdir()
        (self.source / "players/data").mkdir(parents=True)
        (self.source / "world/level.dat").write_bytes(b"synthetic world A")
        (self.source / "players/data/player.dat").write_bytes(b"synthetic inventory A")
        (self.source / "server.properties").write_text(PROPERTIES)
        (self.source / "eula.txt").write_text("# Synthetic fixture\neula=true\n")
        (self.source / "whitelist.json").write_text("[]")
        (self.source / "logs").mkdir()
        (self.source / "logs/latest.log").write_text("excluded log")
        (self.source / "local.secret").write_text("excluded synthetic secret")
        (self.work / "invocation.id").write_text("1" * 32)
        (self.work / "process-stopped.utc").write_text("2026-10-04T00:00:00Z")

    def run_backup(self, aws=None, check=lambda: None):
        # os.sync is intentionally mocked: no host-wide filesystem sync in tests.
        with patch.object(backup.os, "sync"):
            return backup.run_backup(CFG, self.source, self.work, STORAGE, aws or FakeAws(), check)

    def assert_failure(self, mode):
        aws = FakeAws(mode)
        with self.assertRaises(ValueError):
            self.run_backup(aws)
        self.assertFalse((self.work / "backup-success.json").exists())
        self.assertTrue((self.work / "backup-failure.json").exists())
        self.assertTrue((self.work / "attempt.json").exists())
        return aws

    def test_normal_archive_and_manifest_verified(self):
        aws = FakeAws()
        receipt = self.run_backup(aws)
        self.assertEqual(len(aws.objects), 2)
        self.assertEqual(receipt["archive"]["version_id"], "v1")
        self.assertEqual(receipt["manifest"]["version_id"], "v2")
        self.assertTrue((self.work / "backup-success.json").exists())
        with tarfile.open(self.work / "world.tar.gz") as tar:
            names = tar.getnames()
            self.assertIn("world/level.dat", names)
            self.assertIn("players/data/player.dat", names)
            self.assertNotIn("logs", names)
            self.assertNotIn("local.secret", names)
            public = tar.extractfile("server.properties").read()
            self.assertNotIn(b"SYNTHETIC_DO_NOT_INCLUDE", public)
            self.assertNotIn(b"rcon.password", public)
            self.assertEqual(tar.extractfile("eula.txt").read(), b"eula=true\n")
        manifest = json.loads((self.work / "manifest.json").read_text())
        self.assertEqual(manifest["archive"], receipt["archive"])
        self.assertEqual(manifest["storage_at_backup"], STORAGE)
        self.assertNotIn("SYNTHETIC_DO_NOT_INCLUDE", json.dumps(manifest))

    def test_archive_upload_failure(self):
        self.assertEqual(len(self.assert_failure("archive_upload_failure").objects), 0)

    def test_manifest_upload_failure_keeps_archive_evidence(self):
        self.assertEqual(len(self.assert_failure("manifest_upload_failure").objects), 1)
        self.assertTrue((self.work / "world.tar.gz.put-response.json").exists())

    def test_readback_checksum_mismatch(self):
        self.assert_failure("readback_corruption")

    def test_readback_version_mismatch(self):
        self.assert_failure("wrong_version")

    def test_null_version_rejected(self):
        self.assert_failure("no_version")

    def test_not_stopped_prevents_upload(self):
        aws = FakeAws()
        with self.assertRaises(ValueError):
            self.run_backup(aws, lambda: backup.require(False, "not stopped"))
        self.assertEqual(aws.calls, [])
        self.assertFalse((self.work / "backup-success.json").exists())

    def test_restart_after_staging_prevents_upload(self):
        count = 0
        def check():
            nonlocal count
            count += 1
            backup.require(count < 2, "restarted")
        aws = FakeAws()
        with self.assertRaises(ValueError):
            self.run_backup(aws, check)
        self.assertEqual(aws.calls, [])

    def test_missing_stop_evidence_prevents_upload(self):
        (self.work / "invocation.id").unlink()
        aws = FakeAws()
        with self.assertRaises(FileNotFoundError):
            self.run_backup(aws)
        self.assertEqual(aws.calls, [])

    def test_missing_players_rejected(self):
        backup.shutil.rmtree(self.source / "players")
        with self.assertRaises(ValueError):
            self.run_backup()

    def test_symlink_rejected(self):
        (self.source / "world/link").symlink_to(self.source / "local.secret")
        with self.assertRaises(ValueError):
            self.run_backup()

    def test_hardlink_rejected(self):
        backup.os.link(self.source / "world/level.dat", self.source / "world/alias.dat")
        with self.assertRaises(ValueError):
            self.run_backup()

    def test_size_limit_rejected(self):
        with patch.object(backup, "MAX_DATA_BYTES", 8), self.assertRaises(ValueError):
            self.run_backup()

    def test_wrong_world_setting_rejected(self):
        (self.source / "server.properties").write_text(PROPERTIES.replace("level-name=world", "level-name=other"))
        with self.assertRaises(ValueError):
            self.run_backup()

    def test_low_disk_space_rejected(self):
        usage = backup.shutil._ntuple_diskusage(100, 90, 10)
        with patch.object(backup.shutil, "disk_usage", return_value=usage), self.assertRaises(ValueError):
            self.run_backup()

    def test_account_role_region_preflight(self):
        FakeAws().preflight()
        for mode in ("wrong_account", "wrong_role", "wrong_region"):
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                FakeAws(mode).preflight()

    def test_missing_whitelist_rejected(self):
        (self.source / "whitelist.json").unlink()
        with self.assertRaises(ValueError):
            self.run_backup()

    def test_eula_not_accepted_rejected(self):
        (self.source / "eula.txt").write_text("eula=false\n")
        with self.assertRaises(ValueError):
            self.run_backup()

    def test_non_numeric_public_setting_rejected(self):
        (self.source / "server.properties").write_text(PROPERTIES.replace("view-distance=6", "view-distance=not-a-number"))
        with self.assertRaises(ValueError):
            self.run_backup()

    def test_external_service_config_rejected(self):
        (self.source / "server.properties").write_text(PROPERTIES + "resource-pack=https://example.invalid/pack\n")
        with self.assertRaises(ValueError):
            self.run_backup()

    def test_config_validation(self):
        config = self.root / "config.json"
        config.write_text(json.dumps(CFG))
        config.chmod(0o600)
        info = list(config.lstat())
        info[4] = 0  # Model a root-owned fixture without requiring root to run tests.
        with patch.object(Path, "lstat", return_value=os.stat_result(info)):
            self.assertEqual(backup.load_config(config), CFG)
        config.chmod(0o644)
        info = list(config.lstat())
        info[4] = 0
        with patch.object(Path, "lstat", return_value=os.stat_result(info)):
            with self.assertRaisesRegex(ValueError, "root-owned 0600"):
                backup.load_config(config)

    def test_non_root_owned_config_rejected(self):
        config = self.root / "config.json"
        config.write_text(json.dumps(CFG))
        config.chmod(0o600)
        info = list(config.lstat())
        info[4] = 12345
        with patch.object(Path, "lstat", return_value=os.stat_result(info)):
            with self.assertRaisesRegex(ValueError, "root-owned 0600"):
                backup.load_config(config)

    def test_symlink_config_rejected(self):
        config = self.root / "config.json"
        config.write_text(json.dumps(CFG))
        config.chmod(0o600)
        link = self.root / "config-link.json"
        link.symlink_to(config)
        with self.assertRaisesRegex(ValueError, "root-owned 0600"):
            backup.load_config(link)

    def test_duplicate_config_keys_rejected(self):
        config = self.root / "config.json"
        config.write_text('{"account_id":"123456789012","account_id":"000000000000"}')
        config.chmod(0o600)
        info = list(config.lstat())
        info[4] = 0
        with patch.object(Path, "lstat", return_value=os.stat_result(info)):
            with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
                backup.load_config(config)


if __name__ == "__main__":
    unittest.main(verbosity=2)
