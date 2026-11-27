import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "gcp-duckdns-update.yml"


class TailscaleInstallTests(unittest.TestCase):
    def test_install_script_survives_gcloud_prompt_and_checks_installation(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        install_step = workflow.split("      - name: Install Tailscale on VM\n", 1)[1]
        run = install_step.split("        run: |\n", 1)[1].split(
            "\n      - name:", 1
        )[0]
        script = textwrap.dedent(run)

        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            for name in ("bash", "sh", "cat", "chmod"):
                (work / name).symlink_to(shutil.which(name))
            for name, body in {
                "gcloud": """
if [[ " $* " != *" --quiet "* ]]; then
  cat >/dev/null
fi
exec bash -s
""",
                "curl": 'printf \'#!/bin/bash\\nexit 0\\n\' > "$MOCK_BIN/tailscale"\n'
                'chmod +x "$MOCK_BIN/tailscale"\n',
                "systemctl": 'printf "%s\\n" "$*" > "$MOCK_BIN/systemctl-calls"\n',
            }.items():
                executable = work / name
                executable.write_text(f"#!/bin/bash\nset -eu\n{body}", encoding="utf-8")
                executable.chmod(0o755)
            env = {
                **os.environ,
                "PATH": str(work),
                "MOCK_BIN": str(work),
                "VM_NAME": "test-vm",
                "PROJECT_ID": "test-project",
                "ZONE": "test-zone",
            }
            result = subprocess.run(
                ["bash", "-e", "-c", script],
                env=env,
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                (work / "systemctl-calls").read_text(encoding="utf-8"),
                "enable --now tailscaled\n",
            )

            (work / "tailscale").unlink()
            (work / "curl").write_text("#!/bin/bash\nexit 0\n", encoding="utf-8")
            result = subprocess.run(
                ["bash", "-e", "-c", script],
                env=env,
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
