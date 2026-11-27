import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "restore.sh"
MOCK_COMMAND = """#!/usr/bin/env python3
import os
import pathlib
import sys

name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["MOCK_LOG"], "a") as log:
    log.write(name + " " + " ".join(args) + "\\n")

if name == "docker":
    if args[0] == "ps":
        print("hermes")
        if os.environ.get("BACKUP_RUNNING") == "1":
            print("filedata-backup")
    elif args[:2] == ["volume", "inspect"]:
        sys.exit(0)
    elif args[0] == "inspect":
        print("false")
    elif args[0] == "run":
        if "-i" in args:
            sys.stdin.buffer.read()
        if any("find /restore" in arg and "test -n" in arg for arg in args):
            sys.exit(int(os.environ.get("EMPTY_VOLUME", "0")))
elif name == "rclone":
    if args[0] == "lsf":
        print("hermes_2026-01-01_00-00-00.tar.zst.gpg")
    elif args[0] == "copy":
        (pathlib.Path(args[2]) / args[1].split("/")[-1]).write_bytes(b"backup")
    elif args[0] == "copyto":
        pathlib.Path(args[2]).write_bytes(b"backup")
elif name == "gpg":
    sys.stdout.buffer.write(b"archive")
elif name == "zstd":
    sys.stdout.buffer.write(sys.stdin.buffer.read())
elif name == "tar":
    sys.stdin.buffer.read()
    sys.exit(int(os.environ.get("BAD_ARCHIVE", "0")))
"""


class HermesRestoreTests(unittest.TestCase):
    def run_restore(self, answers="", manual=False, **settings):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            for name in ("docker", "rclone", "gpg", "zstd", "tar"):
                command = root / name
                command.write_text(MOCK_COMMAND)
                command.chmod(0o755)
            log = root / "commands"
            env = os.environ.copy()
            env.update(
                PATH=f"{root}:{env['PATH']}",
                MOCK_LOG=str(log),
                PASSPHRASE="test",
                **settings,
            )
            if manual:
                guide = (SCRIPT.parent / "RESTORE_GUIDE.md").read_text()
                block = guide.split("### 2. Manual fallback", 1)[1]
                block = block.split("```bash", 1)[1].split("```", 1)[0]
                block = block.replace(
                    "/path/to/hermes_<timestamp>.tar.zst.gpg",
                    str(root / "backup.tar.zst.gpg"),
                )
                command = ["bash", "-c", block]
            else:
                command = [str(SCRIPT)]
            result = subprocess.run(
                command,
                input=answers,
                text=True,
                capture_output=True,
                env=env,
                check=False,
            )
            return result, log.read_text().splitlines()

    def test_declining_volume_wipe_does_not_stop_hermes(self):
        result, commands = self.run_restore("y\nn\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(" compose " in line for line in commands))
        self.assertFalse(any("docker run " in line for line in commands))

    def test_empty_restored_volume_does_not_start_hermes(self):
        result, commands = self.run_restore("y\ny\n", EMPTY_VOLUME="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("is empty", result.stderr)
        self.assertTrue(any(" compose " in line and " down" in line for line in commands))
        self.assertFalse(any(" compose " in line and " up " in line for line in commands))

    def test_valid_restore_verifies_before_starting(self):
        result, commands = self.run_restore("y\ny\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        verification = next(i for i, line in enumerate(commands) if "test -n" in line)
        startup = next(i for i, line in enumerate(commands) if " compose " in line and " up " in line)
        self.assertLess(verification, startup)

    def test_invalid_archive_does_not_stop_or_clear(self):
        result, commands = self.run_restore("y\ny\n", BAD_ARCHIVE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(" compose " in line for line in commands))
        self.assertFalse(any("docker run " in line for line in commands))

    def test_manual_invalid_archive_does_not_stop_or_clear(self):
        result, commands = self.run_restore("test\n", manual=True, BAD_ARCHIVE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(" compose " in line for line in commands))
        self.assertFalse(any("docker run " in line for line in commands))

    def test_manual_pauses_backup_and_clears_volume(self):
        result, commands = self.run_restore("test\n", manual=True, BACKUP_RUNNING="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        stop = commands.index("docker stop filedata-backup")
        clear = next(i for i, line in enumerate(commands) if "find /restore" in line)
        start = commands.index("docker start filedata-backup")
        self.assertLess(stop, clear)
        self.assertLess(clear, start)
        self.assertFalse(any("volume rm" in line for line in commands))


if __name__ == "__main__":
    unittest.main()
