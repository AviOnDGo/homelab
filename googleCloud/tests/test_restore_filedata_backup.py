import json
import os
import shutil
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
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
            "curl",
            """
printf '%s\\n' "$@" > "$FIXTURE/curl-arguments"
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --data-binary ]]; then
    printf '%s' "$2" > "$FIXTURE/discord-payload"
    break
  fi
  shift
done
[[ "${FAIL_CURL:-0}" != 1 ]]
""",
        )
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
      [[ "${FAIL_VOLUME_LIST:-0}" != 1 ]] || exit 1
      for volume in freshrss_filedata npm_filedata pihole_filedata vaultwarden_filedata; do
        if [[ ",${MISSING_VOLUMES:-}," != *",$volume,"* ]]; then
          printf '%s\\n' "$volume"
        fi
      done
    fi ;;
  build) ;;
  run) [[ "${SECRET_CONFLICT:-0}" != 1 ]] ;;
  ps) [[ "${EXISTING_CONTAINER:-0}" != 1 ]] || echo existing-container ;;
  stop) [[ "${FAIL_STOP:-0}" != 1 ]] ;;
  rm) [[ "${FAIL_REMOVE:-0}" != 1 ]] ;;
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
        self.assertFalse((self.work / "discord-payload").exists())
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

    def test_missing_volumes_are_skipped_and_reported_to_discord(self):
        self.env["MISSING_VOLUMES"] = "pihole_filedata,vaultwarden_filedata"
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        override = (self.work / "override.yml").read_text()
        self.assertIn("freshrss_filedata:/backup-sources/freshrss:ro", override)
        self.assertIn("npm_filedata:/backup-sources/npm:ro", override)
        self.assertNotIn("pihole_filedata", override)
        self.assertNotIn("vaultwarden_filedata", override)
        payload = json.loads((self.work / "discord-payload").read_text())
        self.assertIn("pihole_filedata", payload["content"])
        self.assertIn("vaultwarden_filedata", payload["content"])
        self.assertIn("pihole_filedata", result.stderr)
        self.assertNotIn(
            self.env["DISCORD_WEBHOOK_URL"],
            (self.work / "curl-arguments").read_text() + result.stdout + result.stderr,
        )

    def test_missing_volume_alert_uses_real_http_request(self):
        curl = shutil.which("curl")
        if not curl:
            self.skipTest("curl is unavailable")
        received = []

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                length = int(self.headers["Content-Length"])
                received.append(json.loads(self.rfile.read(length)))
                self.send_response(204)
                self.end_headers()

            def log_message(self, format, *args):
                pass

        server = HTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(thread.join)
        self.addCleanup(server.shutdown)
        self.executable("curl", f'exec "{curl}" "$@"')
        self.env["DISCORD_WEBHOOK_URL"] = f"http://127.0.0.1:{server.server_port}/alert"
        self.env["MISSING_VOLUMES"] = "pihole_filedata"
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(received), 1)
        self.assertIn("pihole_filedata", received[0]["content"])
        self.assertEqual(received[0]["allowed_mentions"], {"parse": []})

    def test_no_volumes_or_unavailable_docker_preserves_existing_container(self):
        self.env["EXISTING_CONTAINER"] = "1"
        for variables in (
            {"MISSING_VOLUMES": (
                "freshrss_filedata,npm_filedata,pihole_filedata,vaultwarden_filedata"
            )},
            {"FAIL_VOLUME_LIST": "1"},
        ):
            with self.subTest(variables=variables):
                self.env.update(variables)
                result = self.invoke()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("ERROR:", result.stderr)
                calls = (self.work / "docker-calls").read_text()
                self.assertNotIn(" compose ", calls)
                self.assertNotIn(" stop ", calls)
                self.assertNotIn(" rm ", calls)
                for key in variables:
                    self.env.pop(key)
                (self.work / "docker-calls").unlink()

    def test_missing_volume_notification_failure_still_starts_scheduler(self):
        self.env["MISSING_VOLUMES"] = "pihole_filedata"
        self.env["FAIL_CURL"] = "1"
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Scheduler started", result.stderr)
        self.assertIn(" compose ", (self.work / "docker-calls").read_text())

    def test_missing_volume_without_webhook_warns_and_starts(self):
        self.env["MISSING_VOLUMES"] = "pihole_filedata"
        self.env["DISCORD_WEBHOOK_URL"] = ""
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("not sent to Discord", result.stderr)
        self.assertFalse((self.work / "discord-payload").exists())
        self.assertIn(" compose ", (self.work / "docker-calls").read_text())

    def test_conflicting_secret_prevents_start(self):
        self.env["EXISTING_CONTAINER"] = "1"
        for variables in (
            {"SECRET_VOLUME": "1", "SECRET_CONFLICT": "1"},
        ):
            with self.subTest(variables=variables):
                self.env.update(variables)
                result = self.invoke()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("ERROR:", result.stderr)
                calls = (self.work / "docker-calls").read_text()
                self.assertNotIn(" compose ", calls)
                self.assertNotIn(" stop ", calls)
                self.assertNotIn(" rm ", calls)
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

    def test_existing_container_is_stopped_and_removed_before_start(self):
        self.env["EXISTING_CONTAINER"] = "1"
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = (self.work / "docker-calls").read_text().splitlines()
        self.assertIn(
            "filedata-backup-gcp ps -a --filter name=^/filedata-backup$ "
            "--format {{.ID}}",
            calls,
        )
        stop = calls.index("filedata-backup-gcp stop existing-container")
        remove = calls.index("filedata-backup-gcp rm existing-container")
        compose = next(i for i, call in enumerate(calls) if " compose " in call)
        self.assertLess(stop, remove)
        self.assertLess(remove, compose)

    def test_container_removal_failure_prevents_start(self):
        self.env["EXISTING_CONTAINER"] = "1"
        for failure in ("FAIL_STOP", "FAIL_REMOVE"):
            with self.subTest(failure=failure):
                self.env[failure] = "1"
                result = self.invoke()
                self.assertNotEqual(result.returncode, 0)
                calls = (self.work / "docker-calls").read_text()
                self.assertNotIn(" compose ", calls)
                if failure == "FAIL_STOP":
                    self.assertNotIn(" rm ", calls)
                self.env.pop(failure)
                (self.work / "docker-calls").unlink()

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
