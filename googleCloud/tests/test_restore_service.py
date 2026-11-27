import base64
import io
import itertools
import json
import os
import shutil
import sqlite3
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

    def pihole_dns_stubs(self) -> dict[str, str]:
        etc = self.work / "etc"
        etc.mkdir()
        resolver = etc / "resolv.conf"
        runtime = self.work / "runtime-resolv.conf"
        runtime.write_text("nameserver 169.254.169.254\nsearch example.internal\n")
        resolver.symlink_to(runtime)
        state = self.work / "resolver-state"
        state.write_text("enabled active\n")
        self.env.update(
            TEST_RESOLVER=str(resolver),
            TEST_RUNTIME_RESOLVER=str(runtime),
            TEST_RESOLVER_STATE=str(state),
        )
        return {
            "gcloud": """
for arg in "$@"; do command="$arg"; done
command="${command//\\/etc\\/resolv.conf/$TEST_RESOLVER}"
unset WEB_PASSWORD PIHOLE_WEB_PASSWORD
exec bash -c "$command"
""",
            "systemctl": """
[[ "$*" == "disable --now systemd-resolved" ]]
[[ "${FAIL_DISABLE:-0}" != 1 ]] || exit 1
echo "disabled inactive" > "$TEST_RESOLVER_STATE"
""",
        }

    def test_allowed_restores_transport_secrets_and_service_files(self) -> None:
        for (service, directory), (force, mode) in itertools.product(
            (
                ("npm", ROOT / "securityServices" / "npm"),
                ("freshrss", ROOT / "knowledgeServices" / "freshrss"),
                ("vaultwarden", ROOT / "securityServices" / "vaultwarden"),
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

    def test_vaultwarden_remote_restore_and_cleanup(self) -> None:
        archive_path = self.work / "backup.tar"
        with tarfile.open(archive_path, "w") as archive:
            for name in ("db.sqlite3", "rsa_key.pem"):
                data = b"test data"
                member = tarfile.TarInfo(f"./{name}")
                member.size = len(data)
                archive.addfile(member, io.BytesIO(data))
        self.env.update(
            SERVICE="vaultwarden",
            FORCE="true",
            ARCHIVE=str(archive_path),
        )
        for name, body in {
            "gcloud": 'for arg in "$@"; do command="$arg"; done\nexec bash -c "$command"',
            "sudo": 'exec "$@"',
            "docker": """
echo "${COMPOSE_PROJECT_NAME:-} $*" >> "$ARGUMENTS"
case "$1" in
  info|compose|exec) ;;
  volume) [[ "$2" != inspect ]] ;;
  ps) ;;
  inspect) echo false ;;
  run) cat >/dev/null ;;
  *) echo "Unexpected docker command: $*" >&2; exit 1 ;;
esac
""",
            "rclone": """
case "$1" in
  lsd) ;;
  lsf) echo vaultwarden_2025-01-01_00-00-00.tar.zst.gpg ;;
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
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Vaultwarden restore completed successfully", result.stdout)
        calls = self.arguments.read_text(encoding="utf-8")
        compose_call = next(line for line in calls.splitlines() if " compose -f " in line)
        self.assertTrue(compose_call.startswith("vaultwarden "))
        compose_path = Path(compose_call.split(" -f ", 1)[1].split(" ", 1)[0])
        self.assertFalse(compose_path.parent.exists())

    def test_vaultwarden_preserves_data_and_backup_state_on_failure(self) -> None:
        archive_path = self.work / "backup.tar"
        self.env.update(
            SERVICE="vaultwarden",
            FORCE="true",
            ARCHIVE=str(archive_path),
            TMPDIR=str(self.work),
        )
        for name, body in {
            "gcloud": 'for arg in "$@"; do command="$arg"; done\nexec bash -c "$command"',
            "sudo": 'exec "$@"',
            "docker": """
echo "$*" >> "$ARGUMENTS"
case "$1" in
  info|stop|start|compose) ;;
  exec) [[ "$FAILURE" != verify ]] ;;
  volume) ;;
  ps) echo vaultwarden ;;
  inspect) echo true ;;
  rm) [[ "$FAILURE" != remove ]] ;;
  run)
    if [[ "$*" == *" -i "* ]]; then
      cat >/dev/null
      [[ "$FAILURE" != extract ]]
    else
      [[ "$FAILURE" != wipe ]]
    fi ;;
  *) exit 1 ;;
