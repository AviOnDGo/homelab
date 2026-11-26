import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HOST_SCRIPTS = Path(__file__).resolve().parents[1]


class HostScriptTests(unittest.TestCase):
    def setUp(self) -> None:
        fixture = tempfile.TemporaryDirectory()
        self.addCleanup(fixture.cleanup)
        self.work = Path(fixture.name)
        self.helpers = self.work / "bin"
        self.helpers.mkdir()
        self.log = self.work / "commands"
        self.log.touch()
        self.env = {**os.environ, "PATH": str(self.helpers), "LOG": str(self.log)}
        self.env["HELPERS"] = str(self.helpers)
        (self.helpers / "bash").symlink_to(shutil.which("bash") or "/bin/bash")
        self.stub("sudo", 'printf "%s\\n" "$*" >> "$LOG"')

    def stub(self, name: str, body: str, directory: Path | None = None) -> None:
        path = (directory or self.helpers) / name
        path.write_text(f"#!/bin/bash\nset -eu\n{body}\n", encoding="utf-8")
        path.chmod(0o755)

    def invoke(self, script: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(script)],
            cwd=self.work,
            env=self.env,
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )

    @unittest.skipIf(os.geteuid() == 0, "Bootstrap requires a non-root operator")
    @unittest.skipUnless(Path("/run/systemd/system").is_dir(), "Requires systemd")
    def test_bootstrap_from_another_directory_and_repeat(self) -> None:
        scripts = self.work / "host scripts"
        scripts.mkdir()
        bootstrap = scripts / "bootstrap.sh"
        shutil.copy2(HOST_SCRIPTS / bootstrap.name, bootstrap)
        (self.helpers / "dirname").symlink_to(shutil.which("dirname") or "/bin/dirname")
        self.stub(
            "id",
            'if [[ $1 == -un ]]; then echo operator; else echo "$TEST_GROUPS"; fi',
        )
        self.stub("dpkg-query", 'printf "installed installed installed "')
        for component in ("docker", "ssh", "tailscale"):
            self.stub(f"configure-{component}.sh", f'echo {component} >> "$LOG"', scripts)

        self.env["TEST_GROUPS"] = "operator sudo"
        first = self.invoke(bootstrap)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.env["TEST_GROUPS"] = "operator sudo docker"
        second = self.invoke(bootstrap)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(
            self.log.read_text().splitlines(),
            [
                "docker",
                "usermod -aG docker operator",
                "ssh",
                "tailscale",
                "docker",
                "ssh",
                "tailscale",
            ],
        )

    def test_installed_tailscale_is_not_enrolled(self) -> None:
        self.stub("tailscale", 'printf "tailscale %s\\n" "$*" >> "$LOG"')
        result = self.invoke(HOST_SCRIPTS / "configure-tailscale.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(), "tailscale version\n")

    def rclone_env(self) -> Path:
        for tool in ("dirname", "mkdir", "mv"):
            (self.helpers / tool).symlink_to(shutil.which(tool) or f"/bin/{tool}")
        self.stub("rclone", 'printf "rclone %s\\n" "$*" >> "$LOG"')
        config = self.work / "rclone" / "rclone.conf"
        self.env.update(RCLONE_CONFIG=str(config), DROPBOX_AUTH_TOKEN="access")
        self.env["DROPBOX_REFRESH_TOKEN"] = "refresh"
        return config

    def test_rclone_backs_up_and_overwrites_config(self) -> None:
        config = self.rclone_env()
        first = self.invoke(HOST_SCRIPTS / "configure-rclone.sh")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertFalse(config.with_suffix(".conf.bak").exists())
        config.write_text("[other]\ntype = local\n")
        second = self.invoke(HOST_SCRIPTS / "configure-rclone.sh")
        self.assertEqual(second.returncode, 0, second.stderr)
        backup = config.with_suffix(".conf.bak")
        self.assertEqual(backup.read_text(), "[other]\ntype = local\n")
        text = config.read_text()
        self.assertTrue(text.startswith("[dropbox]\ntype = dropbox\n"))
        self.assertIn('"refresh_token":"refresh"', text)
        self.assertNotIn("other", text)
        self.assertEqual(config.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.log.read_text(), "rclone lsd dropbox:\n" * 2)

    def test_rclone_without_both_tokens_fails(self) -> None:
        config = self.rclone_env()
        del self.env["DROPBOX_REFRESH_TOKEN"]
        result = self.invoke(HOST_SCRIPTS / "configure-rclone.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Set both", result.stderr)
        self.assertFalse(config.parent.exists())
        self.assertEqual(self.log.read_text(), "")

    def test_rclone_install_refreshes_apt_indexes_only_when_needed(self) -> None:
        self.rclone_env()
        (self.helpers / "rclone").unlink()
        (self.helpers / "chmod").symlink_to(shutil.which("chmod") or "/bin/chmod")
        self.stub("sudo", '"$@"')
        self.stub(
            "apt-get",
            'printf "apt-get %s\\n" "$*" >> "$LOG"; '
            'if [[ $1 == install ]]; then '
            'printf \'#!/bin/bash\\necho "rclone $*" >> "$LOG"\\n\' '
            '> "$HELPERS/rclone"; '
            'chmod +x "$HELPERS/rclone"; fi',
        )
        result = self.invoke(HOST_SCRIPTS / "configure-rclone.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.log.read_text().splitlines()
        self.assertEqual(calls[:2], ["apt-get update", "apt-get install -y rclone"])
        self.assertEqual(calls[2:], ["rclone lsd dropbox:"])

    def test_nvidia_missing_driver_does_not_change_runtime(self) -> None:
        self.stub("apt-get", 'exit 1')
        self.stub("dockerd", 'exit 1')
        self.stub("nvidia-smi", 'exit 1')
        result = self.invoke(HOST_SCRIPTS / "configure-nvidia-container-toolkit.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("working NVIDIA host driver", result.stderr)
        self.assertEqual(self.log.read_text(), "")
