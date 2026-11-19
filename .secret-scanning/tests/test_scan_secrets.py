"""Regression tests for credential detection in local Git gates."""

import importlib.util
import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "scan-secrets-diff.py"
SPEC = importlib.util.spec_from_file_location("scan_secrets_diff", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
SCANNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SCANNER)


def diff(content: str, filename: str = "config.json") -> str:
    """Create an added line with a known new-file line number."""
    return f"+++ b/{filename}\n@@ -0,0 +7 @@\n+{content}\n"


class ScanSecretsTests(unittest.TestCase):
    def test_detects_json_xml_and_environment_literals(self) -> None:
        value = "test" + "Credential123456"
        cases = [
            json.dumps({"APIKey": value}),
            "<ApiKey>" + value + "</ApiKey>",
            "DB_PASSWORD=" + value,
            json.dumps({"AdminPassword": value}),
            json.dumps({"password": value + " with spaces ()[]"}),
            json.dumps({"Authorization": "Bearer " + value}),
        ]
        for content in cases:
            with self.subTest(content=content):
                findings = SCANNER.scan_diff(diff(content).splitlines(), [])
                self.assertTrue(findings)
                self.assertEqual(findings[0][:2], ("config.json", 7))

    def test_examples_are_scanned_but_placeholders_and_references_are_allowed(
        self,
    ) -> None:
        for value in [
            "your_password_here",
            "change-me-before-use",
            "${DB_PASSWORD}",
            "$DB_PASSWORD",
            "{env:DB_PASSWORD}",
            "{file:private-password}",
        ]:
            content = json.dumps({"password": value})
            self.assertEqual(
                SCANNER.scan_diff(diff(content, ".env.example").splitlines(), []),
                [],
            )
        literal = json.dumps({"password": "test" + "Credential123456"})
        self.assertTrue(
            SCANNER.scan_diff(diff(literal, ".env.example").splitlines(), [])
        )

    def test_removed_credentials_and_non_secret_keys_do_not_fail(self) -> None:
        removed = "-<ApiKey>" + "syntheticCredential123456" + "</ApiKey>"
        content = diff(
            '{"SYNC_TOKENSERVER__FXA_EMAIL_DOMAIN": "api.accounts.firefox.com"}'
        )
        self.assertEqual(
            SCANNER.scan_diff((removed + "\n" + content).splitlines(), []), []
        )

    def test_allowlist_comments_do_not_exempt_unrelated_findings(self) -> None:
        content = json.dumps({"APIKey": "test" + "Credential123456"})
        self.assertEqual(
            SCANNER.scan_diff(
                diff(content).splitlines(), [re.compile(r'^{"APIKey": "test')]
            ),
            [],
        )
        with tempfile.TemporaryDirectory() as directory:
            allowlist = Path(directory) / "allowlist"
            allowlist.write_text("# comments and blank lines are not exemptions\n\n")
            result = subprocess.run(
                ["python3", str(SCRIPT), str(allowlist)],
                input=diff(content),
                text=True,
                capture_output=True,
                check=False,
            )
        self.assertEqual(result.returncode, 1)
        self.assertIn("config.json:7", result.stdout)
        self.assertNotIn("testCredential123456", result.stdout + result.stderr)

    def test_invalid_allowlist_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            allowlist = Path(directory) / "allowlist"
            allowlist.write_text("[")
            result = subprocess.run(
                ["python3", str(SCRIPT), str(allowlist)],
                input="",
                text=True,
                capture_output=True,
                check=False,
            )
        self.assertEqual(result.returncode, 2)
        self.assertIn("could not complete", result.stderr)

    def test_known_token_format_without_field_is_detected(self) -> None:
        token = "ghp_" + "syntheticCredential123456"
        self.assertTrue(SCANNER.scan_diff(diff(token).splitlines(), []))

    def test_staged_wrapper_rejects_key_without_scanning_unstaged_files(self) -> None:
        wrapper = SCRIPT.with_name("scan-secrets-staged.sh")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(
                ["git", "init", "-q", directory], check=True, capture_output=True
            )
            config = root / "config.json"
            config.write_text(json.dumps({"ApiKey": "test" + "Credential123456"}))
            clean = subprocess.run(
                ["bash", str(wrapper)], cwd=root, capture_output=True, check=False
            )
            self.assertEqual(clean.returncode, 0)
            subprocess.run(["git", "add", "config.json"], cwd=root, check=True)
            staged = subprocess.run(
                ["bash", str(wrapper)], cwd=root, capture_output=True, check=False
            )
            self.assertEqual(staged.returncode, 1)
            self.assertNotIn(b"testCredential123456", staged.stdout)

    def test_push_wrapper_and_git_failures(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake_git = root / "git"
            fake_git.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                'if [[ "$1" == "-C" ]]; then shift 2; fi\n'
                'case "$1" in\n'
                "rev-parse)\n"
                '  if [[ "$2" == "--show-toplevel" ]]; then\n'
                '    printf "%s\\n" "$FAKE_REPO"\n'
                "  fi ;;\n"
                "branch|config|rev-list)\n"
                '  if [[ "$FAIL_GIT" == "true" ]]; then\n'
                '    echo "synthetic git failure" >&2; exit 3\n'
                "  fi\n"
                '  if [[ "$1" == "branch" ]]; then printf "feature\\n"; fi\n'
                '  if [[ "$1" == "config" ]]; then printf "origin\\n"; fi\n'
                '  if [[ "$1" == "rev-list" ]]; then printf "synthetic-commit\\n"; fi ;;\n'
                "log|diff)\n"
                '  if [[ "$FAIL_GIT" == "true" ]]; then\n'
                '    echo "synthetic git failure" >&2; exit 3\n'
                "  fi\n"
                '  if [[ "$1" == "log" ]]; then echo synthetic-commit; fi ;;\n'
                'show) cat "$FAKE_DIFF" ;;\n'
                "*) exit 2 ;;\n"
                "esac\n"
            )
            fake_git.chmod(0o755)
            fake_diff = root / "diff"
            value = "test" + "Credential123456"
            fake_diff.write_text(diff(json.dumps({"ApiKey": value})))
            env = {
                **os.environ,
                "PATH": str(root) + os.pathsep + os.environ["PATH"],
                "FAKE_REPO": str(root),
                "FAKE_DIFF": str(fake_diff),
                "FAIL_GIT": "false",
            }
            result = subprocess.run(
                ["bash", str(SCRIPT.with_name("scan-secrets-range.sh"))],
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn("config.json:7", result.stdout)
            self.assertNotIn(value, result.stdout + result.stderr)
            env["FAIL_GIT"] = "true"
            for name in ("scan-secrets-staged.sh", "scan-secrets-range.sh"):
                with self.subTest(wrapper=name):
                    result = subprocess.run(
                        ["bash", str(SCRIPT.with_name(name))],
                        env=env,
                        text=True,
                        capture_output=True,
                        check=False,
                    )
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn("passed", result.stdout)
                    self.assertIn("synthetic git failure", result.stderr)


if __name__ == "__main__":
    unittest.main()