esac""",
            "rclone": """
case "$1" in
  lsd) ;;
  lsf) echo vaultwarden_2025-01-01_00-00-00.tar.zst.gpg ;;
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
        cases = (
            ("missing-db", ("rsa_key.pem",), "", False, False),
            ("missing-key", ("db.sqlite3",), "", False, False),
            ("invalid-empty", ("db.sqlite3", "rsa_key.pem"), "", False, False),
            ("invalid-symlink", ("db.sqlite3", "rsa_key.pem"), "", False, False),
            ("remove", ("db.sqlite3", "rsa_key.pem"), "remove", True, True),
            ("wipe", ("db.sqlite3", "rsa_key.pem"), "wipe", True, False),
            ("extract", ("db.sqlite3", "rsa_key.pem"), "extract", True, False),
            ("verify", ("db.sqlite3", "rsa_key.pem"), "verify", True, False),
            ("success", ("db.sqlite3", "rsa_key.pem"), "", True, True),
        )
        for label, files, failure, stopped, restarted in cases:
            with self.subTest(case=label):
                with tarfile.open(archive_path, "w") as archive:
                    for name in files:
                        data = b"test data"
                        member = tarfile.TarInfo(f"./{name}")
                        if label == "invalid-empty" and name == "db.sqlite3":
                            data = b""
                        if label == "invalid-symlink" and name == "rsa_key.pem":
                            member.type = tarfile.SYMTYPE
                            member.linkname = "db.sqlite3"
                            archive.addfile(member)
                            continue
                        member.size = len(data)
                        archive.addfile(member, io.BytesIO(data))
                self.arguments.unlink(missing_ok=True)
                self.env["FAILURE"] = failure
                result = self.invoke()
                self.assertEqual(result.returncode == 0, label == "success", result.stderr)
                calls = self.arguments.read_text(encoding="utf-8").splitlines()
                self.assertEqual("stop filedata-backup" in calls, stopped)
                self.assertEqual("start filedata-backup" in calls, restarted)
                if label.startswith(("missing-", "invalid-")):
                    self.assertIn("Backup is missing", result.stderr)
                    self.assertFalse(any(call.startswith(("rm ", "run ")) for call in calls))
                if failure in ("wipe", "extract", "verify"):
                    self.assertIn("filedata-backup remains stopped", result.stderr)
                self.assertEqual(list(self.work.glob("vaultwarden-restore.*")), [])

    def test_deployment_runs_vaultwarden_after_npm(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "gcp-vm-deploy.yml").read_text(
            encoding="utf-8"
        )
        job = workflow.split("\n  restore-vaultwarden:\n", 1)[1].split(
            "\n  restore-watchtower:", 1
        )[0]
        self.assertIn("    needs: [apply, restore-npm]\n", job)
        self.assertIn("    uses: ./.github/workflows/gcp-vaultwarden-restore.yml\n", job)
        self.assertIn("      force: true\n", job)

    def test_restore_jobs_share_a_queued_concurrency_group(self) -> None:
        for service in ("npm", "freshrss", "vaultwarden", "firefly", "pihole", "watchtower"):
            with self.subTest(service=service):
                workflow = (
                    ROOT / ".github" / "workflows" / f"gcp-{service}-restore.yml"
                ).read_text(encoding="utf-8")
                job = workflow.split("\njobs:\n  restore:\n", 1)[1]
                self.assertIn(
                    "    concurrency:\n"
                    "      group: service-restore\n"
                    "      queue: max\n",
                    job,
                )

    def test_firefly_credentials_are_required_and_transported_over_stdin(self) -> None:
        self.env.update(
            SERVICE="firefly",
            FIREFLY_APP_KEY="app-$key-'fixture",
            FIREFLY_DB_USERNAME="firefly-user",
            FIREFLY_DB_PASSWORD="password-$fixture-'value\n",
            FIREFLY_STATIC_CRON_TOKEN="cron-token-fixture",
        )
        secret_names = (
            "FIREFLY_APP_KEY",
            "FIREFLY_DB_USERNAME",
            "FIREFLY_DB_PASSWORD",
            "FIREFLY_STATIC_CRON_TOKEN",
        )
        for name in secret_names:
            with self.subTest(missing=name):
                value = self.env.pop(name)
                result = self.invoke()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(name, result.stderr)
                self.assertFalse(self.arguments.exists())
                self.env[name] = value
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = self.arguments.read_text(encoding="utf-8")
        for name in secret_names:
            self.assertNotIn(self.env[name], arguments + result.stdout + result.stderr)
            self.assertNotIn(
                self.env[name].rstrip("\n"), arguments + result.stdout + result.stderr
            )
        lines = self.stream.read_bytes().split(b"\n", 7)
        self.assertEqual(
            [base64.b64decode(value).decode() for value in lines[3:7]],
            [self.env[name] for name in secret_names],
        )
        with tarfile.open(fileobj=io.BytesIO(lines[7])) as archive:
            self.assertEqual(set(archive.getnames()), {"restore.sh", "docker-compose.yml"})
            for name in archive.getnames():
                self.assertEqual(
                    archive.extractfile(name).read(),
                    (ROOT / "financialServices" / "firefly" / name).read_bytes(),
                )

    def test_pihole_password_is_required_and_transported_over_stdin(self) -> None:
        self.env["SERVICE"] = "pihole"
        self.env.pop("PIHOLE_WEB_PASSWORD", None)
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("PIHOLE_WEB_PASSWORD", result.stderr)
        self.assertFalse(self.arguments.exists())

        self.env["PIHOLE_WEB_PASSWORD"] = "pihole-$password-'fixture\n"
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = self.arguments.read_text(encoding="utf-8")
        self.assertIn(" _ --if-missing pihole", arguments)
        self.assertNotIn(
            self.env["PIHOLE_WEB_PASSWORD"].rstrip("\n"),
            arguments + result.stdout + result.stderr,
        )
        lines = self.stream.read_bytes().split(b"\n", 4)
        self.assertEqual(
            base64.b64decode(lines[3]).decode(), self.env["PIHOLE_WEB_PASSWORD"]
        )
        with tarfile.open(fileobj=io.BytesIO(lines[4])) as archive:
            self.assertEqual(set(archive.getnames()), {"restore.sh", "docker-compose.yml"})
            for name in archive.getnames():
                self.assertEqual(
                    archive.extractfile(name).read(),
                    (ROOT / "securityServices" / "pihole" / name).read_bytes(),
                )

    def test_pihole_remote_restore_modes_and_cleanup(self) -> None:
        archive_path = self.work / "backup.tar"
        with tarfile.open(archive_path, "w") as archive:
            for name in ("gravity.db", "pihole-FTL.db"):
                database = self.work / name
                with sqlite3.connect(database) as db:
                    db.execute("CREATE TABLE example (value TEXT)")
                archive.add(database, arcname=name)
        password = "pihole-$password-'fixture\n"
        self.env.update(
            SERVICE="pihole",
            PIHOLE_WEB_PASSWORD=password,
            EXPECTED_PIHOLE_PASSWORD=password,
            ARCHIVE=str(archive_path),
            TMPDIR=str(self.work),
        )
        for name, body in {
            **self.pihole_dns_stubs(),
            "sudo": 'exec "$@"',
            "docker": """
echo "${COMPOSE_PROJECT_NAME:-} $*" >> "$ARGUMENTS"
case "$1" in
  info) ;;
  exec)
    if [[ "$3" == pihole-FTL ]]; then echo ok; fi ;;
  compose)
    [[ "$WEB_PASSWORD" == "$EXPECTED_PIHOLE_PASSWORD" ]]
    [[ "$2" == -f ]]
    [[ "${FAIL_COMPOSE:-}" != 1 ]]
    if [[ "$*" == *"config --images pihole"* ]]; then echo pihole/pihole:latest; fi ;;
  volume)
    if [[ "$2" == inspect ]]; then [[ "$FORCE" == false ]]; fi ;;
  ps) ;;
  inspect) echo false ;;
  run)
    if [[ "$*" == *" --entrypoint pihole-FTL "* ]]; then
      for arg in "$@"; do
        case "$arg" in
          *:/check) staged="${arg%:/check}" ;;
          /check/*.db) database="${arg##*/}" ;;
        esac
      done
      python3 -c 'import sqlite3, sys; db = sqlite3.connect(sys.argv[1]); print("\\n".join(row[0] for row in db.execute("PRAGMA integrity_check"))) ' "$staged/$database"
    elif [[ "$*" == *" -i "* ]]; then
      cat >/dev/null
    fi ;;
  *) echo "Unexpected docker command: $*" >&2; exit 1 ;;
esac
""",
            "rclone": """
case "$1" in
  lsd) ;;
  lsf) echo pihole_2025-01-01_00-00-00.tar.zst.gpg ;;
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
        for force, fail in (("false", "0"), ("true", "0"), ("true", "1")):
            with self.subTest(force=force, fail=fail):
                self.arguments.unlink(missing_ok=True)
                self.env.update(FORCE=force, FAIL_COMPOSE=fail)
                result = self.invoke()
                calls = self.arguments.read_text(encoding="utf-8")
                self.assertEqual(result.returncode == 0, fail == "0", result.stderr)
                self.assertNotIn(password.rstrip("\n"), calls + result.stdout + result.stderr)
                if force == "false":
                    self.assertIn("skipping automatic restore", result.stdout)
                    self.assertNotIn(" compose ", calls)
                else:
                    self.assertIn("pihole compose -f", calls)
                    compose_path = next(
                        line.split(" -f ", 1)[1].split(" ", 1)[0]
                        for line in calls.splitlines() if " compose " in line
                    )
                    self.assertFalse(Path(compose_path).parent.exists())
                    self.assertEqual(" up -d" in calls, fail == "0")
                self.assertFalse(list(self.work.glob("pihole-restore.*")))

        database = self.work / "gravity.db"
        data = bytearray(database.read_bytes())
        data[100] = 0
        database.write_bytes(data)
        with tarfile.open(archive_path, "w") as archive:
            for name in ("gravity.db", "pihole-FTL.db"):
                archive.add(self.work / name, arcname=name)
        self.arguments.unlink(missing_ok=True)
        self.env.update(FORCE="true", FAIL_COMPOSE="0")
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Invalid backup database gravity.db", result.stderr)
        self.assertNotIn(
            "pihole_filedata:/restore", self.arguments.read_text(encoding="utf-8")
        )
        self.assertFalse(list(self.work.glob("pihole-restore.*")))

    def test_pihole_copies_resolver_and_disables_service(self) -> None:
        self.env.update(SERVICE="pihole", PIHOLE_WEB_PASSWORD="test-password")
        for name, body in {
            **self.pihole_dns_stubs(),
            "sudo": 'exec "$@"',
            "docker": 'case "$*" in "info"|"volume inspect pihole_filedata") exit 0 ;; *) exit 1 ;; esac',
            "rclone": "exit 0",
            "zstd": "exit 0",
            "jq": 'echo "{}"',
        }.items():
            path = self.work / name
            path.write_text(f"#!/bin/bash\nset -eu\n{body}\n", encoding="utf-8")
            path.chmod(0o755)
        resolver = Path(self.env["TEST_RESOLVER"])
        runtime = Path(self.env["TEST_RUNTIME_RESOLVER"])
        state = Path(self.env["TEST_RESOLVER_STATE"])
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(resolver.is_symlink())
        self.assertEqual(resolver.read_text(), runtime.read_text())
        self.assertEqual(state.read_text().strip(), "disabled inactive")
        self.assertEqual(self.invoke().returncode, 0)
        self.env["FAIL_DISABLE"] = "1"
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)

    def test_pihole_compose_receives_password_from_environment(self) -> None:
        docker = shutil.which("docker")
        if docker is None:
            self.skipTest("Docker Compose is not available")
        version = subprocess.run(
            [docker, "compose", "version"], capture_output=True, check=False
        )
        if version.returncode:
            self.skipTest("Docker Compose is not available")
        compose_file = self.work / "docker-compose.yml"
        shutil.copyfile(ROOT / "securityServices" / "pihole" / "docker-compose.yml", compose_file)
        env = os.environ.copy()
        env["WEB_PASSWORD"] = "pihole-$password-'fixture\n"
        result = subprocess.run(
            [
                docker,
                "compose",
                "-f",
                str(compose_file),
                "config",
                "--format",
                "json",
            ],
            cwd=self.work,
            env=env,
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        environment = json.loads(result.stdout)["services"]["pihole"]["environment"]
        # Compose escapes dollar signs when rendering its reusable configuration.
        rendered_password = environment["FTLCONF_webserver_api_password"]
        self.assertEqual(rendered_password.replace("$$", "$"), env["WEB_PASSWORD"])

    def test_firefly_remote_restore_modes_and_failure(self) -> None:
        self.env.update(
            SERVICE="firefly",
            FIREFLY_APP_KEY="app-$key-'fixture",
            FIREFLY_DB_USERNAME="firefly-user",
            FIREFLY_DB_PASSWORD="password-$fixture-'value\n",
            FIREFLY_STATIC_CRON_TOKEN="cron-token-fixture",
            TMPDIR=str(self.work),
        )
        for name, body in {
            "gcloud": 'for arg in "$@"; do command="$arg"; done\nexec bash -c "$command"',
            "sudo": 'exec "$@"',
            "docker": """
echo "${COMPOSE_PROJECT_NAME:-} $*" >> "$ARGUMENTS"
case "$1" in
  info|stop|start|run) ;;
  volume) [[ "$2" != ls ]] || echo firefly_postgresdata ;;
  ps) [[ "$*" != *"db-backup"* ]] || echo 'db-backup running' ;;
  compose)
    [[ "$APP_KEY" == "$FIREFLY_APP_KEY" ]]
    [[ "$DB_USERNAME" == "$FIREFLY_DB_USERNAME" ]]
    [[ "$DB_PASSWORD" == "$FIREFLY_DB_PASSWORD" ]]
    [[ "$STATIC_CRON_TOKEN" == "$FIREFLY_STATIC_CRON_TOKEN" ]] ;;
  exec)
    if [[ "$*" == *"ON_ERROR_STOP"* && "$*" != *"SELECT 1 FROM"* ]]; then
      cat >/dev/null
      [[ "${FAIL_IMPORT:-}" != 1 ]]
    fi ;;
  *) exit 1 ;;
