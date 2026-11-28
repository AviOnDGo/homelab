import base64
import io
import json
import os
import shlex
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "backupServices" / "postgres"
TRANSPORT = ROOT / "googleCloud" / "restore-db-backup.sh"
NAMES = (
    "DROPBOX_AUTH_TOKEN", "DROPBOX_REFRESH_TOKEN", "GPG_PASSPHRASE",
    "DISCORD_WEBHOOK_URL", "FIREFLY_DB_USER", "FIREFLY_DB_PASSWORD",
    "ROMM_DB_USER", "ROMM_DB_PASSWORD", "PAPERLESS_DB_USER", "PAPERLESS_DB_PASSWORD",
    "IMMICH_DB_USER", "IMMICH_DB_PASSWORD", "INVIDIOUS_DB_USER",
    "INVIDIOUS_DB_PASSWORD", "FIREFOXSYNC_DB_USER", "FIREFOXSYNC_DB_PASSWORD",
)


class DatabaseBackupRestoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.work = self.root / "work"
        self.work.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in (
            "Dockerfile", ".dockerignore", "docker-compose.yml",
            "backup-databases.conf", "start-backup.sh", "db-backup-script.sh",
            "path.prod",
        ):
            shutil.copy(SOURCE / name, self.work / name)
        self.env = {
            **os.environ,
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "HOME": str(self.root),
            "FIXTURE": str(self.root),
            "VM_NAME": "test-vm",
            "PROJECT_ID": "test-project",
            "ZONE": "test-zone",
            "DROPBOX_AUTH_TOKEN": "test-access",
            "DROPBOX_REFRESH_TOKEN": "test-refresh",
            "GPG_PASSPHRASE": 'test-$pass"\\phrase',
            "DISCORD_WEBHOOK_URL": "https://example.invalid/test",
            "FIREFLY_DB_USER": "test-user",
            "FIREFLY_DB_PASSWORD": 'test-$password"\\value',
            "ROMM_DB_USER": "romm-user",
            "ROMM_DB_PASSWORD": "romm-password",
        }
        for service in ("PAPERLESS", "IMMICH", "INVIDIOUS", "FIREFOXSYNC"):
            self.env[f"{service}_DB_USER"] = ""
            self.env[f"{service}_DB_PASSWORD"] = ""
        self.executable(
            "docker",
            """
printf '%s\\n' "$*" >> "$FIXTURE/docker-calls"
case "$1" in
  volume)
    if [[ "$2" == ls ]]; then
      [[ "${FAIL_LIST:-0}" != 1 ]] || exit 1
      printf '%s\\n' "${VOLUMES-firefly_postgresdata}"
    else
      [[ "${SECRET_VOLUME:-0}" == 1 ]]
    fi ;;
  network) printf '%s\\n' "${NETWORKS-finance_network}" ;;
  build) ;;
  run) [[ "${SECRET_CONFLICT:-0}" != 1 ]] ;;
  ps) [[ "${EXISTING:-0}" != 1 ]] || echo existing-container ;;
  stop|rm) ;;
  compose)
    cp "$3/workflow-input" "$FIXTURE/input"
    cp "$7" "$FIXTURE/override.yml"
    cp "$3/docker-compose.yml" "$FIXTURE/compose.yml"
    if [[ "$8" == config ]]; then
      [[ "${FAIL_CONFIG:-0}" != 1 ]]
    else
      [[ "${FAIL_START:-0}" != 1 ]]
    fi ;;
  *) exit 1 ;;
esac
""",
        )
        self.executable(
            "curl",
            """
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --data-binary ]]; then
    printf '%s' "$2" > "$FIXTURE/payload"
    break
  fi
  shift
done
[[ "${FAIL_CURL:-0}" != 1 ]]
""",
        )
        self.executable(
            "gcloud",
            'printf "%s\\n" "$@" > "$FIXTURE/args"\ncat > "$FIXTURE/stream"',
        )

    def executable(self, name, body):
        path = self.bin / name
        path.write_text(f"#!/bin/bash\nset -eu\n{body}\n")
        path.chmod(0o755)

    def invoke_vm(self):
        transport = subprocess.run(
            ["bash", str(TRANSPORT)], env=self.env, capture_output=True, check=False,
            timeout=20,
        )
        self.assertEqual(transport.returncode, 0, transport.stderr.decode())
        arguments = (self.root / "args").read_text()
        command = shlex.split(arguments[arguments.index("sudo bash -c "):])
        self.assertEqual(command[:3], ["sudo", "bash", "-c"])
        self.assertEqual(len(command), 4)
        remote_script = self.root / "remote-script"
        remote_script.write_text(command[3])
        stream = io.BytesIO()
        for name in NAMES:
            stream.write(name.encode() + b"\n")
            stream.write(base64.b64encode(self.env.get(name, "").encode()) + b"\n")
        with tarfile.open(fileobj=stream, mode="w") as archive:
            for path in self.work.iterdir():
                archive.add(path, arcname=path.name)
        return subprocess.run(
            ["bash", str(remote_script)], input=stream.getvalue(),
            env=self.env, capture_output=True, check=False, timeout=20,
        )

    def invoke_vm_text(self):
        result = self.invoke_vm()
        return subprocess.CompletedProcess(
            result.args, result.returncode, result.stdout.decode(), result.stderr.decode()
        )

    def add_romm_to_prod(self):
        registry = self.work / "backup-databases.conf"
        registry.write_text(
            registry.read_text().replace(
                "romm|romm_postgresdata|default,local|",
                "romm|romm_postgresdata|default,local,prod|",
            )
        )

    def test_available_database_preflight_and_start(self):
        result = self.invoke_vm_text()
        self.assertEqual(result.returncode, 0, result.stderr)
        override = (self.root / "override.yml").read_text()
        self.assertIn("firefly_postgresdata:/var/lib/postgresql/firefly:ro", override)
        self.assertIn("backup-script.sh firefly", override)
        calls = (self.root / "docker-calls").read_text()
        self.assertIn(" config -q", calls)
        self.assertIn(" up --build --force-recreate --wait", calls)
        project_dir = next(
            line.split(" --project-directory ", 1)[1].split(" ", 1)[0]
            for line in calls.splitlines() if line.startswith("compose ")
        )
        self.assertFalse(Path(project_dir).exists())
        for value in (self.env["FIREFLY_DB_PASSWORD"], self.env["GPG_PASSPHRASE"]):
            self.assertNotIn(value, result.stdout + result.stderr + calls)

    def test_compose_receives_literal_credentials(self):
        docker = shutil.which("docker")
        if not docker:
            self.skipTest("Docker Compose is unavailable")
        result = self.invoke_vm_text()
        self.assertEqual(result.returncode, 0, result.stderr)
        shutil.copy(self.work / "path.prod", self.root / "path.prod")
        shutil.copy(self.root / "input", self.root / "workflow-input")
        result = subprocess.run(
            [
                docker, "compose", "--env-file", "/dev/null",
                "--project-directory", str(self.root),
                "-f", str(self.root / "compose.yml"),
                "-f", str(self.root / "override.yml"),
                "config", "--format", "json",
            ],
            env={"PATH": os.defpath, "HOME": str(self.root)},
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        values = json.loads(result.stdout)["services"]["db-backup"]["environment"]
        for name in ("FIREFLY_DB_PASSWORD", "GPG_PASSPHRASE"):
            self.assertEqual(values[name].replace("$$", "$"), self.env[name])

        image = "homelab/db-backup:local"
        image_check = subprocess.run(
            [docker, "image", "inspect", image], capture_output=True, check=False,
        )
        if image_check.returncode:
            self.skipTest("Local backup image is unavailable for runtime verification")
        probe = self.root / "probe.yml"
        probe.write_text(
            "services:\n  probe:\n    image: homelab/db-backup:local\n"
            "    network_mode: none\n    env_file: workflow-input\n"
        )
        result = subprocess.run(
            [
                docker, "compose", "-p", f"db-backup-test-{self.root.name}",
                "--env-file", "/dev/null", "-f", str(probe), "run", "--rm", "-T",
                "--no-deps", "--entrypoint", "/usr/bin/env", "probe",
            ],
            env={"PATH": os.defpath, "HOME": str(self.root)},
            capture_output=True, text=True, check=False, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        actual = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
        for name in ("FIREFLY_DB_PASSWORD", "GPG_PASSPHRASE"):
            self.assertEqual(actual[name], self.env[name])

    def test_missing_database_is_skipped_and_reported(self):
        self.add_romm_to_prod()
        result = self.invoke_vm_text()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Skipping romm", result.stderr)
        self.assertIn("romm", (self.root / "payload").read_text())
        self.assertNotIn("romm_postgresdata", (self.root / "override.yml").read_text())
        self.assertIn("firefly_postgresdata", (self.root / "override.yml").read_text())

    def test_missing_network_or_failed_preflight_preserves_container(self):
        for update in (
            {"NETWORKS": ""},
            {"FAIL_LIST": "1"},
            {"FAIL_CONFIG": "1"},
            {"SECRET_VOLUME": "1", "SECRET_CONFLICT": "1"},
            {"FIREFLY_DB_PASSWORD": ""},
        ):
            with self.subTest(update=update):
                fixture = self.root / "docker-calls"
                if fixture.exists():
                    fixture.unlink()
                for temporary in ("filtered-registry", "workflow-input", "preflight-bin"):
                    path = self.work / temporary
                    if path.is_dir():
                        shutil.rmtree(path)
                    elif path.exists():
                        path.unlink()
                shutil.copy(SOURCE / "docker-compose.yml", self.work / "docker-compose.yml")
                self.env.update(EXISTING="1", **update)
                result = self.invoke_vm_text()
                self.assertNotEqual(result.returncode, 0)
                calls = fixture.read_text() if fixture.exists() else ""
                self.assertNotIn("stop existing-container", calls)
                self.assertNotIn("rm existing-container", calls)
                for key in update:
                    self.env.pop(key)
                self.env["FIREFLY_DB_PASSWORD"] = 'test-$password"\\value'

    def test_alert_failure_starts_available_scheduler_and_fails(self):
        self.add_romm_to_prod()
        self.env["FAIL_CURL"] = "1"
        result = self.invoke_vm_text()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Scheduler started", result.stderr)
        self.assertIn(" up --build", (self.root / "docker-calls").read_text())

    def test_transport_rejects_multiline_and_hides_secrets_from_arguments(self):
        self.env["FIREFLY_DB_PASSWORD"] = "bad\n"
        result = subprocess.run(
            ["bash", str(TRANSPORT)], env=self.env, capture_output=True, text=True,
            check=False, timeout=20,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "args").exists())
        self.env["FIREFLY_DB_PASSWORD"] = "safe-secret"
        result = subprocess.run(
            ["bash", str(TRANSPORT)], env=self.env, capture_output=True, text=True,
            check=False, timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("safe-secret", (self.root / "args").read_text())
        self.assertIn("sudo bash -c", (self.root / "args").read_text())
        self.assertNotIn("safe-secret", result.stdout + result.stderr)
        stream = io.BytesIO((self.root / "stream").read_bytes())
        values = {}
        for _ in range(16):
            name = stream.readline().decode().strip()
            values[name] = base64.b64decode(stream.readline()).decode()
        self.assertEqual(values["FIREFLY_DB_PASSWORD"], "safe-secret")
        self.assertEqual(values["GPG_PASSPHRASE"], self.env["GPG_PASSPHRASE"])
        with tarfile.open(fileobj=stream, mode="r|") as archive:
            names = archive.getnames()
        self.assertIn("start-backup.sh", names)
        self.assertNotIn("googleCloud/restore-db-backup.sh", names)

    def test_deployment_and_manual_workflow_are_connected(self):
        workflow = (ROOT / ".github/workflows/gcp-db-backup-restore.yml").read_text()
        deployment = (ROOT / ".github/workflows/gcp-vm-deploy.yml").read_text()
        job = deployment.split("\n  restore-db-backup:\n", 1)[1].split(
            "\n  teardown:", 1
        )[0]
        self.assertIn("  workflow_dispatch:", workflow)
        self.assertIn("group: service-restore", workflow)
        self.assertIn("needs: [apply, restore-npm, restore-services]", job)
        self.assertIn("needs.restore-services.result == 'failure'", job)
        self.assertIn("uses: ./.github/workflows/gcp-db-backup-restore.yml", job)


if __name__ == "__main__":
    unittest.main()
