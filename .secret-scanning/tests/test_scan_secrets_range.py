"""Regression tests for outgoing commit selection in the local push scanner."""

import pathlib
import subprocess
import tempfile
import unittest


SCANNER = pathlib.Path(__file__).resolve().parents[1] / "scripts/scan-secrets-range.sh"
TEST_VALUE = "SyntheticFixture123"


class PushRangeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repo = pathlib.Path(self.temporary.name)
        self.git("init", "--quiet", "--initial-branch=main")
        self.git("config", "user.name", "Scanner Test")
        self.git("config", "user.email", "scanner@example.invalid")
        self.git("config", "core.hooksPath", str(self.repo / "no-hooks"))
        self.git("config", "commit.gpgsign", "false")
        self.commit_file("baseline.txt", "baseline\n")
        self.git("remote", "add", "origin", str(self.repo / "unused-remote"))
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")
        self.git("switch", "--quiet", "-c", "feature")
        self.git("update-ref", "refs/remotes/origin/feature", "HEAD")
        self.git("branch", "--set-upstream-to=origin/feature")

    def git(self, *args: str) -> str:
        return subprocess.check_output(
            ["git", *args], cwd=self.repo, text=True, stderr=subprocess.PIPE
        ).strip()

    def commit_file(self, name: str, content: str) -> None:
        fixture = self.repo / name
        fixture.write_text(content, encoding="utf-8")  # lgtm[py/clear-text-storage-sensitive-data]
        self.git("add", "--", name)
        self.git("commit", "--quiet", "-m", "Add fixture")

    def scan(self) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["bash", str(SCANNER)],
            cwd=self.repo,
            text=True,
            capture_output=True,
            check=False,
        )

    def merge_remote_main(self) -> None:
        self.commit_file("feature.txt", "feature work\n")
        self.git("switch", "--quiet", "main")
        secret_label = "secret"
        self.commit_file(
            "old.txt", f'echo "Missing required {secret_label}: {TEST_VALUE}"\n'
        )
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")
        self.git("switch", "--quiet", "feature")
        self.git("merge", "--no-edit", "origin/main")

    def test_empty_range_passes(self) -> None:
        result = self.scan()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_merged_remote_history_is_not_rescanned(self) -> None:
        self.merge_remote_main()
        result = self.scan()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_new_secret_after_merging_remote_main_is_blocked(self) -> None:
        self.merge_remote_main()
        self.commit_file("new.txt", f"password={TEST_VALUE}\n")
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("Secret scan failed", result.stdout)

    def test_new_local_commit_merged_from_another_branch_is_blocked(self) -> None:
        self.git("switch", "--quiet", "-c", "local-work")
        self.commit_file("local.txt", f"password={TEST_VALUE}\n")
        self.git("switch", "--quiet", "feature")
        self.git("merge", "--no-edit", "local-work")
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("Secret scan failed", result.stdout)

    def test_no_upstream_still_scans_new_commits(self) -> None:
        self.git("branch", "--unset-upstream")
        self.commit_file("new.txt", f"password={TEST_VALUE}\n")
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("Secret scan failed", result.stdout)

    def test_local_main_without_upstream_scans_new_commits(self) -> None:
        self.git("switch", "--quiet", "main")
        self.commit_file("new.txt", f"password={TEST_VALUE}\n")
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("Secret scan failed", result.stdout)

    def test_example_placeholder_passes(self) -> None:
        field_name = "tailscale_oauth_client_" + "secret"
        self.commit_file(
            "terraform.tfvars.example",
            f'{field_name} = "your-oauth-client-secret"\n',
        )
        result = self.scan()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_example_secret_is_blocked(self) -> None:
        field_name = "tailscale_oauth_client_" + "secret"
        self.commit_file(
            "terraform.tfvars.example",
            f'{field_name} = "{TEST_VALUE}"\n',
        )
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("terraform.tfvars.example:1", result.stdout)
        self.assertNotIn(TEST_VALUE, result.stdout + result.stderr)

    def test_configured_remote_is_used(self) -> None:
        self.git("remote", "rename", "origin", "upstream")
        self.commit_file("remote.txt", f"password={TEST_VALUE}\n")
        self.git("update-ref", "refs/remotes/upstream/main", "HEAD")
        result = self.scan()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
