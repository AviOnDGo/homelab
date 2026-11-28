import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SERVICE = ROOT / "securityServices" / "firefoxsync"
BACKUP = ROOT / "backupServices" / "postgres"


class FirefoxSyncDatabaseConfigurationTests(unittest.TestCase):
    def test_application_healthcheck_and_restore_use_same_database(self) -> None:
        compose = (SERVICE / "docker-compose.yml").read_text(encoding="utf-8")
        restore = (SERVICE / "restore.sh").read_text(encoding="utf-8")

        database = re.search(r"^\s+POSTGRES_DB: (\S+)$", compose, re.MULTILINE)
        self.assertIsNotNone(database)
        self.assertEqual(database.group(1), "firefoxsync")
        for variable in (
            "SYNC_SYNCSTORAGE__DATABASE_URL",
            "SYNC_TOKENSERVER__DATABASE_URL",
        ):
            self.assertRegex(
                compose,
                rf"{variable}: .*@firefoxsync-db:5432/{database.group(1)}\"",
            )
        self.assertIn(f"pg_isready -U sync -d {database.group(1)}", compose)
        self.assertIn(f'DB_NAME="{database.group(1)}"', restore)

    def test_backup_examples_target_application_database(self) -> None:
        for filename in (".env.acc.example", ".env.prd.example"):
            with self.subTest(filename=filename):
                example = (BACKUP / filename).read_text(encoding="utf-8")
                self.assertIn("FIREFOXSYNC_DB_HOST=firefoxsync-db\n", example)
                self.assertIn("FIREFOXSYNC_DB_NAME=firefoxsync\n", example)


if __name__ == "__main__":
    unittest.main()
