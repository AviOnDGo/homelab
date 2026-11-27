import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class BackupSourceSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.calls = self.root / "calls"

        # Isolate test paths and external commands from the host's data and secrets.
        original = (ROOT / "filedata-backup-script.sh").read_text()
        self.assertIn('SOURCE_DIR="/backup-sources/${VOLUME_NAME}"', original)
        original = original.replace(
            'SOURCE_DIR="/backup-sources/${VOLUME_NAME}"',
            'SOURCE_DIR="${TEST_SOURCE_DIR}"',
        ).replace(
            "/run/secrets/gpg-passphrase", str(self.root / "no-gpg-secret")
        ).replace(
            'BACKUP_DIR="/backups/${VOLUME_NAME}"',
            'BACKUP_DIR="${TEST_BACKUP_DIR}"',
        )
        self.script = self.root / "backup.sh"
        self.script.write_text(original)

        for name in ("rclone", "tar", "zstd", "gpg", "curl"):
            command = self.bin / name
            command.write_text(
                "#!/bin/sh\n"
                f"echo '{name}' >> \"$TEST_CALLS\"\n"
                'if [ "$(basename "$0")" = curl ]; then '
                'printf "%s\\n" "$@" > "$TEST_NOTIFICATION"; fi\n'
                'if [ "$1" = listremotes ]; then echo test:; fi\n'
            )
            command.chmod(0o755)
        self.env = {
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "HOME": str(self.root),
            "TEST_CALLS": str(self.calls),
            "TEST_NOTIFICATION": str(self.root / "notification"),
            "SAMPLE_DROPBOX_PATH": "/test",
            "SAMPLE_SYNC_CRYPT_REMOTE": "test:/test",
            "SAMPLE_RETENTION_DAYS": "0",
            "DISCORD_WEBHOOK_URL": "https://example.invalid/test",
        }

    def run_backup(self, source, mode):
        return subprocess.run(
            ["bash", str(self.script), "sample"],
            env={
                **self.env,
                "TEST_SOURCE_DIR": str(source),
                "TEST_BACKUP_DIR": str(self.root / "backups"),
                "SAMPLE_BACKUP_MODE": mode,
            },
            text=True,
            capture_output=True,
            check=False,
        )

    def test_existing_unmounted_directory_stops_both_modes(self):
        source = self.root / "source"
        source.mkdir()
        for mode in ("archive", "sync-crypt"):
            with self.subTest(mode=mode):
                result = self.run_backup(source, mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Source directory is not a mount point", result.stdout)
                self.assertEqual(self.calls.read_text().splitlines()[-1], "curl")
                notification = (self.root / "notification").read_text()
                self.assertIn("Source validation", notification)
                self.assertIn("Source directory is not a mount point", notification)
        self.assertEqual(self.calls.read_text().splitlines(), ["curl", "curl"])

    def test_missing_source_still_reports_failure(self):
        result = self.run_backup(self.root / "missing", "sync-crypt")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Source directory not found", result.stdout)
        self.assertEqual(self.calls.read_text().splitlines(), ["curl"])

    def test_mounted_source_reaches_sync(self):
        self.assertTrue(os.path.ismount("/proc"))
        result = self.run_backup("/proc", "sync-crypt")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Pure sync-crypt mirror completed successfully", result.stdout)
        self.assertEqual(self.calls.read_text().splitlines(), ["rclone", "rclone"])

    def test_mounted_source_reaches_archive_validation(self):
        self.env.pop("SAMPLE_DROPBOX_PATH")
        result = self.run_backup("/proc", "archive")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "Required environment variable missing: SAMPLE_DROPBOX_PATH", result.stdout
        )
        self.assertNotIn("not a mount point", result.stdout)

    def test_archive_passphrase_is_not_interpreted_as_echo_options(self):
        zstd = self.bin / "zstd"
        zstd.write_text('#!/bin/sh\nwhile [ "$1" != -o ]; do shift; done\n: > "$2"\n')
        gpg = self.bin / "gpg"
        gpg.write_text('#!/bin/sh\ncat > "$HOME/passphrase-input"\nexit 1\n')
        self.env["GPG_PASSPHRASE"] = "-n"
        result = self.run_backup("/proc", "archive")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.root / "passphrase-input").read_text(), "-n\n")


if __name__ == "__main__":
    unittest.main()
