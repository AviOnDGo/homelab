import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = ROOT / "googleCloud" / "bootstrap-startup.sh.tftpl"
URL = "git@github.com:example/homelab.git"


class BootstrapGitTests(unittest.TestCase):
    def setUp(self) -> None:
        fixture = tempfile.TemporaryDirectory()
        self.addCleanup(fixture.cleanup)
        self.work = Path(fixture.name)
        self.source = self.work / "source"
        self.remote = self.work / "remote.git"
        self.checkout = self.work / "opt" / "homelab"
        self.checkout.parent.mkdir()
        self.ssh_dir = self.work / "root" / ".ssh"
        self.ssh_dir.mkdir(parents=True)
        (self.ssh_dir / "known_hosts").write_text(
            "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n",
            encoding="utf-8",
        )
        self.secret = self.work / "secret"
        self.secret.write_text("test deploy key\n", encoding="utf-8")
        self.bin = self.work / "bin"
        self.bin.mkdir()
        ssh = self.bin / "ssh"
        ssh.write_text(
            '#!/bin/bash\n'
            '[[ " $* " == *" -i $EXPECTED_KEY "* ]] || exit 1\n'
            'for arg in "$@"; do\n'
            '  case "$arg" in\n'
            '    *git-upload-pack*) exec git-upload-pack "$REMOTE_REPO" ;;\n'
            '  esac\n'
            'done\n'
            'exit 1\n',
            encoding="utf-8",
        )
        ssh.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_AUTHOR_NAME": "Test",
            "GIT_AUTHOR_EMAIL": "test@example.invalid",
            "GIT_COMMITTER_NAME": "Test",
            "GIT_COMMITTER_EMAIL": "test@example.invalid",
            "REMOTE_REPO": str(self.remote),
            "EXPECTED_KEY": str(self.ssh_dir / "homelab_deploy_key"),
            "SECRET_PATH": str(self.secret),
            "TEST_GIT_URL": URL,
            "TEST_SECRET_NAME": "deploy-key",
        }
        self.git("init", "-b", "main", str(self.source))
        (self.source / "tracked").write_text("first\n", encoding="utf-8")
        self.git("-C", str(self.source), "add", "tracked")
        self.git("-C", str(self.source), "commit", "-m", "initial")
        self.git("clone", "--bare", str(self.source), str(self.remote))

    def git(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", *args], env=self.env, capture_output=True, text=True, check=True
        )

    def bootstrap(self, fail_secret: bool = False) -> subprocess.CompletedProcess[str]:
        template = TEMPLATE.read_text(encoding="utf-8")
        marker = "# Optional authenticated clone with runtime secret retrieval.\n"
        block = template.split(marker, 1)[1].split(
            '\nwrite_status "completed phase=bootstrap"', 1
        )[0]
        block = block.replace(
            "bootstrap_git_repo_ssh_url", "TEST_GIT_URL"
        ).replace(
            "bootstrap_git_deploy_key_secret_name", "TEST_SECRET_NAME"
        ).replace("/root/.ssh", str(self.ssh_dir)).replace(
            "/opt/homelab", str(self.checkout)
        )
        script = """
set -Eeuo pipefail
log() { echo "$1"; }
mark_phase_start() { :; }
mark_phase_done() { :; }
metadata_get() { :; }
fetch_secret_value() {
  cat "$SECRET_PATH"
  if [ "$FAIL_SECRET" = yes ]; then return 1; fi
}
""" + block
        return subprocess.run(
            ["bash", "-c", script],
            env={**self.env, "FAIL_SECRET": "yes" if fail_secret else "no"},
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )

    def test_clone_pull_and_existing_checkout(self) -> None:
        result = self.bootstrap()
        self.assertEqual(result.returncode, 0, result.stderr)
        key = self.ssh_dir / "homelab_deploy_key"
        self.assertEqual(key.read_text(encoding="utf-8"), "test deploy key\n")
        self.assertEqual(key.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.ssh_dir.stat().st_mode & 0o777, 0o700)

        (self.source / "tracked").write_text("second\n", encoding="utf-8")
        self.git("-C", str(self.source), "commit", "-am", "second")
        self.git("-C", str(self.source), "push", str(self.remote), "main")
        self.git("-C", str(self.checkout), "pull", "--ff-only")
        self.assertEqual(
            (self.checkout / "tracked").read_text(encoding="utf-8"), "second\n"
        )

        (self.checkout / "local").write_text("preserved\n", encoding="utf-8")
        self.git("-C", str(self.checkout), "config", "--unset", "core.sshCommand")
        self.secret.write_text("rotated deploy key\n", encoding="utf-8")
        result = self.bootstrap()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(key.read_text(encoding="utf-8"), "rotated deploy key\n")
        self.git("-C", str(self.checkout), "pull", "--ff-only")
        self.assertEqual(
            (self.checkout / "local").read_text(encoding="utf-8"), "preserved\n"
        )

    def test_secret_failure_preserves_existing_key_and_removes_temporary_file(self) -> None:
        self.assertEqual(self.bootstrap().returncode, 0)
        key = self.ssh_dir / "homelab_deploy_key"
        self.secret.write_text("partial value", encoding="utf-8")
        result = self.bootstrap(fail_secret=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unable to retrieve deploy key secret", result.stdout)
        self.assertEqual(key.read_text(encoding="utf-8"), "test deploy key\n")
        self.assertEqual(list(self.ssh_dir.glob("homelab_deploy_key.*")), [])

    def test_empty_secret_fails_without_leaving_key(self) -> None:
        self.secret.write_text("", encoding="utf-8")
        result = self.bootstrap()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unable to retrieve deploy key secret", result.stdout)
        self.assertEqual(list(self.ssh_dir.glob("homelab_deploy_key*")), [])

    def test_existing_unrelated_checkout_is_not_reconfigured(self) -> None:
        self.assertEqual(self.bootstrap().returncode, 0)
        self.git("-C", str(self.checkout), "remote", "set-url", "origin", "other")
        result = self.bootstrap()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("different origin", result.stdout)


if __name__ == "__main__":
    unittest.main()