esac
""",
            "rclone": """
case "$1" in
  lsd) ;;
  lsf) echo firefly_2025-01-01_00-00-00.sql.zst.gpg ;;
  copy) printf encrypted > "$3/${2##*/}" ;;
  *) exit 1 ;;
esac""",
            "zstd": "cat",
            "gpg": """printf '%s\\n' '-- PostgreSQL database dump' 'SELECT 1;' \\
  '-- PostgreSQL database dump complete'""",
            "jq": 'echo "{}"',
            "sleep": "exit 0",
        }.items():
            path = self.work / name
            path.write_text(f"#!/bin/bash\nset -eu\n{body}\n", encoding="utf-8")
            path.chmod(0o755)
        for force, fail in (("false", "0"), ("true", "0"), ("true", "1")):
            with self.subTest(force=force, fail=fail):
                self.arguments.unlink(missing_ok=True)
                self.env.update(FORCE=force, FAIL_IMPORT=fail)
                result = self.invoke()
                calls = self.arguments.read_text(encoding="utf-8")
                self.assertEqual(result.returncode == 0, fail == "0", result.stderr)
                for secret in (
                    "FIREFLY_APP_KEY", "FIREFLY_DB_USERNAME",
                    "FIREFLY_DB_PASSWORD", "FIREFLY_STATIC_CRON_TOKEN",
                ):
                    self.assertNotIn(self.env[secret], calls + result.stdout + result.stderr)
                    self.assertNotIn(
                        self.env[secret].rstrip("\n"), calls + result.stdout + result.stderr
                    )
                if force == "false":
                    self.assertIn("skipping automatic restore", result.stdout)
                    self.assertNotIn(" compose ", calls)
                else:
                    self.assertIn("firefly compose", calls)
                    self.assertIn("firefly stop db-backup", calls)
                    self.assertEqual("firefly start db-backup" in calls, fail == "0")
                    compose_path = next(
                        line.split(" -f ", 1)[1].split(" ", 1)[0]
                        for line in calls.splitlines() if " compose -f " in line
                    )
                    self.assertFalse(Path(compose_path).parent.exists())
                self.assertFalse(list(self.work.glob("firefly-restore.*")))

    def test_firefly_workflow_wires_restore_credentials(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "gcp-firefly-restore.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn("  workflow_call:\n", workflow)
        self.assertIn("  workflow_dispatch:\n", workflow)
        self.assertIn("    environment: prod\n", workflow)
        self.assertIn("          SERVICE: firefly\n", workflow)
        self.assertIn("        run: ./googleCloud/restore-service.sh\n", workflow)
        for name in (
            "DROPBOX_AUTH_TOKEN", "DROPBOX_REFRESH_TOKEN", "GPG_PASSPHRASE",
            "FIREFLY_APP_KEY", "FIREFLY_DB_USERNAME", "FIREFLY_DB_PASSWORD",
            "FIREFLY_STATIC_CRON_TOKEN",
        ):
            self.assertIn(f"      {name}:\n", workflow)
            self.assertIn(f"          {name}: ${{{{ secrets.{name} }}}}\n", workflow)
            self.assertIn(f'          : "${{{name}:?', workflow)

    def test_pihole_workflow_wires_restore_credentials(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "gcp-pihole-restore.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn("  workflow_call:\n", workflow)
        self.assertIn("  workflow_dispatch:\n", workflow)
        self.assertEqual(workflow.count("        default: false\n"), 2)
        self.assertIn("    environment: prod\n", workflow)
        self.assertIn("          SERVICE: pihole\n", workflow)
        self.assertIn("          FORCE: ${{ inputs.force || false }}\n", workflow)
        self.assertIn("        run: ./googleCloud/restore-service.sh\n", workflow)
        for name in (
            "DROPBOX_AUTH_TOKEN", "DROPBOX_REFRESH_TOKEN", "GPG_PASSPHRASE",
            "PIHOLE_WEB_PASSWORD",
        ):
            self.assertIn(f"      {name}:\n", workflow)
            self.assertEqual(
                workflow.count(f"          {name}: ${{{{ secrets.{name} }}}}\n"), 2
            )
            self.assertIn(f'          : "${{{name}:?', workflow)

    def test_deployment_runs_pihole_after_npm(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "gcp-vm-deploy.yml").read_text(
            encoding="utf-8"
        )
        job = workflow.split("\n  restore-pihole:\n", 1)[1].split(
            "\n  restore-watchtower:", 1
        )[0]
        self.assertIn("    needs: [apply, restore-npm]\n", job)
        self.assertNotIn("\n    if:", job)
        self.assertIn("    uses: ./.github/workflows/gcp-pihole-restore.yml\n", job)
        self.assertIn("      force: true\n", job)
        for name in (
            "DROPBOX_AUTH_TOKEN", "DROPBOX_REFRESH_TOKEN", "GPG_PASSPHRASE",
            "PIHOLE_WEB_PASSWORD",
        ):
            self.assertIn(f"      {name}: ${{{{ secrets.{name} }}}}\n", job)

    def test_deployment_runs_firefly_after_npm(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "gcp-vm-deploy.yml").read_text(
            encoding="utf-8"
        )
        job = workflow.split("\n  restore-firefly:\n", 1)[1].split(
            "\n  restore-watchtower:", 1
        )[0]
        self.assertIn("    needs: [apply, restore-npm]\n", job)
        self.assertIn("    uses: ./.github/workflows/gcp-firefly-restore.yml\n", job)
        self.assertIn("      force: true\n", job)
        for name in (
            "DROPBOX_AUTH_TOKEN", "DROPBOX_REFRESH_TOKEN", "GPG_PASSPHRASE",
            "FIREFLY_APP_KEY", "FIREFLY_DB_USERNAME", "FIREFLY_DB_PASSWORD",
            "FIREFLY_STATIC_CRON_TOKEN",
        ):
            self.assertIn(f"      {name}: ${{{{ secrets.{name} }}}}\n", job)

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


class RestoreWatchtowerTests(unittest.TestCase):
    def setUp(self) -> None:
        fixture = tempfile.TemporaryDirectory()
        self.addCleanup(fixture.cleanup)
        self.work = Path(fixture.name)
        self.arguments = self.work / "arguments"
        self.stream = self.work / "stream"
        self.env = {
            **os.environ,
            "PATH": f"{self.work}:{os.environ['PATH']}",
            "ARGUMENTS": str(self.arguments),
            "STREAM": str(self.stream),
            "SERVICE": "watchtower",
            "VM_NAME": "test-vm",
            "PROJECT_ID": "test-project",
            "ZONE": "test-zone",
            "WATCHTOWER_SCHEDULE": "0 0 3 * * *",
        }
        for secret in (
            "FORCE",
            "DROPBOX_AUTH_TOKEN",
            "DROPBOX_REFRESH_TOKEN",
            "GPG_PASSPHRASE",
            "WATCHTOWER_NOTIFICATION_URL",
        ):
            self.env.pop(secret, None)

    def executable(self, name: str, body: str) -> None:
        path = self.work / name
        path.write_text(f"#!/bin/bash\nset -eu\n{body}\n", encoding="utf-8")
        path.chmod(0o755)

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

    def test_transport_excludes_backup_credentials(self) -> None:
        self.env["WATCHTOWER_NOTIFICATION_URL"] = "discord://synthetic@channel"
        self.executable(
            "gcloud", 'printf "%s\\n" "$@" > "$ARGUMENTS"\ncat > "$STREAM"'
        )
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(
            self.env["WATCHTOWER_NOTIFICATION_URL"].encode(), self.stream.read_bytes()
        )
        lines = self.stream.read_bytes().split(b"\n", 1)
        self.assertEqual(base64.b64decode(lines[0]).decode(), self.env["WATCHTOWER_SCHEDULE"])
        with tarfile.open(fileobj=io.BytesIO(lines[1])) as archive:
            self.assertEqual(set(archive.getnames()), {"restore.sh", "docker-compose.yml"})
            for name in archive.getnames():
                self.assertEqual(
                    archive.extractfile(name).read(),
                    (ROOT / "securityServices" / "watchtower" / name).read_bytes(),
                )

    def test_remote_restore_runs_and_cleans_up(self) -> None:
        self.executable(
            "gcloud", 'for arg in "$@"; do command="$arg"; done\nexec bash -c "$command"'
        )
        self.executable("sudo", 'exec "$@"')
        self.executable(
            "docker",
            """
