import os
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("restore.sh")


def restore_env(tmp_path: str) -> tuple[dict[str, str], Path]:
    bin_dir = Path(tmp_path) / "bin"
    bin_dir.mkdir()
    log = Path(tmp_path) / "calls"
    stub = bin_dir / "stub"
    stub.write_text(
        """#!/usr/bin/env bash
set -eu
echo "$(basename "$0") $*" >> "$CALLS"
case "$(basename "$0"):$1" in
  docker:info) ;;
  docker:inspect)
    if [[ -f "$STATE/backup-stopped" || "${BACKUP_NOT_RUNNING:-}" == 1 ]]; then
      echo false
    else
      echo true
    fi ;;
  docker:ps)
    if [[ "${FRESHRSS_NOT_RUNNING:-}" != 1 && ! -f "$STATE/stopped" ]]; then
      echo freshrss
    fi ;;
  docker:compose)
    if [[ "$*" == *" down" ]]; then touch "$STATE/stopped"; fi ;;
  docker:volume)
    if [[ "$2" == inspect && "${NO_VOLUME:-}" == 1 ]]; then exit 1; fi
    [[ "$2" != create ]] || echo freshrss_filedata ;;
  docker:run)
    if [[ "$*" == *" -i "* ]]; then
      if [[ "${FAIL_EXTRACT:-}" == 1 ]]; then exit 1; fi
      cat >/dev/null
    fi ;;
  docker:exec) [[ "${FAIL_HEALTH:-}" != 1 ]] ;;
  docker:stop) touch "$STATE/backup-stopped" ;;
  docker:start)
    if [[ "${FAIL_START:-}" == 1 ]]; then exit 1; fi
    rm -f "$STATE/backup-stopped" ;;
  rclone:lsd) ;;
  rclone:lsf)
    if [[ "${FAIL_LIST:-}" == 1 ]]; then exit 1; fi
    printf '%s\\n' freshrss_2024-01-01_00-00-00.tar.zst.gpg unrelated.txt \\
      freshrss_2025-01-01_00-00-00.tar.zst.gpg ;;
  rclone:copy)
    if [[ "${FAIL_COPY:-}" == 1 ]]; then exit 1; fi
    printf encrypted > "$3/${2##*/}" ;;
  gpg:*)
    if [[ "${FAIL_GPG:-}" == 1 ]]; then exit 1; fi
    cat "$ARCHIVE" ;;
  zstd:*) cat ;;
  sleep:*) ;;
  *) echo "Unexpected command: $*" >&2; exit 1 ;;
esac
"""
    )
    stub.chmod(0o755)
    for name in ("docker", "rclone", "gpg", "zstd", "sleep"):
        (bin_dir / name).symlink_to(stub)
    archive_path = Path(tmp_path) / "archive.tar"
    archive_file = Path(tmp_path) / "archive-content"
    archive_file.write_text("valid archive")
    with tarfile.open(archive_path, "w") as archive:
        archive.add(archive_file, arcname="archive-content")
    return {
        **os.environ,
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
        "CALLS": str(log),
        "STATE": str(tmp_path),
        "TMPDIR": str(tmp_path),
        "ARCHIVE": str(archive_path),
        "PASSPHRASE": "test-passphrase",
    }, log


