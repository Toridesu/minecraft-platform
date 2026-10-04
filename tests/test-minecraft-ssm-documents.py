#!/usr/bin/env python3
"""SSM structure and shell fail-closed behavior, without SSM/AWS calls."""
import json
import os
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).parents[1] / "infra/environments/lab/session-runtime"


class DocumentTests(unittest.TestCase):
    def test_fixed_documents(self):
        for operation in ("backup", "restore"):
            doc = json.loads((ROOT / f"minecraft-{operation}-document.json").read_text())
            self.assertEqual(doc["schemaVersion"], "2.2")
            self.assertEqual(len(doc["mainSteps"]), 1)
            step = doc["mainSteps"][0]
            self.assertEqual(step["action"], "aws:runShellScript")
            self.assertEqual(step["precondition"], {"StringEquals": ["platformType", "Linux"]})
            command = "\n".join(step["inputs"]["runCommand"])
            self.assertNotIn("{{", command)
            self.assertIn(f"/usr/local/libexec/minecraft-platform/{operation}-minecraft.sh", command)
            subprocess.run(["bash", "-n"], input=command, text=True, check=True)

    def test_restore_environment_required(self):
        doc = json.loads((ROOT / "minecraft-restore-document.json").read_text())
        command = "\n".join(doc["mainSteps"][0]["inputs"]["runCommand"][:-1])
        env = {k: v for k, v in os.environ.items() if not k.startswith("SSM_")}
        result = subprocess.run(["bash", "-c", command], env=env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        for name, value in doc["parameters"].items():
            self.assertEqual(value["type"], "String")
            self.assertEqual(value["interpolationType"], "ENV_VAR")
            self.assertIsNone(re.fullmatch(value["allowedPattern"], 'x"; touch /tmp/injected; #'))


if __name__ == "__main__":
    unittest.main()
