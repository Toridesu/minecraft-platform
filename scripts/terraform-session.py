#!/usr/bin/env python3
"""Manual disposable CI session. demo is offline; live operations require two gates."""
import argparse
from datetime import datetime, timezone, timedelta
from decimal import Decimal
import hashlib
import io
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

REPO = Path(__file__).resolve().parents[1]
PROJECT, REGION = "minecraft-platform", "ap-northeast-1"
ROOTS = {"data": "infra/environments/lab/session-data", "runtime": "infra/environments/lab/session-runtime"}
KEYS = {name: f"pmp/lab/session-{name}/terraform.tfstate" for name in ROOTS}
DATA = {
    "aws_s3_bucket.backup", "aws_s3_bucket_public_access_block.backup",
    "aws_s3_bucket_ownership_controls.backup", "aws_s3_bucket_server_side_encryption_configuration.backup",
    "aws_s3_bucket_versioning.backup", "aws_s3_bucket_lifecycle_configuration.backup", "aws_s3_bucket_policy.backup",
}
RUNTIME = {
    "aws_instance.minecraft", "aws_ebs_volume.minecraft_data", "aws_volume_attachment.minecraft_data",
    "aws_vpc.lab", "aws_subnet.public", "aws_internet_gateway.lab", "aws_route_table.public",
    "aws_route.internet", "aws_route_table_association.public", "aws_vpc_endpoint.s3",
    "aws_security_group.minecraft", "aws_vpc_security_group_ingress_rule.minecraft[0]",
    "aws_vpc_security_group_egress_rule.https", "aws_ssm_document.minecraft_backup[0]",
    "aws_ssm_document.minecraft_restore[0]",
}
# Untagged relationships must point at these owned parent resources.
LINKS = {
    "aws_volume_attachment.minecraft_data": {"instance_id": "aws_instance.minecraft", "volume_id": "aws_ebs_volume.minecraft_data"},
    "aws_route.internet": {"route_table_id": "aws_route_table.public", "gateway_id": "aws_internet_gateway.lab"},
    "aws_route_table_association.public": {"route_table_id": "aws_route_table.public", "subnet_id": "aws_subnet.public"},
    "aws_vpc_security_group_ingress_rule.minecraft[0]": {"security_group_id": "aws_security_group.minecraft"},
    "aws_vpc_security_group_egress_rule.https": {"security_group_id": "aws_security_group.minecraft"},
}
MEMBERS = {"manifest.json", "data.plan", "runtime.plan", "data.lock", "runtime.lock", "data.txt", "runtime.txt"}


