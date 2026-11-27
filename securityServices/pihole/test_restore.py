import os
import shutil
import sqlite3
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("restore.sh")
DATABASES = ("gravity.db", "pihole-FTL.db")


class RestoreDatabaseTests(unittest.TestCase):
    def setUp(self) -> None:
        fixture = tempfile.TemporaryDirectory()
        self.addCleanup(fixture.cleanup)
        self.work = Path(fixture.name)
        self.calls = self.work / "calls"
        self.archive = self.work / "backup.tar"
        bin_dir = self.work / "bin"
        bin_dir.mkdir()
        stub = bin_dir / "stub"
        stub.write_text(
            """#!/usr/bin/env bash
set -eu
echo "$(basename "$0") $*" >> "$CALLS"
case "$(basename "$0"):$1" in
  docker:info|docker:stop) ;;
  docker:start) [[ "${FAILURE:-}" != restart ]] ;;
  docker:rm) [[ "${FAILURE:-}" != remove ]] ;;
  docker:compose)
    if [[ "$*" == *"config --images pihole"* ]]; then echo pihole/pihole:latest; fi
    if [[ "$*" == *" up -d" ]]; then [[ "${FAILURE:-}" != startup ]]; fi ;;
  docker:volume)
    if [[ "$2" == create ]]; then [[ "${FAILURE:-}" != create ]]; fi ;;
  docker:ps) echo pihole ;;
  docker:inspect) echo "${BACKUP_RUNNING:-true}" ;;
  docker:run)
    if [[ "$*" == *" --entrypoint pihole-FTL "* ]]; then
      if [[ -n "${REAL_DOCKER:-}" ]]; then exec "$REAL_DOCKER" "$@"; fi
      if [[ "${VALIDATION_FAILURE:-}" == 1 ]]; then exit 1; fi
      if [[ -n "${VALIDATION_OUTPUT:-}" ]]; then echo "$VALIDATION_OUTPUT"; exit 0; fi
      for arg in "$@"; do
        case "$arg" in
          *:/check) staged="${arg%:/check}" ;;
          /check/*.db) database="${arg##*/}" ;;
        esac
      done
      python3 -c 'import sqlite3, sys; db = sqlite3.connect(sys.argv[1]); print("\\n".join(row[0] for row in db.execute("PRAGMA integrity_check"))) ' "$staged/$database"
    elif [[ "$*" == *" -i "* ]]; then
      cat >/dev/null
      [[ "${FAILURE:-}" != extract ]]
    else
      [[ "${FAILURE:-}" != wipe ]]
    fi ;;
  docker:exec)
    if [[ "$3" == pihole-FTL ]]; then
      if [[ "${UNREADABLE_RESTORED:-}" == "${4##*/}" ]]; then
        exit 1
      elif [[ "${INVALID_RESTORED:-}" == "${4##*/}" ]]; then
        echo "database disk image is malformed"
      else
        echo ok
      fi
    fi ;;
  rclone:lsd) ;;
  rclone:lsf) echo pihole_2025-01-01_00-00-00.tar.zst.gpg ;;
  rclone:copy) printf encrypted > "$3/${2##*/}" ;;
  gpg:*) cat "$ARCHIVE" ;;
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
            "CALLS": str(self.calls),
            "ARCHIVE": str(self.archive),
            "TMPDIR": str(self.work),
            "PASSPHRASE": "fixture",
        }

    def make_archive(self, invalid: str = "", mode: str = "") -> None:
        with tarfile.open(self.archive, "w") as archive:
            for name in DATABASES:
                if name == invalid and mode == "missing":
                    continue
                if name == invalid and mode == "symlink":
                    member = tarfile.TarInfo(f"./{name}")
                    member.type = tarfile.SYMTYPE
                    member.linkname = "other.db"
                    archive.addfile(member)
                    continue
                database = self.work / name
                database.unlink(missing_ok=True)
                with sqlite3.connect(database) as db:
                    db.execute("CREATE TABLE example (value TEXT)")
                    db.execute("INSERT INTO example VALUES ('data')")
                if name == invalid and mode == "empty":
                    database.write_bytes(b"")
                elif name == invalid and mode == "corrupt":
                    data = bytearray(database.read_bytes())
                    data[100] = 0
                    database.write_bytes(data)
                archive.add(database, arcname=f"./{name}")

    def invoke(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(SCRIPT), "--force"],
            env=self.env,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )

    def test_invalid_backup_never_changes_existing_data(self) -> None:
        for database in DATABASES:
            for mode in ("missing", "empty", "corrupt", "symlink"):
                with self.subTest(database=database, mode=mode):
                    self.calls.unlink(missing_ok=True)
                    self.make_archive(database, mode)
                    result = self.invoke()
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(f"Invalid backup database {database}", result.stderr)
                    calls = self.calls.read_text(encoding="utf-8")
                    for command in ("docker stop", "docker rm", "pihole_filedata:/restore"):
                        self.assertNotIn(command, calls)
                    self.assertFalse(list(self.work.glob("pihole-restore.*")))

    def test_invalid_sqlite_sidecars_are_rejected(self) -> None:
        for suffix in ("-wal", "-shm"):
            with self.subTest(suffix=suffix):
                self.calls.unlink(missing_ok=True)
                self.make_archive()
                with tarfile.open(self.archive, "a") as archive:
                    member = tarfile.TarInfo(f"./gravity.db{suffix}")
                    member.type = tarfile.SYMTYPE
                    member.linkname = "other.db"
                    archive.addfile(member)
                result = self.invoke()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"Invalid SQLite sidecar: gravity.db{suffix}", result.stderr)
                self.assertNotIn(
                    "pihole_filedata:/restore", self.calls.read_text(encoding="utf-8")
                )

    def test_failed_or_non_ok_validation_never_changes_existing_data(self) -> None:
        self.make_archive()
        for variable, value in (("VALIDATION_FAILURE", "1"), ("VALIDATION_OUTPUT", "corrupt")):
            with self.subTest(variable=variable):
                self.calls.unlink(missing_ok=True)
                self.env[variable] = value
                result = self.invoke()
                self.env.pop(variable)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Invalid backup database gravity.db", result.stderr)
                self.assertNotIn(
                    "pihole_filedata:/restore", self.calls.read_text(encoding="utf-8")
                )

    def test_post_restore_integrity_is_checked_for_both_databases(self) -> None:
        self.make_archive()
        for invalid in ("", *DATABASES):
            with self.subTest(invalid=invalid):
                self.calls.unlink(missing_ok=True)
                self.env["INVALID_RESTORED"] = invalid
                result = self.invoke()
                calls = self.calls.read_text(encoding="utf-8")
                self.assertEqual(result.returncode == 0, not invalid, result.stderr)
                for database in DATABASES:
                    if database == "pihole-FTL.db" and invalid == "gravity.db":
                        break
                    self.assertIn(
                        f"pihole-FTL /etc/pihole/{database} PRAGMA integrity_check;",
                        calls,
                    )
                if invalid:
                    self.assertIn(f"Integrity check failed for {invalid}", result.stderr)
                self.assertFalse(list(self.work.glob("pihole-restore.*")))

    def test_post_restore_unreadable_database_fails(self) -> None:
        self.make_archive()
        self.env["UNREADABLE_RESTORED"] = "pihole-FTL.db"
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Could not check the integrity of pihole-FTL.db", result.stderr)

    def test_backup_restart_depends_on_restore_safety(self) -> None:
        self.make_archive()
        cases = (
            ("remove", True),
            ("wipe", False),
            ("create", False),
            ("extract", False),
            ("startup", False),
            ("verify", False),
            ("", True),
        )
        for failure, restarted in cases:
            with self.subTest(failure=failure):
                self.calls.unlink(missing_ok=True)
                self.env["FAILURE"] = failure
                self.env["INVALID_RESTORED"] = "gravity.db" if failure == "verify" else ""
                result = self.invoke()
                calls = self.calls.read_text(encoding="utf-8").splitlines()
                self.assertEqual(result.returncode == 0, not failure, result.stderr)
                self.assertIn("docker stop filedata-backup", calls)
                self.assertEqual("docker start filedata-backup" in calls, restarted)
                if failure and not restarted:
                    self.assertIn("filedata-backup remains stopped", result.stderr)
                    self.assertIn("Recover Pi-hole data before manually restarting", result.stderr)
                self.assertFalse(list(self.work.glob("pihole-restore.*")))

    def test_previously_stopped_backup_is_not_started(self) -> None:
        self.make_archive()
        self.env["BACKUP_RUNNING"] = "false"
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls.read_text(encoding="utf-8")
        self.assertNotIn("docker stop filedata-backup", calls)
        self.assertNotIn("docker start filedata-backup", calls)

    def test_backup_restart_failure_is_reported(self) -> None:
        self.make_archive()
        self.env["FAILURE"] = "restart"
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Could not restart filedata-backup", result.stderr)

    def make_wal_archive(self) -> None:
        gravity = self.work / "gravity.db"
        queries = self.work / "pihole-FTL.db"
        gravity.unlink(missing_ok=True)
        queries.unlink(missing_ok=True)
        connection = sqlite3.connect(gravity)
        self.addCleanup(connection.close)
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("CREATE TABLE example (value TEXT)")
        connection.execute("INSERT INTO example VALUES ('data')")
        connection.commit()
        with sqlite3.connect(queries) as db:
            db.execute("CREATE TABLE example (value TEXT)")
        wal = self.work / "gravity.db-wal"
        self.assertTrue(wal.is_file())
        with tarfile.open(self.archive, "w") as archive:
            for path in (gravity, wal, queries):
                archive.add(path, arcname=f"./{path.name}")

    def test_backup_with_sqlite_wal_is_validated(self) -> None:
        self.make_wal_archive()
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_real_pihole_sqlite_validation(self) -> None:
        docker = shutil.which("docker")
        if not docker:
            self.skipTest("Docker is not available")
        image = subprocess.run(
            [docker, "image", "inspect", "pihole/pihole:latest"],
            capture_output=True,
            check=False,
            timeout=10,
        )
        if image.returncode:
            self.skipTest("Docker daemon or Pi-hole image is not available")
        self.env["REAL_DOCKER"] = docker
        for case in ("valid", "corrupt", "wal"):
            with self.subTest(case=case):
                self.calls.unlink(missing_ok=True)
                if case == "wal":
                    self.make_wal_archive()
                else:
                    self.make_archive("gravity.db", case)
                result = self.invoke()
                self.assertEqual(result.returncode == 0, case != "corrupt", result.stderr)
                calls = self.calls.read_text(encoding="utf-8")
                if case == "corrupt":
                    self.assertIn("Invalid backup database gravity.db", result.stderr)
                    self.assertNotIn("pihole_filedata:/restore", calls)
                else:
                    self.assertEqual(calls.count("--entrypoint pihole-FTL"), 2)


if __name__ == "__main__":
    unittest.main()