echo "${COMPOSE_PROJECT_NAME:-} $*" >> "$ARGUMENTS"
case "$*" in
  info) ;;
  *" down"|*" up -d") ;;
  *" ps --status running watchtower") echo watchtower ;;
  *" ps --status running watchtower-socket-proxy") echo watchtower-socket-proxy ;;
  *" logs --no-color --tail=80 watchtower") echo "Scheduling first run" ;;
  *) echo "Unexpected docker command: $*" >&2; exit 1 ;;
esac
""",
        )
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Watchtower recovery completed", result.stdout)
        calls = self.arguments.read_text(encoding="utf-8")
        self.assertIn("watchtower compose", calls)
        self.assertIn(" up -d", calls)
        compose_path = next(
            line.split(" -f ", 1)[1].split(" ", 1)[0]
            for line in calls.splitlines()
            if " -f " in line
        )
        self.assertFalse(Path(compose_path).parent.exists())

    def test_remote_configuration_preserves_literal_dollar_signs(self) -> None:
        self.env["WATCHTOWER_SCHEDULE"] = "0 $TOKEN 3 * * *"
        self.executable(
            "gcloud",
            'for arg in "$@"; do command="$arg"; done\n'
            'command="${command//\\/.env/\\/fixture-input}"\n'
            'exec bash -c "$command"',
        )
        self.executable("sudo", 'exec "$@"')
        self.executable(
            "docker",
            """