class RestoreTests(unittest.TestCase):
    def test_restore_selects_archive_and_coordinates_backup(self):
        with tempfile.TemporaryDirectory() as tmp:
            env, log = restore_env(tmp)
            result = subprocess.run(
                [str(SCRIPT)], env=env, input="y\ny\n", capture_output=True, text=True
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = log.read_text()
            self.assertIn(
                "rclone copy dropbox:/Apps/freshrss/"
                "freshrss_2025-01-01_00-00-00.tar.zst.gpg",
                calls,
            )
            self.assertLess(
                calls.index("rclone copy"), calls.index("docker stop filedata-backup")
            )
            self.assertLess(
                calls.index("docker stop filedata-backup"), calls.index("docker run")
            )
            self.assertLess(
                calls.index("docker exec freshrss"), calls.index("docker start filedata-backup")
            )
            self.assertNotIn("test-passphrase", calls)

    def test_download_failures_do_not_stop_services(self):
        for failure in ("FAIL_LIST", "FAIL_COPY"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as tmp:
                env, log = restore_env(tmp)
                env[failure] = "1"
                result = subprocess.run(
                    [str(SCRIPT)], env=env, input="y\ny\n", capture_output=True, text=True
                )
                self.assertNotEqual(result.returncode, 0)
                calls = log.read_text()
                self.assertNotIn("docker stop", calls)
                self.assertNotIn("docker compose", calls)
                self.assertNotIn("docker run", calls)

    def test_invalid_archive_does_not_stop_or_clear_services(self):
        with tempfile.TemporaryDirectory() as tmp:
            env, log = restore_env(tmp)
            env["FAIL_GPG"] = "1"
            result = subprocess.run(
                [str(SCRIPT)], env=env, input="y\ny\n", capture_output=True, text=True
            )
            self.assertNotEqual(result.returncode, 0)
            calls = log.read_text()
            self.assertNotIn("docker stop", calls)
            self.assertNotIn("docker compose", calls)
            self.assertNotIn("docker run", calls)

    def test_failed_extraction_restores_backup_container(self):
        with tempfile.TemporaryDirectory() as tmp:
            env, log = restore_env(tmp)
            env["FAIL_EXTRACT"] = "1"
            result = subprocess.run(
                [str(SCRIPT)], env=env, input="y\ny\n", capture_output=True, text=True
            )
            self.assertNotEqual(result.returncode, 0)
            calls = log.read_text()
            self.assertIn("docker stop filedata-backup", calls)
            self.assertIn("docker start filedata-backup", calls)
            self.assertFalse((Path(tmp) / "backup-stopped").exists())

    def test_failed_health_check_restores_backup_container(self):
        with tempfile.TemporaryDirectory() as tmp:
            env, log = restore_env(tmp)
            env["FAIL_HEALTH"] = "1"
            result = subprocess.run(
                [str(SCRIPT)], env=env, input="y\ny\n", capture_output=True, text=True
            )
            self.assertNotEqual(result.returncode, 0)
            calls = log.read_text()
            self.assertIn("docker start filedata-backup", calls)
            self.assertFalse((Path(tmp) / "backup-stopped").exists())

    def test_retry_restores_backup_state_saved_by_failed_attempt(self):
        with tempfile.TemporaryDirectory() as tmp:
            env, log = restore_env(tmp)
            env.update(FAIL_EXTRACT="1", FAIL_START="1")
            first = subprocess.run(
                [str(SCRIPT)], env=env, input="y\ny\n", capture_output=True, text=True
            )
            self.assertNotEqual(first.returncode, 0)
            self.assertTrue((Path(tmp) / "backup-stopped").exists())
            self.assertEqual(
                (Path(tmp) / "freshrss-restore-backup-state").read_text().strip(),
                "running",
            )

            env.pop("FAIL_EXTRACT")
            env.pop("FAIL_START")
            second = subprocess.run(
                [str(SCRIPT)], env=env, input="y\ny\n", capture_output=True, text=True
            )
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertIn("filedata-backup is running.", second.stdout)
            self.assertFalse((Path(tmp) / "backup-stopped").exists())
            self.assertFalse((Path(tmp) / "freshrss-restore-backup-state").exists())

    def test_initially_stopped_backup_remains_stopped(self):
        with tempfile.TemporaryDirectory() as tmp:
            env, log = restore_env(tmp)
            env["BACKUP_NOT_RUNNING"] = "1"
            result = subprocess.run(
                [str(SCRIPT)], env=env, input="y\ny\n", capture_output=True, text=True
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("docker stop filedata-backup", log.read_text())
            self.assertNotIn("docker start filedata-backup", log.read_text())
            self.assertIn("filedata-backup is not running.", result.stdout)

    def test_declined_confirmation_does_not_stop_services(self):
        with tempfile.TemporaryDirectory() as tmp:
            env, log = restore_env(tmp)
            result = subprocess.run(
                [str(SCRIPT)], env=env, input="n\n", capture_output=True, text=True
            )
            self.assertEqual(result.returncode, 0)
            calls = log.read_text()
            self.assertNotIn("docker stop", calls)
            self.assertNotIn("docker compose", calls)
            self.assertNotIn("docker run", calls)

    def test_missing_confirmation_fails_without_stopping_services(self):
        with tempfile.TemporaryDirectory() as tmp:
            env, log = restore_env(tmp)
            result = subprocess.run(
                [str(SCRIPT)], env=env, input="y\n", capture_output=True, text=True
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Confirmation input unavailable", result.stderr)
            self.assertNotIn("docker stop", log.read_text())

    def test_confirmations_allow_missing_service_or_volume(self):
        for absent in ("FRESHRSS_NOT_RUNNING", "NO_VOLUME"):
            with self.subTest(absent=absent), tempfile.TemporaryDirectory() as tmp:
                env, log = restore_env(tmp)
                env[absent] = "1"
                result = subprocess.run(
                    [str(SCRIPT)], env=env, input="y\ny\n",
                    capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("docker start filedata-backup", log.read_text())


if __name__ == "__main__":
    unittest.main()
