import base64
import io
import os
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "googleCloud" / "restore-service.sh"


class RestoreServiceTests(unittest.TestCase):
    def setUp(self) -> None:
        fixture = tempfile.TemporaryDirectory()
        self.addCleanup(fixture.cleanup)
        self.work = Path(fixture.name)
        self.arguments = self.work / "arguments"
        self.stream = self.work / "stream"
        gcloud = self.work / "gcloud"
        gcloud.write_text(
            '#!/bin/bash\nprintf "%s\\n" "$@" > "$ARGUMENTS"\n'
            'cat > "$STREAM"\nexit "${GCLOUD_EXIT:-0}"\n',
            encoding="utf-8",
        )
        gcloud.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": f"{self.work}:{os.environ['PATH']}",
            "ARGUMENTS": str(self.arguments),
            "STREAM": str(self.stream),
            "SERVICE": "npm",
            "FORCE": "false",
            "VM_NAME": "test-vm",
            "PROJECT_ID": "test-project",
            "ZONE": "test-zone",
            "DROPBOX_AUTH_TOKEN": "test-access-token",
            "DROPBOX_REFRESH_TOKEN": "test-refresh-token",
            "GPG_PASSPHRASE": "test-passphrase",
        }

    def invoke(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(SCRIPT)],
            cwd=ROOT,
            env=self.env,
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )

    def test_allowed_npm_restore_transports_secrets_and_files(self) -> None:
        for force, mode in (("false", "--if-missing"), ("true", "--force")):
            with self.subTest(force=force):
                self.env["FORCE"] = force
                result = self.invoke()
                self.assertEqual(result.returncode, 0, result.stderr)
                arguments = self.arguments.read_text(encoding="utf-8")
                self.assertIn(f" _ {mode}", arguments)
                self.assertIn("test-vm", arguments)
                for secret in ("DROPBOX_AUTH_TOKEN", "DROPBOX_REFRESH_TOKEN", "GPG_PASSPHRASE"):
                    self.assertNotIn(self.env[secret], arguments)
                lines = self.stream.read_bytes().split(b"\n", 3)
                self.assertEqual(
                    [base64.b64decode(value).decode() for value in lines[:3]],
                    [
                        self.env["DROPBOX_AUTH_TOKEN"],
                        self.env["DROPBOX_REFRESH_TOKEN"],
                        self.env["GPG_PASSPHRASE"],
                    ],
                )
                with tarfile.open(fileobj=io.BytesIO(lines[3])) as archive:
                    self.assertEqual(
                        set(archive.getnames()), {"restore.sh", "docker-compose.yml"}
                    )
                    for name in archive.getnames():
                        self.assertEqual(
                            archive.extractfile(name).read(),
                            (ROOT / "securityServices" / "npm" / name).read_bytes(),
                        )

    def test_invalid_inputs_fail_before_connecting(self) -> None:
        for variable, value in (
            ("SERVICE", "../npm"),
            ("FORCE", "yes"),
            ("GPG_PASSPHRASE", "first\nsecond"),
            ("DROPBOX_REFRESH_TOKEN", ""),
        ):
            with self.subTest(variable=variable):
                original = self.env[variable]
                self.env[variable] = value
                result = self.invoke()
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(result.stderr)
                self.assertFalse(self.arguments.exists())
                self.env[variable] = original

    def test_ssh_failure_is_reported(self) -> None:
        self.env["GCLOUD_EXIT"] = "1"
        self.assertNotEqual(self.invoke().returncode, 0)

    def test_remote_command_runs_npm_skip_path(self) -> None:
        for name, body in {
            "gcloud": 'for arg in "$@"; do command="$arg"; done\nexec bash -c "$command"',
            "sudo": 'exec "$@"',
            "docker": 'case "$*" in "info"|"volume inspect npm_filedata") exit 0 ;; '
            '*) echo "Unexpected docker command: $*" >&2; exit 1 ;; esac',
            "rclone": "exit 0",
            "zstd": "exit 0",
            "gpg": "exit 0",
            "jq": 'echo "{}"',
        }.items():
            path = self.work / name
            path.write_text(f"#!/bin/bash\nset -eu\n{body}\n", encoding="utf-8")
            path.chmod(0o755)
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("already exists; skipping automatic restore", result.stdout)


if __name__ == "__main__":
    unittest.main()