def require(ok, message):
    if not ok:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def encode(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def now():
    return datetime.now(timezone.utc)


def configuration(action):
    env = os.environ
    require(env.get("GITHUB_REPOSITORY") == "Toridesu/minecraft-platform" and
            env.get("GITHUB_REPOSITORY_ID") == "1376681181" and
            env.get("GITHUB_REPOSITORY_OWNER_ID") == "160250540", "wrong repository/owner")
    require(env.get("GITHUB_REF") == "refs/heads/main" and env.get("GITHUB_EVENT_NAME") == "workflow_dispatch",
            "only manual main runs are allowed")
    source = env.get("SOURCE_SHA", "")
    require(re.fullmatch(r"[a-f0-9]{40}", source) and source == env.get("GITHUB_SHA"), "source SHA is not this main revision")
    run = env.get("LAB_RUN_ID", "")
    require(re.fullmatch(r"[a-z0-9][a-z0-9-]{0,23}", run), "invalid RunId")
    account = env.get("LAB_ACCOUNT_ID", "")
    require(re.fullmatch(r"[0-9]{12}", account), "invalid account")
    owner = env.get("LAB_OWNER", "")
    require(owner and len(owner) <= 64, "set the lab owner")
    expiry = env.get("EXPIRES_AT", "")
    end = datetime.strptime(expiry, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    if action != "cleanup":
        require(now() < end <= now() + timedelta(hours=24), "session must expire within 24 hours")
        require(env.get("COST_REVIEWED") == "true" and Decimal("0") <= Decimal(env.get("ESTIMATE_USD", "99")) < Decimal("2"),
                "review costs; estimate must be below 2 USD")
    cidr = env.get("CLIENT_CIDR", "")
    require(not cidr or isinstance(ipaddress.ip_network(cidr), ipaddress.IPv4Network) and
            ipaddress.ip_network(cidr).prefixlen == 32, "client CIDR must be one IPv4 /32")
    bucket = env.get("TF_STATE_BUCKET", "")
    require(re.fullmatch(r"pmp-terraform-state-[a-z0-9-]+", bucket), "unexpected state bucket")
    if action != "plan":
        require(env.get("CONFIRMATION") == f"DISPOSABLE:{run}", "confirm the disposable RunId")
    return {"account": account, "owner": owner, "run_id": run, "source_sha": source, "expires_at": expiry,
            "cidr": cidr, "state_bucket": bucket, "backup_bucket": f"pmp-lab-backup-{account}-{run}",
            "profile": f"{PROJECT}-ci-minecraft", "region": REGION, "project": PROJECT}


def tags(config):
    return {"Project": PROJECT, "Environment": "lab", "Owner": config["owner"],
            "RunId": config["run_id"], "DataClass": "disposable"}


def variables(config, root):
    result = {"aws_region": REGION, "project_name": PROJECT, "environment": "lab",
              "owner": config["owner"], "run_id": config["run_id"], "expires_at": config["expires_at"]}
    if root == "data":
        result.update(backup_bucket_name=config["backup_bucket"], enable_aws_backup_profile=False)
    else:
        result.update(allowed_client_cidr=config["cidr"], backup_bucket_arn="arn:aws:s3:::" + config["backup_bucket"],
                      existing_instance_profile_name=config["profile"], enable_monitoring=False)
    return result


def resource_map(module):
    result = {r["address"]: r["values"] for r in module.get("resources", []) if r.get("mode") == "managed"}
    for child in module.get("child_modules", []):
        result.update(resource_map(child))
    return result


def check_plan(plan, root, config, destroy=False):
    """No Bootstrap/IAM/KMS/unknown profile; check existing ownership and parent IDs."""
    require(root in ROOTS and plan.get("format_version", "").startswith("1."), "unsupported plan/root")
    before = resource_map(plan.get("prior_state", {}).get("values", {}).get("root_module", {}))
    after = resource_map(plan.get("planned_values", {}).get("root_module", {}))
    allowed = DATA if root == "data" else RUNTIME
    require(set(before) <= allowed and set(after) <= allowed, "state includes resources outside the CI core profile")
    expressions = {r["address"]: r.get("expressions", {}) for r in
                   plan.get("configuration", {}).get("root_module", {}).get("resources", [])}
    changes = {r["address"]: r for r in plan.get("resource_changes", []) if r.get("mode") == "managed"}
    require(set(changes) <= allowed, "plan includes a protected or unsupported resource")
    require(set(before) | set(after) <= set(changes), "plan omits managed resource ownership checks")
    for address, change in changes.items():
        actions = change["change"]["actions"]
        require(set(actions) <= ({"no-op", "delete"} if destroy else {"no-op", "create", "update", "delete"}),
                "unexpected plan operation")
        require(not change["change"].get("importing"), "imports require separate ownership review")
        for phase, values, peers in (("before", change["change"].get("before"), before),
                                      ("after", change["change"].get("after"), after)):
            if values is None:
                continue
            if root == "data":
                bucket = values.get("bucket")
                if bucket is None and phase == "after" and address != "aws_s3_bucket.backup":
                    refs = expressions.get(address, {}).get("bucket", {}).get("references", [])
                    require("aws_s3_bucket.backup" in peers and "aws_s3_bucket.backup.id" in refs,
                            "unknown bucket is not bound to the owned bucket")
                else:
                    require(bucket == config["backup_bucket"], "wrong backup bucket")
            if address not in LINKS and (root == "runtime" or address == "aws_s3_bucket.backup"):
                actual = values.get("tags_all") or values.get("tags") or {}
                require(all(actual.get(k) == v for k, v in tags(config).items()), "ownership/RunId/disposable mismatch")
            for field, parent in LINKS.get(address, {}).items():
                expected_id = peers.get(parent, {}).get("id")
                actual_id = values.get(field)
                if actual_id is not None:
                    require(expected_id is not None and actual_id == expected_id, "relationship points outside owned resources")
                else:
                    refs = expressions.get(re.sub(r"\[\d+\]$", "", address), {}).get(field, {}).get("references", [])
                    require(phase == "after" and parent in peers and
                            any(ref == parent or ref.startswith(parent + ".") for ref in refs),
                            "unknown relationship is not bound to an owned parent")
            if address == "aws_instance.minecraft":
                require(values.get("iam_instance_profile") == config["profile"], "unexpected EC2 role/profile")
                require(values.get("metadata_options", [{}])[0].get("http_tokens") == "required", "IMDSv2 required")
            if phase == "after" and address == "aws_s3_bucket_public_access_block.backup":
                require(all(values.get(k) is True for k in ("block_public_acls", "ignore_public_acls",
                        "block_public_policy", "restrict_public_buckets")), "public access protection required")
            if phase == "after" and address == "aws_s3_bucket.backup":
                require(values.get("force_destroy") is False, "implicit bucket emptying is forbidden")
    return before


class Session:
    def __init__(self, config, work):
        self.config, self.work = config, Path(work)
        self.report = {"run_id": config["run_id"], "source_sha": config["source_sha"], "steps": [], "status": "STARTED"}
        self.initialized = set()

    def run(self, args, *, cwd=None, missing=()):
        result = subprocess.run(list(map(str, args)), cwd=cwd, capture_output=True, text=True, timeout=900)
        with (self.work / "private-commands.log").open("a") as out:
            out.write(result.stdout + result.stderr)
        if result.returncode:
            match = re.search(r"\(([^)]+)\)", result.stderr)
            if match and match.group(1) in missing:
                return None
            raise RuntimeError("command failed; inspect the private command log")
        return result.stdout

    def aws(self, service, operation, *args, missing=()):
        result = self.run(["aws", service, operation, *args, "--region", REGION, "--output", "json", "--no-cli-pager"],
                          missing=missing)
        return None if result is None else json.loads(result or "{}")

    def identity(self, action):
        require(not any(k.startswith("AWS_ENDPOINT_URL") for k in os.environ), "endpoint overrides are forbidden")
        identity = self.aws("sts", "get-caller-identity")
        role = "plan" if action == "plan" else "apply"
        expected = f'arn:aws:sts::{self.config["account"]}:assumed-role/{PROJECT}-github-{role}/'
        require(identity["Account"] == self.config["account"] and identity["Arn"].startswith(expected), "wrong AWS identity")

    def initialize(self, root, lock=None):
        if root in self.initialized:
            return self.work / root
        directory = self.work / root
        directory.mkdir()
        source = REPO / ROOTS[root]
        for path in source.iterdir():
            if path.name != "backend.tf" and (path.suffix == ".tf" or path.name.endswith("-document.json")):
                shutil.copyfile(path, directory / path.name)
        (directory / "backend.tf").write_text('terraform {\n  backend "s3" {}\n}\n')
        shutil.copyfile(source / ".terraform.lock.hcl", directory / ".terraform.lock.hcl")
        if lock:
            (directory / ".terraform.lock.hcl").write_bytes(lock)
        (directory / "session.auto.tfvars.json").write_bytes(encode(variables(self.config, root)))
        args = ["terraform", "init", "-input=false", "-no-color",
                "-backend-config=bucket=" + self.config["state_bucket"], "-backend-config=key=" + KEYS[root],
                "-backend-config=region=" + REGION, "-backend-config=use_lockfile=true"]
        # Initial registry installation may add h1 in this disposable copy; no -upgrade.
        if lock:
            args.append("-lockfile=readonly")
        self.run(args, cwd=directory)
        require(self.run(["terraform", "workspace", "show"], cwd=directory).strip() == "default", "only default workspace is allowed")
        self.initialized.add(root)
        return directory

    def plan(self, root, destroy=False):
        directory = self.initialize(root)
        filename = self.work / (root + (".destroy" if destroy else ".plan"))
        self.run(["terraform", "plan", "-input=false", "-no-color", "-lock-timeout=60s", "-out=" + str(filename),
                  *(["-destroy"] if destroy else [])], cwd=directory)
        value = json.loads(self.run(["terraform", "show", "-json", str(filename)], cwd=directory))
        owned = check_plan(value, root, self.config, destroy)
        self.report["steps"].append({"step": root + ("_destroy_plan" if destroy else "_plan"), "managed_resources": len(owned)})
        return filename, owned

    def put(self, name, path):
        return self.aws("s3api", "put-object", "--bucket", self.config["state_bucket"],
                        "--key", f'ci-plans/{self.config["run_id"]}/{name}', "--body", path,
                        "--server-side-encryption", "AES256", "--expected-bucket-owner", self.config["account"])

    def saved_plan(self):
        payload = {}
        for root in ROOTS:
            path, _ = self.plan(root)
            payload[root + ".plan"] = path.read_bytes()
            payload[root + ".lock"] = (self.work / root / ".terraform.lock.hcl").read_bytes()
            payload[root + ".txt"] = self.run(["terraform", "show", "-no-color", path], cwd=self.work / root).encode()
        manifest = {"config": self.config, "state_keys": KEYS,
                    "source_locks": {r: sha((REPO / path / ".terraform.lock.hcl").read_bytes()) for r, path in ROOTS.items()},
                    "inputs": {r: sha(encode(variables(self.config, r))) for r in ROOTS},
                    "files": {name: sha(value) for name, value in payload.items()}}
        payload["manifest.json"] = encode(manifest)
        archive = self.work / "plan.tar.gz"
        with tarfile.open(archive, "w:gz") as out:
            for name, content in payload.items():
                item = tarfile.TarInfo(name)
                item.size, item.mode = len(content), 0o600
                out.addfile(item, io.BytesIO(content))
        result = self.put("plan.tar.gz", archive)
        require(result.get("VersionId") and result["VersionId"] != "null", "versioned plan storage required")
        summary = f'Plan SHA-256: {sha(archive.read_bytes())}\nS3 VersionId: {result["VersionId"]}\n'
        print(summary)
        if os.environ.get("GITHUB_STEP_SUMMARY"):
            with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as out:
                out.write(summary)

    def load_plan(self):
        version, approved = os.environ.get("PLAN_VERSION", ""), os.environ.get("PLAN_SHA256", "")
        require(version and re.fullmatch(r"[a-f0-9]{64}", approved), "approved plan hash/version required")
        archive = self.work / "approved.tar.gz"
        self.aws("s3api", "get-object", "--bucket", self.config["state_bucket"],
                 "--key", f'ci-plans/{self.config["run_id"]}/plan.tar.gz', "--version-id", version,
                 "--expected-bucket-owner", self.config["account"], archive)
        require(sha(archive.read_bytes()) == approved, "saved plan archive changed")
        payload = {}
        with tarfile.open(archive) as source:
            require(len(source.getmembers()) == len(MEMBERS), "unexpected plan archive")
            for item in source.getmembers():
                require(item.name in MEMBERS and item.isfile() and item.name not in payload and 0 < item.size < 32 * 1024**2,
                        "unsafe plan archive member")
                payload[item.name] = source.extractfile(item).read()
        manifest = json.loads(payload.pop("manifest.json"))
        require(manifest["config"] == self.config and manifest["state_keys"] == KEYS, "plan identity/inputs/expiry changed")
        require(manifest["inputs"] == {r: sha(encode(variables(self.config, r))) for r in ROOTS}, "inputs changed")
        require(manifest["source_locks"] == {r: sha((REPO / path / ".terraform.lock.hcl").read_bytes()) for r, path in ROOTS.items()}, "source lock changed")
        require(manifest["files"] == {name: sha(value) for name, value in payload.items()}, "saved plan or resolved lock changed")
        for root in ROOTS:
            directory = self.initialize(root, payload[root + ".lock"])
            plan = self.work / (root + ".approved")
            plan.write_bytes(payload[root + ".plan"])
            check_plan(json.loads(self.run(["terraform", "show", "-json", str(plan)], cwd=directory)), root, self.config)
        return {root: self.work / (root + ".approved") for root in ROOTS}

    def apply_file(self, root, plan):
        self.run(["terraform", "apply", "-input=false", "-no-color", "-lock-timeout=60s", str(plan)], cwd=self.work / root)
        self.report["steps"].append({"step": root + "_applied"})

    def smoke(self):
        value = json.loads(self.run(["terraform", "output", "-json", "ci_runtime"], cwd=self.work / "runtime"))
        result = self.aws("ec2", "describe-volumes", "--volume-ids", value["volume_id"])
        require(any(a["InstanceId"] == value["instance_id"] for a in result["Volumes"][0]["Attachments"]), "World volume is not attached")
        self.report["steps"].append({"step": "infra_smoke_passed", "game_started": False})

    def export(self):
        for root in self.initialized:
            # Private bucket only; outputs/state can contain sensitive values.
            for suffix, command in (("state", ["terraform", "state", "pull"]),
                                    ("outputs", ["terraform", "output", "-json"])):
                content = self.run(command, cwd=self.work / root)
                path = self.work / f"{root}-{suffix}.json"
                path.write_text(content)
                self.put(path.name, path)

    def empty_backup(self):
        bucket, account = self.config["backup_bucket"], self.config["account"]
        owner = self.aws("s3api", "get-bucket-tagging", "--bucket", bucket, "--expected-bucket-owner", account, missing=("NoSuchBucket",))
        if owner is None:
            return
        actual = {item["Key"]: item["Value"] for item in owner["TagSet"]}
        require(all(actual.get(k) == v for k, v in tags(self.config).items()), "backup bucket is not owned disposable data")
        args = ["--bucket", bucket, "--expected-bucket-owner", account]
        # AWS CLI auto-pagination is retained. Never use a partial --max-items list.
        uploads = self.aws("s3api", "list-multipart-uploads", *args).get("Uploads", [])
        listing = self.aws("s3api", "list-object-versions", *args)
        objects = listing.get("Versions", []) + listing.get("DeleteMarkers", [])
        require(all(item["Key"].startswith(f'backups/{self.config["run_id"]}/') for item in uploads + objects),
                "unexpected object prefix; preserve bucket for review")
        for item in uploads:
            self.aws("s3api", "abort-multipart-upload", *args, "--key", item["Key"], "--upload-id", item["UploadId"])
        for offset in range(0, len(objects), 1000):
            payload = {"Objects": [{"Key": x["Key"], "VersionId": x["VersionId"]} for x in objects[offset:offset + 1000]], "Quiet": True}
            result = self.aws("s3api", "delete-objects", *args, "--delete", encode(payload).decode())
            require(not result.get("Errors"), "S3 reported partial deletion failure")
        listing = self.aws("s3api", "list-object-versions", *args)
        require(not listing.get("Versions") and not listing.get("DeleteMarkers") and
                not self.aws("s3api", "list-multipart-uploads", *args).get("Uploads"), "bucket is not empty")

    def verify_runtime(self, owned):
        filters = [f"Name=tag:Project,Values={PROJECT}", f'Name=tag:RunId,Values={self.config["run_id"]}']
        queries = [("describe-instances", "Reservations"), ("describe-volumes", "Volumes"),
                   ("describe-vpcs", "Vpcs"), ("describe-subnets", "Subnets"),
                   ("describe-route-tables", "RouteTables"), ("describe-internet-gateways", "InternetGateways"),
                   ("describe-security-groups", "SecurityGroups"), ("describe-vpc-endpoints", "VpcEndpoints"),
                   ("describe-network-interfaces", "NetworkInterfaces"),
                   ("describe-addresses", "Addresses"), ("describe-snapshots", "Snapshots")]
        for operation, key in queries:
            result = self.aws("ec2", operation, "--filters", *filters).get(key, [])
            if operation == "describe-instances":
                result = [x for reservation in result for x in reservation["Instances"] if x["State"]["Name"] != "terminated"]
            require(not result, "core resources remain; preserve data and investigate")
        # Also probe known volume IDs: losing a tag must not hide surviving EBS.
        volumes = {v["id"] for a, v in owned.items() if a == "aws_ebs_volume.minecraft_data"}
        instance = owned.get("aws_instance.minecraft", {})
        volumes.update(v["volume_id"] for v in instance.get("root_block_device", []) if v.get("volume_id"))
        for volume in volumes:
            result = self.aws("ec2", "describe-volumes", "--volume-ids", volume, missing=("InvalidVolume.NotFound",))
            require(result is None, "known volume remains even if its tags changed")
        for name in ("pmp-lab-minecraft-backup", "pmp-lab-minecraft-restore"):
            result = self.aws("ssm", "describe-document", "--name", name, missing=("InvalidDocument",))
            require(result is None, "SSM document still exists; preserve data")

    def cleanup(self):
        path, owned = self.plan("runtime", destroy=True)
        self.plan("data", destroy=True)  # Reject another profile before deleting anything.
        try:
            self.export()
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
            self.report["steps"].append({"step": "private_export_failed"})
        self.apply_file("runtime", path)
        self.verify_runtime(owned)
        self.empty_backup()
        path, _ = self.plan("data", destroy=True)
        self.apply_file("data", path)
        for root in ROOTS:
            state = json.loads(self.run(["terraform", "show", "-json"], cwd=self.work / root))
            require(not resource_map(state.get("values", {}).get("root_module", {})), "managed state is not empty")
        absent = self.aws("s3api", "head-bucket", "--bucket", self.config["backup_bucket"],
                          "--expected-bucket-owner", self.config["account"], missing=("404", "NoSuchBucket", "NotFound"))
        require(absent is None, "backup bucket still exists")
        self.report["steps"].append({"step": "core_cleanup_verified"})
        self.report["cleanup"] = "VERIFIED"
        self.remove_plan_versions()

    def remove_plan_versions(self):
        key = f'ci-plans/{self.config["run_id"]}/plan.tar.gz'
        args = ["--bucket", self.config["state_bucket"], "--expected-bucket-owner", self.config["account"]]
        listing = self.aws("s3api", "list-object-versions", *args, "--prefix", key)
        for item in listing.get("Versions", []) + listing.get("DeleteMarkers", []):
            require(item["Key"] == key, "unexpected saved plan key")
            self.aws("s3api", "delete-object", *args, "--key", key, "--version-id", item["VersionId"])
        remaining = self.aws("s3api", "list-object-versions", *args, "--prefix", key)
        require(not remaining.get("Versions") and not remaining.get("DeleteMarkers"), "saved plan versions remain")

    def finish(self):
        log = self.work / "private-commands.log"
        if self.report["status"] != "COMPLETED" and log.exists():
            self.put("commands.log", log)
        path = self.work / "report.json"
        path.write_bytes(encode(self.report))
        self.put("report.json", path)


def demo():
    config = {"account": "123456789012", "owner": "demo", "run_id": "demo", "backup_bucket": "pmp-lab-backup-123456789012-demo"}
    values = {"bucket": config["backup_bucket"], "tags_all": tags(config), "force_destroy": False}
    plan = {"format_version": "1.2", "resource_changes": [{
        "address": "aws_s3_bucket.backup", "mode": "managed",
        "change": {"actions": ["create"], "before": None, "after": values}}]}
    check_plan(plan, "data", config)
    values["tags_all"]["RunId"] = "foreign"
    rejected = False
    try:
        check_plan(plan, "data", config)
    except ValueError:
        rejected = True
    require(rejected, "ownership guard did not reject the foreign RunId")
    print("Offline example passed: owned plan accepted; foreign RunId rejected. No AWS/Terraform operation.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("demo", "plan", "apply", "cleanup"))
    parser.add_argument("--execute", action="store_true", help="future live CI only; also needs ENABLE_LAB_AWS=true")
    args = parser.parse_args()
    if args.action == "demo":
        demo()
        return 0
    require(args.execute and os.environ.get("ENABLE_LAB_AWS") == "true", "live execution is disabled")
    os.umask(0o077)
    config = configuration(args.action)
    with tempfile.TemporaryDirectory(prefix="pmp-ci-") as work:
        session = Session(config, work)
        session.identity(args.action)
        error = None
        writes_started = False
        try:
            if args.action == "plan":
                session.saved_plan()
            elif args.action == "cleanup":
                session.cleanup()
            else:
                plans = session.load_plan()  # All checks pass BEFORE the first write.
                require(now() < datetime.strptime(config["expires_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc),
                        "saved plan expired before apply")
                writes_started = True
                try:
                    for root in ROOTS:
                        session.apply_file(root, plans[root])
                    session.smoke()
                finally:
                    session.cleanup()
            session.report["status"] = "COMPLETED"
        except (OSError, ValueError, RuntimeError, KeyError, subprocess.SubprocessError) as exc:
            error = exc
            status = ("FAILED_CLEANED" if session.report.get("cleanup") == "VERIFIED" else
                      "CLEANUP_REQUIRED" if writes_started or args.action == "cleanup" else "REFUSED")
            session.report.update(status=status, error_type=type(exc).__name__)
        finally:
            try:
                session.finish()
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
                print("Private report upload failed; remote completion is not confirmed.", file=sys.stderr)
                if error is None:
                    raise
        if error:
            raise error
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, KeyError, subprocess.SubprocessError) as exc:
        print(f"Session refused/failed ({type(exc).__name__}): {exc}", file=sys.stderr)
        sys.exit(1)
