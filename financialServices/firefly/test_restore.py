import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("restore.sh")


class FireflyRestoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.log = self.root / "calls"
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        stub = bin_dir / "stub"
        stub.write_text(
            """#!/usr/bin/env bash
set -eu
echo "$(basename "$0") $*" >> "$CALLS"
case "$(basename "$0"):$1" in
  docker:info) ;;
  docker:volume)
    if [[ "$2" == ls ]]; then
      [[ "${FAIL_VOLUME_LIST:-}" != 1 ]] || exit 1
      if [[ -f "$STATE/volume" ]]; then echo firefly_postgresdata; fi
    else touch "$STATE/volume"; fi ;;
  docker:ps)
    if [[ "$*" == *"db-backup"* && "${BACKUP_RUNNING:-}" == 1 ]]; then
      echo 'db-backup running'
    elif [[ "$*" == *"name=^/firefly"* && -f "$STATE/container" ]]; then
      echo firefly-db
    elif [[ "$*" == *"volume="* && "${VOLUME_BUSY:-}" == 1 ]]; then
      echo other-container
    fi ;;
  docker:stop)
    touch "$STATE/backup-stopped"
    if [[ "${FAIL_STOP:-}" == 1 ]]; then
      echo "Failed to stop backup container" >&2
      exit 1
    fi ;;
  docker:start)
    if [[ "$2" == db-backup ]]; then
      [[ "${FAIL_RESTART:-}" != 1 ]] || exit 1
      rm -f "$STATE/backup-stopped"
    fi ;;
  docker:compose)
    if [[ "$*" == *" down" ]]; then rm -f "$STATE/container"; fi
    if [[ "$*" == *" up -d --wait"* && "${FAIL_HEALTH:-}" == 1 ]]; then exit 1; fi ;;
  docker:run) [[ "${FAIL_CLEAR:-}" != 1 ]] ;;
  docker:exec)
    if [[ "$*" == *pg_isready* && "${SIMULATE_INIT:-}" == 1 ]]; then
      if [[ "$*" != *"pg_isready -h 127.0.0.1 "* ]]; then
        exit 0
      fi
      if [[ "${NEVER_READY:-}" == 1 ]]; then exit 1; fi
      if [[ ! -f "$STATE/tcp-ready" ]]; then
        touch "$STATE/tcp-ready"
        exit 1
      fi
    elif [[ "$*" == *ON_ERROR_STOP* ]]; then
      if [[ "$*" == *"SELECT 1 FROM"* ]]; then
        [[ "${FAIL_VERIFY:-}" != 1 ]]
      else
        cat >/dev/null
        [[ "${FAIL_IMPORT:-}" != 1 ]]
      fi
    fi ;;
  rclone:lsd) ;;
  rclone:lsf)
    [[ "${FAIL_LIST:-}" != 1 ]] || exit 1
    if [[ "${ONLY_LEGACY:-}" == 1 ]]; then
      echo backup_firefly_20260101_000000.sql.zst.gpg
    else
      printf '%s\\n' firefly_2024-01-01_00-00-00.sql.zst.gpg \\
        firefly_2025-01-01_00-00-00.sql.zst.gpg \\
        backup_firefly_20260101_000000.sql.zst.gpg unrelated.sql.zst.gpg
    fi ;;
  rclone:copy)
    if [[ -n "${REAL_ENCRYPTED:-}" ]]; then cp "$REAL_ENCRYPTED" "$3/${2##*/}"
    else printf encrypted > "$3/${2##*/}"; fi ;;
  gpg:*)
    read -r -u 3 supplied
    [[ "$supplied" == "$PASSPHRASE_EXPECTED" ]]
    [[ "${FAIL_GPG:-}" != 1 ]] || exit 1
    if [[ "${EMPTY_DUMP:-}" != 1 ]]; then
      printf '%s\\n' '-- PostgreSQL database dump' 'SELECT 1;' \\
        '-- PostgreSQL database dump complete'
    fi ;;
  zstd:*) cat ;;
  sleep:*) ;;
  *) echo "Unexpected command: $*" >&2; exit 1 ;;
esac
""",
            encoding="utf-8",
        )
        stub.chmod(0o755)
        for name in ("docker", "rclone", "gpg", "zstd", "sleep"):
            (bin_dir / name).symlink_to(stub)
        self.env = {
            **os.environ,
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
            "CALLS": str(self.log),
            "STATE": str(self.root),
            "TMPDIR": str(self.root),
            "PASSPHRASE": "test-passphrase",
            "PASSPHRASE_EXPECTED": "test-passphrase",
        }

    def run_restore(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(SCRIPT), *args],
            env=self.env,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=10,
        )

    def calls(self) -> str:
        return self.log.read_text(encoding="utf-8")

    def test_skip_existing_volume_without_accessing_backup(self) -> None:
        (self.root / "volume").touch()
        result = self.run_restore("--if-missing")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("rclone", self.calls())
        self.assertNotIn("docker compose", self.calls())

    def test_if_missing_refuses_existing_containers(self) -> None:
        (self.root / "container").touch()
        result = self.run_restore("--if-missing")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("docker compose", self.calls())

    def test_volume_listing_failure_does_not_restore(self) -> None:
        self.env["FAIL_VOLUME_LIST"] = "1"
        result = self.run_restore("--force")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Could not list Docker volumes", result.stderr)
        self.assertNotIn("docker compose", self.calls())

    def test_restore_validates_and_restarts_backup_on_success(self) -> None:
        (self.root / "volume").touch()
        self.env["BACKUP_RUNNING"] = "1"
        result = self.run_restore("--force")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertIn("firefly_2025-01-01_00-00-00.sql.zst.gpg", calls)
        self.assertLess(calls.index("gpg "), calls.index("docker stop db-backup"))
        self.assertLess(calls.index("docker stop db-backup"), calls.index("docker run"))
        self.assertIn("ON_ERROR_STOP=1", calls)
        self.assertIn("docker start db-backup", calls)
        self.assertNotIn("test-passphrase", calls + result.stdout + result.stderr)
        self.assertFalse(list(self.root.glob("firefly-restore.*")))

    def test_waits_for_tcp_server_after_socket_only_initialization(self) -> None:
        self.env["SIMULATE_INIT"] = "1"
        result = self.run_restore("--force")
        self.assertEqual(result.returncode, 0, result.stderr)
        probes = [line for line in self.calls().splitlines() if "pg_isready" in line]
        self.assertEqual(len(probes), 2)
        self.assertTrue(all("pg_isready -h 127.0.0.1 " in line for line in probes))
        self.assertIn("ON_ERROR_STOP=1", self.calls())

    def test_tcp_readiness_timeout_does_not_import(self) -> None:
        self.env.update(SIMULATE_INIT="1", NEVER_READY="1", BACKUP_RUNNING="1")
        result = self.run_restore("--force")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("PostgreSQL did not become ready", result.stderr)
        self.assertIn("remains stopped", result.stderr)
        self.assertNotIn("ON_ERROR_STOP=1", self.calls())
        self.assertNotIn("docker start db-backup", self.calls())

    def test_failed_backup_stop_attempts_restart_without_stopping_firefly(self) -> None:
        self.env.update(BACKUP_RUNNING="1", FAIL_STOP="1")
        for fail_restart in ("0", "1"):
            with self.subTest(fail_restart=fail_restart):
                self.env["FAIL_RESTART"] = fail_restart
                result = self.run_restore("--force")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Failed to stop backup container", result.stderr)
                self.assertIn("docker start db-backup", self.calls())
                self.assertNotIn("docker compose", self.calls())
                self.assertEqual(
                    (self.root / "backup-stopped").exists(), fail_restart == "1"
                )
                if fail_restart == "1":
                    self.assertIn("Could not restart db-backup", result.stderr)
                self.log.unlink()

    def test_invalid_backup_never_stops_services(self) -> None:
        for failure in ("FAIL_LIST", "FAIL_GPG", "EMPTY_DUMP"):
            with self.subTest(failure=failure):
                self.env[failure] = "1"
                result = self.run_restore("--force")
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("docker stop", self.calls())
                self.assertNotIn(" down", self.calls())
                self.log.unlink()
                del self.env[failure]

    def test_legacy_only_backup_is_not_restored(self) -> None:
        self.env["ONLY_LEGACY"] = "1"
        result = self.run_restore("--force")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Expected firefly_YYYY-MM-DD_HH-MM-SS.sql.zst.gpg", result.stderr)
        self.assertNotIn("rclone copy", self.calls())
        self.assertNotIn("docker stop", self.calls())

    def test_failure_after_wipe_leaves_backup_stopped(self) -> None:
        for failure in ("FAIL_CLEAR", "FAIL_IMPORT", "FAIL_VERIFY", "FAIL_HEALTH"):
            with self.subTest(failure=failure):
                (self.root / "volume").touch()
                self.env.update(BACKUP_RUNNING="1", **{failure: "1"})
                result = self.run_restore("--force")
                self.assertNotEqual(result.returncode, 0, result.stderr)
                self.assertIn("remains stopped", result.stderr)
                self.assertNotIn("docker start db-backup", self.calls())
                self.assertFalse(list(self.root.glob("firefly-restore.*")))
                self.log.unlink()
                del self.env[failure]

    def test_running_volume_user_blocks_wipe_and_restarts_backup(self) -> None:
        (self.root / "volume").touch()
        self.env.update(BACKUP_RUNNING="1", VOLUME_BUSY="1")
        result = self.run_restore("--force")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("docker run", self.calls())
        self.assertIn("docker start db-backup", self.calls())

    def test_backup_restart_failure_is_reported(self) -> None:
        self.env.update(BACKUP_RUNNING="1", FAIL_RESTART="1")
        result = self.run_restore("--force")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Could not restart db-backup", result.stderr)

    @unittest.skipUnless(shutil.which("gpg") and shutil.which("zstd"), "requires gpg and zstd")
    def test_real_encrypted_dump_and_wrong_passphrase(self) -> None:
        gpg = shutil.which("gpg")
        zstd = shutil.which("zstd")
        gnupg_home = self.root / "gnupg"
        gnupg_home.mkdir(mode=0o700)
        encrypted = self.root / "fixture.gpg"
        self.env.update(GNUPGHOME=str(gnupg_home), REAL_ENCRYPTED=str(encrypted))
        dump = (
            b"-- PostgreSQL database dump\nSELECT 1;\n"
            b"-- PostgreSQL database dump complete\n"
        )
        compressed = subprocess.run(
            [zstd, "-q", "-c"], input=dump, check=True, capture_output=True
        ).stdout
        compressed_file = self.root / "fixture.zst"
        compressed_file.write_bytes(compressed)
        subprocess.run(
            [
                gpg, "--batch", "--yes", "--pinentry-mode", "loopback",
                "--passphrase-fd", "0", "--symmetric", "-o", str(encrypted),
                str(compressed_file),
            ],
            env=self.env,
            input=b"test-passphrase\n",
            check=True,
            capture_output=True,
        )
        for name, executable in (("gpg", gpg), ("zstd", zstd)):
            path = self.root / "bin" / name
            path.unlink()
            path.symlink_to(executable)
        self.env["PASSPHRASE"] = "wrong-passphrase"
        failed = self.run_restore("--force")
        self.assertNotEqual(failed.returncode, 0)
        self.assertNotIn(" down", self.calls())
        self.log.unlink()
        self.env["PASSPHRASE"] = "test-passphrase"
        result = self.run_restore("--force")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("ON_ERROR_STOP=1", self.calls())

    def test_invalid_mode_is_rejected(self) -> None:
        result = self.run_restore("--unknown")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Usage:", result.stderr)
        self.assertFalse(self.log.exists())


if __name__ == "__main__":
    unittest.main()
