import base64
import io
import itertools
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

    def test_allowed_restores_transport_secrets_and_service_files(self) -> None:
        for (service, directory), (force, mode) in itertools.product(
            (
                ("npm", ROOT / "securityServices" / "npm"),
                ("freshrss", ROOT / "knowledgeServices" / "freshrss"),
            ),
            (("false", "--if-missing"), ("true", "--force")),
        ):
            with self.subTest(service=service, force=force):
                self.env["SERVICE"] = service
                self.env["FORCE"] = force
                result = self.invoke()
                self.assertEqual(result.returncode, 0, result.stderr)
                arguments = self.arguments.read_text(encoding="utf-8")
                self.assertIn(f" _ {mode} {service}", arguments)
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
                            (directory / name).read_bytes(),
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

    def test_deployment_requires_successful_npm_restore(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "gcp-vm-deploy.yml").read_text(
            encoding="utf-8"
        )
        job = workflow.split("\n  restore-freshrss:\n", 1)[1].split(
            "\n  teardown:", 1
        )[0]
        self.assertIn("    needs: [apply, restore-npm]\n", job)
        self.assertNotIn("\n    if:", job)
        self.assertIn("    uses: ./.github/workflows/gcp-freshrss-restore.yml\n", job)

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

    def test_freshrss_remote_restore_uses_expected_mode_and_project(self) -> None:
        archive_file = self.work / "content"
        archive_file.write_text("test data", encoding="utf-8")
        archive_path = self.work / "backup.tar"
        with tarfile.open(archive_path, "w") as archive:
            archive.add(archive_file, arcname="content")
        self.env.update(SERVICE="freshrss", ARCHIVE=str(archive_path))
        for name, body in {
            "gcloud": 'for arg in "$@"; do command="$arg"; done\nexec bash -c "$command"',
            "sudo": 'exec "$@"',
            "docker": """
echo "$COMPOSE_PROJECT_NAME $*" >> "$ARGUMENTS"
case "$1" in
  info) ;;
  compose) ;;
  volume)
    if [[ "$2" == inspect ]]; then [[ "$FORCE" == false ]]; fi ;;
  ps) ;;
  inspect) echo false ;;
  run) cat >/dev/null ;;
  *) echo "Unexpected docker command: $*" >&2; exit 1 ;;
esac""",
            "rclone": """
case "$1" in
  lsd) ;;
  lsf) echo freshrss_2025-01-01_00-00-00.tar.zst.gpg ;;
  copy) printf encrypted > "$3/${2##*/}" ;;
  *) exit 1 ;;
esac""",
            "zstd": "cat",
            "gpg": 'cat "$ARCHIVE"',
            "jq": 'echo "{}"',
            "sleep": "exit 0",
        }.items():
            path = self.work / name
            path.write_text(f"#!/bin/bash\nset -eu\n{body}\n", encoding="utf-8")
            path.chmod(0o755)
        for force in ("false", "true"):
            with self.subTest(force=force):
                self.arguments.unlink(missing_ok=True)
                self.env["FORCE"] = force
                result = self.invoke()
                self.assertEqual(result.returncode, 0, result.stderr)
                calls = self.arguments.read_text(encoding="utf-8")
                if force == "false":
                    self.assertIn("skipping automatic restore", result.stdout)
                    self.assertNotIn(" up -d --wait ", calls)
                else:
                    self.assertIn("up -d --wait --wait-timeout 300", calls)


if __name__ == "__main__":
    unittest.main()
