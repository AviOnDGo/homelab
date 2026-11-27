import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = ROOT / "googleCloud" / "bootstrap-startup.sh.tftpl"
URL = "git@github.com:example/homelab.git"
GIT_LOCATION_VARS = {
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_COMMON_DIR",
}


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
        keyscan = self.bin / "ssh-keyscan"
        keyscan.write_text(
            '#!/bin/bash\n'
            'printf "%s\\n" "$*" >> "$SCAN_LOG"\n'
            'if [ "${SCAN_FAIL:-no}" = yes ]; then exit 1; fi\n'
            'host="$4"\n'
            'if [ "$2" != 22 ]; then host="[$host]:$2"; fi\n'
            'printf "%s ssh-ed25519 '
            'AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\\n" '
            '"$host"\n',
            encoding="utf-8",
        )
        keyscan.chmod(0o755)
        self.env = {
            **{
                key: value
                for key, value in os.environ.items()
                if key not in GIT_LOCATION_VARS
            },
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
            "SCAN_LOG": str(self.work / "scan-log"),
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
        ).replace("$${", "${")
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

    def test_scans_configured_endpoint_and_reuses_known_host(self) -> None:
        cases = (
            ("git@other.example:owner/repo.git", "other.example", 22),
            ("ssh://git@host.example/owner/repo.git", "host.example", 22),
            ("ssh://git@ssh.github.com:443/owner/repo.git", "ssh.github.com", 443),
            ("ssh://git@[2001:db8::1]:2222/owner/repo.git", "2001:db8::1", 2222),
        )
        for url, host, port in cases:
            with self.subTest(url=url):
                if self.checkout.exists():
                    self.git("-C", str(self.checkout), "remote", "set-url", "origin", url)
                self.env["TEST_GIT_URL"] = url
                result = self.bootstrap()
                self.assertEqual(result.returncode, 0, result.stderr)
                expected = f"-p {port} -H {host}"
                calls = (self.work / "scan-log").read_text(encoding="utf-8").splitlines()
                self.assertEqual(calls[-1], expected)
                result = self.bootstrap()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(
                    (self.work / "scan-log").read_text(encoding="utf-8").splitlines(),
                    calls,
                )

    def test_invalid_ssh_url_is_rejected(self) -> None:
        for url in (
            "https://github.com/owner/repo",
            "ssh://host:99999/repo",
            "git@-option:owner/repo",
        ):
            with self.subTest(url=url):
                self.env["TEST_GIT_URL"] = url
                result = self.bootstrap()
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.checkout.exists())

    def test_existing_checkout_fails_if_host_scan_fails(self) -> None:
        self.assertEqual(self.bootstrap().returncode, 0)
        url = "ssh://git@other.example:443/owner/repo.git"
        self.git("-C", str(self.checkout), "remote", "set-url", "origin", url)
        self.env["TEST_GIT_URL"] = url
        self.env["SCAN_FAIL"] = "yes"
        result = self.bootstrap()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unable to scan SSH host key", result.stdout)
        self.assertTrue((self.checkout / ".git").exists())

    def test_fixture_ignores_inherited_git_locations(self) -> None:
        inherited = {key: str(self.work / "outside") for key in GIT_LOCATION_VARS}
        with patch.dict(os.environ, inherited):
            nested = BootstrapGitTests("test_clone_pull_and_existing_checkout")
            try:
                nested.setUp()
                self.assertTrue(GIT_LOCATION_VARS.isdisjoint(nested.env))
                result = nested.bootstrap()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse((self.work / "outside").exists())
            finally:
                nested.doCleanups()


if __name__ == "__main__":
    unittest.main()
