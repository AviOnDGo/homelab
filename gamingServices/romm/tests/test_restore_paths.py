import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class RommRestorePathTests(unittest.TestCase):
    def setUp(self):
        fixture = tempfile.TemporaryDirectory()
        self.addCleanup(fixture.cleanup)
        self.root = Path(fixture.name)
        self.service = self.root / "gamingServices" / "romm"
        self.filedata = self.root / "backupServices" / "filedata"
        self.service.mkdir(parents=True)
        self.filedata.mkdir(parents=True)
        script = (ROOT / "gamingServices/romm/restore.sh").read_text()
        script = script.replace(
            'FILEDATA_ENV="${FILEDATA_DIR}/.env"',
            'FILEDATA_ENV="${FILEDATA_DIR}/fixture-input"',
        )
        (self.service / "restore.sh").write_text(script)
        (self.filedata / "fixture-input").write_text(
            "ROMM_SYNC_CRYPT_REMOTE=legacy:wrong\n"
        )
        shutil.copy(ROOT / "backupServices/filedata/path.local", self.filedata)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.executable(self.filedata / "start-backup.sh", "exit 0")
        self.executable(
            self.bin / "docker",
            """
printf '%s\\n' "$*" >> "$CALLS"
case "$1" in
  volume) [[ "$2" != inspect ]] ;;
  exec) if [[ "$*" == *psql* ]]; then cat >/dev/null; echo 1; fi ;;
  info|build|run|compose|start|ps) ;;
  *) exit 1 ;;
esac
""",
        )
        self.executable(
            self.bin / "rclone",
            """
case "$1" in
  lsd) ;;
  lsf) echo romm_2026-01-01_00-00-00.sql.zst.gpg ;;
  copy) printf backup > "$3/${2##*/}" ;;
  *) exit 1 ;;
esac
""",
        )
        self.executable(self.bin / "gpg", "echo sql")
        self.executable(self.bin / "zstd", "cat")
        self.env = {
            **os.environ,
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "HOME": str(self.root),
            "CALLS": str(self.root / "calls"),
            "PASSPHRASE": "fixture",
        }

    def executable(self, path, body):
        path.write_text(f"#!/bin/bash\nset -eu\n{body}\n")
        path.chmod(0o755)

    def invoke(self):
        return subprocess.run(
            ["bash", str(self.service / "restore.sh")],
            env=self.env, capture_output=True, text=True, timeout=20, check=False,
        )

    def test_both_restore_stages_load_local_paths_after_credentials(self):
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        runs = [
            line for line in (self.root / "calls").read_text().splitlines()
            if line.startswith("run ")
        ]
        self.assertEqual(len(runs), 2)
        for line in runs:
            args = line.split()
            paths = [
                Path(args[index + 1]).resolve()
                for index, value in enumerate(args) if value == "--env-file"
            ]
            self.assertEqual(
                paths, [self.filedata / "fixture-input", self.filedata / "path.local"]
            )

    def test_missing_local_path_file_fails_before_build(self):
        (self.filedata / "path.local").unlink()
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing", result.stderr)
        self.assertNotIn("build", (self.root / "calls").read_text())


if __name__ == "__main__":
    unittest.main()
