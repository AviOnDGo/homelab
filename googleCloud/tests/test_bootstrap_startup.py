import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STARTUP_SCRIPT = ROOT / "googleCloud" / "bootstrap-startup.sh.tftpl"
TERRAFORM_CONFIG = ROOT / "googleCloud" / "main.tf"


class BootstrapStartupTests(unittest.TestCase):
    def test_startup_does_not_clone_repository_or_retrieve_deploy_key(self) -> None:
        startup_script = STARTUP_SCRIPT.read_text(encoding="utf-8")
        terraform_config = TERRAFORM_CONFIG.read_text(encoding="utf-8")

        for removed_feature in (
            "git clone",
            "homelab_deploy_key",
            "fetch_secret_value",
            "homelab-git-url",
        ):
            with self.subTest(removed_feature=removed_feature):
                self.assertNotIn(removed_feature, startup_script)
                self.assertNotIn(removed_feature, terraform_config)

        self.assertIn('bootstrap_startup_script = file(', terraform_config)
        self.assertNotIn("bootstrap_git_", terraform_config)


if __name__ == "__main__":
    unittest.main()
