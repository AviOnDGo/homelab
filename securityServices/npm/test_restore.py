import os
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("restore.sh")


def restore_env(directory: str) -> tuple[dict[str, str], Path]:
    root = Path(directory)
    bin_dir = root / "bin"
    bin_dir.mkdir()
    log = root / "calls"
    stub = bin_dir / "stub"
    stub.write_text(
        """#!/usr/bin/env bash
set -eu
echo "$(basename "$0") $*" >> "$CALLS"
case "$(basename "$0"):$1" in
  docker:info) ;;
  docker:volume)
    case "$2" in
      inspect) [[ -f "$STATE/volume" ]] ;;
      create) touch "$STATE/volume" ;;
      rm) rm "$STATE/volume" ;;
    esac ;;
  docker:ps)
    [[ ! -f "$STATE/container" ]] || echo npm ;;
  docker:inspect) echo "${BACKUP_RUNNING:-false}" ;;
  docker:stop) touch "$STATE/backup-stopped" ;;
  docker:start) rm -f "$STATE/backup-stopped" ;;
  docker:rm) rm -f "$STATE/container" ;;
  docker:run)
    if [[ "${FAIL_RUN:-}" == 1 ]]; then exit 1; fi
    cat >/dev/null ;;
  docker:compose) ;;
  docker:exec) ;;
  rclone:lsd) ;;
  rclone:lsf)
    printf '%s\\n' npm_2024-01-01_00-00-00.tar.zst.gpg unrelated.txt \\
      npm_2025-01-01_00-00-00.tar.zst.gpg ;;
  rclone:copy) printf encrypted > "$3/${2##*/}" ;;
  gpg:*)
    read -r -u 3 supplied_passphrase
    [[ "$supplied_passphrase" == "$EXPECTED_PASSPHRASE" ]]
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
    archive_path = root / "archive.tar"
    archive_file = root / "database.sqlite"
    archive_file.write_text("test data")
    with tarfile.open(archive_path, "w") as archive:
        archive.add(archive_file, arcname="database.sqlite")
    return {
        **os.environ,
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
        "CALLS": str(log),
        "STATE": directory,
        "ARCHIVE": str(archive_path),
        "PASSPHRASE": "test-secret-value",
        "EXPECTED_PASSPHRASE": "test-secret-value",
    }, log


class RestoreTests(unittest.TestCase):
    def test_automatic_restore_skips_existing_volume(self):
        with tempfile.TemporaryDirectory() as tmp:
            env, log = restore_env(tmp)
            (Path(tmp) / "volume").touch()
            result = subprocess.run(
                [str(SCRIPT), "--if-missing"],
                env=env,
                capture_output=True,
                text=True,
                stdin=subprocess.DEVNULL,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("skipping automatic restore", result.stdout)
            self.assertNotIn("rclone", log.read_text())
            self.assertNotIn("docker rm", log.read_text())

    def test_automatic_restore_selects_backup_without_exposing_passphrase(self):
        with tempfile.TemporaryDirectory() as tmp:
            env, log = restore_env(tmp)
            result = subprocess.run(
                [str(SCRIPT), "--if-missing"],
                env=env,
                capture_output=True,
                text=True,
                stdin=subprocess.DEVNULL,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = log.read_text()
            self.assertIn("npm_2025-01-01_00-00-00.tar.zst.gpg", calls)
            self.assertIn("--passphrase-fd 3", calls)
            self.assertNotIn(env["PASSPHRASE"], calls + result.stdout + result.stderr)
            self.assertIn("docker compose", calls)

    def test_force_validates_before_replacing_existing_data(self):
        for fail in (True, False):
            with self.subTest(fail=fail), tempfile.TemporaryDirectory() as tmp:
                env, log = restore_env(tmp)
                (Path(tmp) / "volume").touch()
                (Path(tmp) / "container").touch()
                if fail:
                    env["FAIL_GPG"] = "1"
                result = subprocess.run(
                    [str(SCRIPT), "--force"],
                    env=env,
                    capture_output=True,
                    text=True,
                    stdin=subprocess.DEVNULL,
                )
                calls = log.read_text()
                if fail:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn("docker rm", calls)
                    self.assertNotIn("docker run", calls)
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertLess(calls.index("gpg "), calls.index("docker rm"))
                    self.assertIn("docker run --rm -v npm_filedata:/restore", calls)

    def test_force_restarts_running_backup(self):
        for fail in (True, False):
            with self.subTest(fail=fail), tempfile.TemporaryDirectory() as tmp:
                env, log = restore_env(tmp)
                env["BACKUP_RUNNING"] = "true"
                if fail:
                    env["FAIL_RUN"] = "1"
                (Path(tmp) / "volume").touch()
                result = subprocess.run(
                    [str(SCRIPT), "--force"],
                    env=env,
                    capture_output=True,
                    text=True,
                    stdin=subprocess.DEVNULL,
                )
                self.assertEqual(result.returncode == 0, not fail, result.stderr)
                calls = log.read_text()
                self.assertLess(
                    calls.index("docker stop filedata-backup"), calls.index("docker run")
                )
                self.assertIn("docker start filedata-backup", calls)
                self.assertFalse((Path(tmp) / "backup-stopped").exists())

    def test_missing_passphrase_fails_when_input_is_unavailable(self):
        with tempfile.TemporaryDirectory() as tmp:
            env, _ = restore_env(tmp)
            env.pop("PASSPHRASE")
            result = subprocess.run(
                [str(SCRIPT), "--if-missing"],
                env=env,
                capture_output=True,
                text=True,
                stdin=subprocess.DEVNULL,
            )
            self.assertNotEqual(result.returncode, 0)

    def test_no_argument_prompts_before_replacing_data(self):
        for answer in ("n\n", "y\n"):
            with self.subTest(answer=answer), tempfile.TemporaryDirectory() as tmp:
                env, log = restore_env(tmp)
                (Path(tmp) / "volume").touch()
                result = subprocess.run(
                    [str(SCRIPT)],
                    env=env,
                    input=answer,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Its contents will be permanently deleted", result.stdout)
                self.assertEqual(
                    "docker run --rm -v npm_filedata:/restore" in log.read_text(),
                    answer == "y\n",
                )

    def test_unrecognized_argument_uses_interactive_prompt(self):
        with tempfile.TemporaryDirectory() as tmp:
            env, log = restore_env(tmp)
            (Path(tmp) / "volume").touch()
            result = subprocess.run(
                [str(SCRIPT), "unexpected"], env=env, input="n\n",
                capture_output=True, text=True
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Its contents will be permanently deleted", result.stdout)
            self.assertNotIn("docker run --rm -v npm_filedata:/restore", log.read_text())


if __name__ == "__main__":
    unittest.main()