case "$*" in
  info) ;;
  *" down") cp "$(dirname "$3")/fixture-input" "$STREAM" ;;
  *" up -d") ;;
  *" ps --status running watchtower") echo watchtower ;;
  *" ps --status running watchtower-socket-proxy") echo watchtower-socket-proxy ;;
  *" logs --no-color --tail=80 watchtower") echo "Scheduling first run" ;;
  *) echo "Unexpected docker command: $*" >&2; exit 1 ;;
esac
""",
        )
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.stream.read_text(encoding="utf-8"),
            "WATCHTOWER_SCHEDULE='0 $TOKEN 3 * * *'\n",
        )

    def test_invalid_inputs_fail_before_connecting(self) -> None:
        for variable, value in (
            ("WATCHTOWER_SCHEDULE", ""),
            ("WATCHTOWER_SCHEDULE", "first\nsecond"),
            ("WATCHTOWER_SCHEDULE", "single'quote"),
            ("WATCHTOWER_SCHEDULE", "back\\slash"),
        ):
            with self.subTest(variable=variable, value=value):
                original = self.env[variable]
                self.env[variable] = value
                result = self.invoke()
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(result.stderr)
                self.assertFalse(self.arguments.exists())
                self.env[variable] = original

    def test_existing_notification_configuration_is_not_passed_to_container(self) -> None:
        docker = shutil.which("docker")
        if docker is None:
            self.skipTest("Docker Compose is not available")
        version = subprocess.run(
            [docker, "compose", "version"], capture_output=True, check=False
        )
        if version.returncode:
            self.skipTest("Docker Compose is not available")
        fixture = self.work / "compose-input"
        fixture.write_text(
            "WATCHTOWER_SCHEDULE=0 0 3 * * *\n"
            "WATCHTOWER_NOTIFICATION_URL=discord://synthetic@channel\n"
            "WATCHTOWER_NOTIFICATIONS=shoutrrr\n",
            encoding="utf-8",
        )
        env = os.environ.copy()
        env.pop("WATCHTOWER_SCHEDULE", None)
        result = subprocess.run(
            [
                docker,
                "compose",
                "--env-file",
                str(fixture),
                "-f",
                str(ROOT / "securityServices" / "watchtower" / "docker-compose.yml"),
                "config",
                "--format",
                "json",
            ],
            cwd=self.work,
            env=env,
            text=True,
            capture_output=True,
            check=False,
            timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        environment = json.loads(result.stdout)["services"]["watchtower"]["environment"]
        self.assertEqual(environment["WATCHTOWER_SCHEDULE"], "0 0 3 * * *")
        self.assertNotIn("WATCHTOWER_NOTIFICATION_URL", environment)
        self.assertNotIn("WATCHTOWER_NOTIFICATIONS", environment)

    def test_remote_restore_failure_is_reported_and_cleans_up(self) -> None:
        self.executable(
            "gcloud", 'for arg in "$@"; do command="$arg"; done\nexec bash -c "$command"'
        )
        self.executable("sudo", 'exec "$@"')
        self.executable(
            "docker",
            """
case "$*" in
  info) ;;
  *" down") printf '%s\\n' "$3" > "$ARGUMENTS"; exit 1 ;;
  *) exit 1 ;;
esac
""",
        )
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        compose_path = Path(self.arguments.read_text(encoding="utf-8").strip())
        self.assertFalse(compose_path.parent.exists())

    def test_deployment_schedules_watchtower_after_npm(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "gcp-vm-deploy.yml").read_text(
            encoding="utf-8"
        )
        job = workflow.split("\n  restore-watchtower:\n", 1)[1].split(
            "\n  teardown:", 1
        )[0]
        self.assertIn("    needs: [apply, restore-npm]\n", job)
        self.assertNotIn("\n    if:", job)
        self.assertIn("    uses: ./.github/workflows/gcp-watchtower-restore.yml\n", job)

    def test_workflow_invokes_shared_helper_for_watchtower(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "gcp-watchtower-restore.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn("          SERVICE: watchtower\n", workflow)
        self.assertIn("        run: ./googleCloud/restore-service.sh\n", workflow)


if __name__ == "__main__":
    unittest.main()
