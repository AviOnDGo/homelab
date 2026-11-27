import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "googleCloud" / "restore-filedata-backup.sh"


class FiledataBackupRestoreTests(unittest.TestCase):
    def setUp(self):
        fixture = tempfile.TemporaryDirectory()
        self.addCleanup(fixture.cleanup)
        self.work = Path(fixture.name)
        self.env = {
            **os.environ,
            "PATH": f"{self.work}:{os.environ['PATH']}",
            "HOME": str(self.work),
            "FIXTURE": str(self.work),
            "VM_NAME": "test-vm",
            "PROJECT_ID": "test-project",
            "ZONE": "test-zone",
            "DROPBOX_AUTH_TOKEN": "access-$test-token",
            "DROPBOX_REFRESH_TOKEN": "refresh-'$test-token",
            "GPG_PASSPHRASE": 'pass-$test-"\\phrase',
            "DISCORD_WEBHOOK_URL": "https://example.invalid/$test",
        }
        self.executable(
            "gcloud",
            'printf "%s\\n" "$@" > "$FIXTURE/arguments"\n'
            'for arg in "$@"; do command="$arg"; done\nexec bash -c "$command"',
        )
        self.executable("sudo", 'exec "$@"')
        self.executable(
            "docker",
            """
echo "$COMPOSE_PROJECT_NAME $*" >> "$FIXTURE/docker-calls"
case "$1" in
  volume)
    if [[ "$2" == inspect ]]; then
      if [[ "$3" == filedata-backup-gcp_gpg-secrets ]]; then
        [[ "${SECRET_VOLUME:-0}" == 1 ]]
      else
        [[ "$3" != "${MISSING_VOLUME:-}" ]]
      fi
    elif [[ "$2" == ls ]]; then
      printf '%s\\n' freshrss_filedata npm_filedata pihole_filedata vaultwarden_filedata
    fi ;;
  build) ;;
  run) [[ "${SECRET_CONFLICT:-0}" != 1 ]] ;;
  compose)
    cp "$3/docker-compose.yml" "$FIXTURE/compose.yml"
    cp "$3/workflow-input" "$FIXTURE/workflow-input"
    cp "$3/path.prod" "$FIXTURE/path.prod"
    cp "$7" "$FIXTURE/override.yml"
    [[ "${FAIL_COMPOSE:-0}" != 1 ]] ;;
  *) exit 1 ;;
esac
""",
        )

    def executable(self, name, body):
        path = self.work / name
        path.write_text(f"#!/bin/bash\nset -eu\n{body}\n", encoding="utf-8")
        path.chmod(0o755)

    def invoke(self):
        return subprocess.run(
            [str(SCRIPT)], cwd=ROOT, env=self.env, text=True,
            capture_output=True, check=False, timeout=20,
        )

    def test_remote_start_and_literal_credentials(self):
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = (self.work / "docker-calls").read_text()
        self.assertIn("filedata-backup-gcp compose", calls)
        self.assertIn("--wait", calls)
        project_dir = next(
            line.split(" --project-directory ", 1)[1].split(" ", 1)[0]
            for line in calls.splitlines() if " compose " in line
        )
        self.assertFalse(Path(project_dir).exists())
        arguments = (self.work / "arguments").read_text()
        for name in (
            "DROPBOX_AUTH_TOKEN", "DROPBOX_REFRESH_TOKEN", "GPG_PASSPHRASE",
            "DISCORD_WEBHOOK_URL",
        ):
            self.assertNotIn(self.env[name], arguments + result.stdout + result.stderr)
        if not shutil.which("docker"):
            self.skipTest("Docker Compose unavailable for credential verification")
        result = subprocess.run(
            [
                shutil.which("docker"), "compose", "--env-file", "/dev/null",
                "--project-directory", str(self.work),
                "-f", str(self.work / "compose.yml"),
                "-f", str(self.work / "override.yml"), "config", "--format", "json",
            ],
            env={"PATH": os.defpath, "HOME": str(self.work)},
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        values = json.loads(result.stdout)["services"]["filedata-backup"]["environment"]
        for name in (
            "DROPBOX_AUTH_TOKEN", "DROPBOX_REFRESH_TOKEN", "GPG_PASSPHRASE",
            "DISCORD_WEBHOOK_URL",
        ):
            self.assertEqual(values[name].replace("$$", "$"), self.env[name])
        for name in ("FRESHRSS", "NPM", "PIHOLE", "VAULTWARDEN"):
            self.assertEqual(values[f"{name}_DROPBOX_PATH"], f"/Apps/{name.lower()}")

    def test_missing_volume_or_conflicting_secret_prevents_start(self):
        for variables in (
            {"MISSING_VOLUME": "pihole_filedata"},
            {"SECRET_VOLUME": "1", "SECRET_CONFLICT": "1"},
        ):
            with self.subTest(variables=variables):
                self.env.update(variables)
                result = self.invoke()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("ERROR:", result.stderr)
                self.assertNotIn(" compose ", (self.work / "docker-calls").read_text())
                for key in variables:
                    self.env.pop(key)
                (self.work / "docker-calls").unlink()

    def test_invalid_credentials_and_compose_failure_are_reported(self):
        self.env["GPG_PASSPHRASE"] = "invalid\npassphrase"
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.work / "arguments").exists())
        self.env["GPG_PASSPHRASE"] = "passphrase"
        self.env["DROPBOX_AUTH_TOKEN"] = 'bad"token'
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assertFalse((self.work / "arguments").exists())
        self.env["DROPBOX_AUTH_TOKEN"] = "valid-token"
        self.env["FAIL_COMPOSE"] = "1"
        self.assertNotEqual(self.invoke().returncode, 0)

    def test_existing_empty_secret_volume_allows_rerun(self):
        self.env["SECRET_VOLUME"] = "1"
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(" run --rm ", (self.work / "docker-calls").read_text())

    def test_workflow_waits_for_all_source_restores(self):
        deployment = (ROOT / ".github/workflows/gcp-vm-deploy.yml").read_text()
        job = deployment.split("\n  restore-filedata-backup:\n", 1)[1].split(
            "\n  teardown:", 1
        )[0]
        self.assertIn(
            "needs: [apply, restore-npm, restore-freshrss, "
            "restore-vaultwarden, restore-pihole]",
            job,
        )
        self.assertNotIn("\n    if:", job)
        workflow = (
            ROOT / ".github/workflows/gcp-filedata-backup-restore.yml"
        ).read_text()
        self.assertIn("  workflow_dispatch:", workflow)
        self.assertIn("      group: service-restore", workflow)
        for name in (
            "DROPBOX_AUTH_TOKEN", "DROPBOX_REFRESH_TOKEN", "GPG_PASSPHRASE",
            "DISCORD_WEBHOOK_URL",
        ):
            self.assertIn(f"{name}: ${{{{ secrets.{name} }}}}", job)
            self.assertIn(f"{name}: ${{{{ secrets.{name} }}}}", workflow)


if __name__ == "__main__":
    unittest.main()
