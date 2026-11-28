import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class DatabaseRetentionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.backups = self.root / "backups" / "firefly"
        self.backups.mkdir(parents=True)
        self.log = self.root / "rclone.log"
        self.system_env = self.root / "system-environment"
        self.script = self.root / "backup-script.sh"
        script = (ROOT / "db-backup-script.sh").read_text()
        script = script.replace("/etc/environment", str(self.system_env))
        script = script.replace("/run/secrets/gpg-passphrase", str(self.root / "passphrase"))
        script = script.replace("/backups/", str(self.root / "backups") + "/")
        script = script.replace("/root/.config/rclone", str(self.root / "rclone-config"))
        self.script.write_text(script)
        self.stub("pg_dump", 'printf "database dump\\n"\n')
        self.stub(
            "zstd",
            'while [ "$#" -gt 0 ]; do\n'
            '  if [ "$1" = "-o" ]; then shift; cat > "$1"; exit; fi\n'
            "  shift\n"
            "done\n"
            "exit 1\n",
        )
        self.stub(
            "gpg",
            'while [ "$#" -gt 0 ]; do\n'
            '  if [ "$1" = "-o" ]; then shift; output="$1"; '
            'else input="$1"; fi\n'
            "  shift\n"
            "done\n"
            'cp "$input" "$output"\n',
        )
        self.stub(
            "rclone",
            'printf "%s\\n" "$*" >> "$RCLONE_LOG"\n'
            'if [ "$1" = "ls" ]; then\n'
            "  printf '1 firefly_2000-01-01_00-00-00.sql.zst.gpg\\n"
            "1 firefly_2999-01-01_00-00-00.sql.zst.gpg\\n'\n"
            "fi\n",
        )
        self.env = {
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "HOME": str(self.root),
            "RCLONE_LOG": str(self.log),
            "FIREFLY_DB_HOST": "firefly-db",
            "FIREFLY_DB_USER": "firefly",
            "FIREFLY_DB_PASSWORD": "test-password",
            "FIREFLY_DB_NAME": "firefly",
            "FIREFLY_BACKUP_NAME": "firefly",
            "FIREFLY_DROPBOX_BACKUP_PATH": "/test/firefly",
            "FIREFLY_BACKUP_RETENTION_DAYS": "90",
            "GPG_PASSPHRASE": "test-passphrase",
            "DISCORD_WEBHOOK_URL": "",
            "DROPBOX_AUTH_TOKEN": "",
            "DROPBOX_REFRESH_TOKEN": "",
        }

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/sh\nset -eu\n" + body)
        path.chmod(0o755)

    def run_backup(self, name="firefly", **env):
        return subprocess.run(
            ["bash", str(self.script), name],
            env={**self.env, **env},
            text=True,
            capture_output=True,
            check=False,
            timeout=10,
        )

    def test_registry_retention_controls_local_and_remote_cleanup(self):
        old = self.backups / "firefly_2000-01-01_00-00-00.sql.zst.gpg"
        recent = self.backups / "firefly_2999-01-01_00-00-00.sql.zst.gpg"
        old.write_text("old")
        recent.write_text("recent")
        past = time.time() - 3 * 86400
        os.utime(old, (past, past))
        self.system_env.write_text(
            "FIREFLY_BACKUP_RETENTION_DAYS=90\n"
            "DB_BACKUP_FIREFLY_RETENTION_DAYS=90\n"
        )
        result = self.run_backup(DB_BACKUP_FIREFLY_RETENTION_DAYS="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(old.exists())
        self.assertTrue(recent.exists())
        log = self.log.read_text()
        self.assertIn("delete dropbox:/test/firefly/firefly_2000-01-01", log)
        self.assertNotIn("delete dropbox:/test/firefly/firefly_2999-01-01", log)

    def test_each_database_uses_its_generated_retention(self):
        for name in ("firefly", "romm", "paperless", "immich", "invidious", "firefoxsync"):
            with self.subTest(name=name):
                key = name.upper()
                result = self.run_backup(
                    name,
                    **{
                        f"DB_BACKUP_{key}_RETENTION_DAYS": "1",
                        f"{key}_BACKUP_RETENTION_DAYS": "90",
                        f"{key}_BACKUP_NAME": name,
                        f"{key}_DROPBOX_BACKUP_PATH": f"/test/{name}",
                    },
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Cleaning local backups older than 1 days", result.stdout)

    def test_missing_registry_retention_fails_before_backup(self):
        result = self.run_backup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No registry retention policy for firefly", result.stderr)
        self.assertFalse(self.log.exists())


if __name__ == "__main__":
    unittest.main()
