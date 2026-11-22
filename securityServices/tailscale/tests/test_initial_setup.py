import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "initial_setup.sh"
SA_EMAIL = "terraform-sa@test-project.iam.gserviceaccount.com"


class InitialSetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        sdk = self.root / "share/google-cloud-sdk"
        sdk.mkdir(parents=True)
        (sdk / "path.bash.inc").write_text("")
        self.log = self.root / "gcloud.log"
        self.credentials = self.root / "credentials.json"
        self.script = self.root / "initial_setup.sh"
        self.script.write_text(
            SCRIPT.read_text()
            .replace('PROJECT_ID="your-gcp-project-id"', 'PROJECT_ID="test-project"')
            .replace(
                'BUCKET_NAME="your-tailscale-terraform-state-bucket"',
                'BUCKET_NAME="test-bucket"',
            )
        )
        self.write_command(
            "brew",
            '#!/usr/bin/env bash\n'
            'if [[ "$1" == "--prefix" ]]; then printf "%s\\n" "$HOME"; fi\n',
        )
        self.write_command(
            "gcloud",
            '#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$HOME/gcloud.log"\n',
        )

    def write_command(self, name, content):
        path = self.bin / name
        path.write_text(content)
        path.chmod(0o755)

    def run_setup(self, billing=True):
        env = {
            "HOME": str(self.root),
            "PATH": f"{self.bin}{os.pathsep}{os.defpath}",
            "CREDENTIALS_PATH": str(self.credentials),
        }
        if billing:
            env["BILLING_ACCOUNT"] = "test-billing-account"
        return subprocess.run(
            ["bash", str(self.script)], env=env, capture_output=True, text=True
        )

    def test_missing_billing_account_fails_before_bootstrap(self):
        result = self.run_setup(billing=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Set BILLING_ACCOUNT", result.stderr)
        self.assertFalse(self.log.exists())

    def test_invalid_or_mismatched_key_is_not_overwritten(self):
        for contents in ("not json", json.dumps({"client_email": "other@example.com"})):
            with self.subTest(contents=contents):
                self.credentials.write_text(contents)
                result = self.run_setup()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("set CREDENTIALS_PATH to another path", result.stderr)
                self.assertEqual(self.credentials.read_text(), contents)
                self.assertFalse(self.log.exists())

    def test_matching_key_is_reused(self):
        self.credentials.write_text(json.dumps({"client_email": SA_EMAIL}))
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("service-accounts keys create", self.log.read_text())
        self.assertIn("billing accounts add-iam-policy-binding", self.log.read_text())

    def test_missing_key_is_created(self):
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("service-accounts keys create", self.log.read_text())


if __name__ == "__main__":
    unittest.main()
