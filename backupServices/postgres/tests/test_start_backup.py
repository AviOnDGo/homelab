import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VOLUMES = (
    "firefly_postgresdata\nromm_postgresdata\npaperless_postgresdata\n"
    "immich_postgresdata\ninvidious_postgresdata\nfirefoxsync_postgresdata"
)
NETWORKS = "finance_network\ngames_network\nknowledge_network\nmedia_network\nsecurity_network"


class StartBackupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ("start-backup.sh", "backup-databases.conf", "docker-compose.yml"):
            shutil.copy(ROOT / name, self.root / name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        docker = self.bin / "docker"
        docker.write_text(
            """#!/usr/bin/env python3
import os
import shutil
import sys

if sys.argv[1:3] == ["volume", "ls"]:
    if os.environ.get("MOCK_DOCKER_FAIL") == "volume":
        sys.exit(1)
    print(os.environ["MOCK_VOLUMES"])
elif sys.argv[1:3] == ["network", "ls"]:
    if os.environ.get("MOCK_DOCKER_FAIL") == "network":
        sys.exit(1)
    print(os.environ["MOCK_NETWORKS"])
elif sys.argv[1] == "compose":
    args = sys.argv[1:]
    override = args[args.index("-f", args.index("-f") + 1) + 1]
    shutil.copyfile(override, os.environ["MOCK_OVERRIDE"])
    open(os.environ["MOCK_ARGS"], "w").write("\\n".join(args))
    sys.exit(int(os.environ.get("MOCK_COMPOSE_EXIT", "0")))
else:
    sys.exit(2)
""",
            encoding="utf-8",
        )
        docker.chmod(0o755)
        self.env = {
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "HOME": str(self.root),
            "TMPDIR": str(self.root),
            "MOCK_VOLUMES": VOLUMES,
            "MOCK_NETWORKS": NETWORKS,
            "MOCK_OVERRIDE": str(self.root / "override.yml"),
            "MOCK_ARGS": str(self.root / "args"),
        }

    def run_start(self, profile, **env):
        return subprocess.run(
            ["bash", str(self.root / "start-backup.sh"), profile],
            env={**self.env, **env},
            text=True,
            capture_output=True,
            check=False,
        )

    def merged_config(self):
        docker = shutil.which("docker")
        if docker is None:
            self.skipTest("Docker Compose is not available")
        result = subprocess.run(
            [
                docker,
                "compose",
                "--env-file",
                "/dev/null",
                "--project-directory",
                str(self.root),
                "-f",
                str(self.root / "docker-compose.yml"),
                "-f",
                str(self.root / "override.yml"),
                "config",
                "--no-env-resolution",
                "--format",
                "json",
            ],
            env={"PATH": os.defpath, "HOME": str(self.root)},
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_profiles_generate_exact_resources_and_cron_jobs(self):
        cases = {
            "default": (
                {"firefly", "paperless", "immich", "invidious", "firefoxsync"},
                {"finance_network", "knowledge_network", "media_network", "security_network"},
            ),
            "local": (
                {"romm", "paperless", "immich", "invidious", "firefoxsync"},
                {"games_network", "knowledge_network", "media_network", "security_network"},
            ),
            "prod": ({"firefly"}, {"finance_network"}),
        }
        for profile, (names, networks) in cases.items():
            with self.subTest(profile=profile):
                result = self.run_start(profile)
                self.assertEqual(result.returncode, 0, result.stderr)
                config = self.merged_config()
                service = config["services"]["db-backup"]
                self.assertEqual(set(service["networks"]), networks)
                mounts = {mount["target"]: mount for mount in service["volumes"]}
                self.assertEqual(
                    set(mounts),
                    {f"/var/lib/postgresql/{name}" for name in names} | {"/run/secrets"},
                )
                for name in names:
                    mount = mounts[f"/var/lib/postgresql/{name}"]
                    self.assertEqual(mount["source"], f"{name}_postgresdata")
                    self.assertTrue(mount["read_only"])
                self.assertTrue(mounts["/run/secrets"]["read_only"])
                command = service["command"][2]
                for name in names:
                    self.assertIn(f"${{{name.upper()}_CRON_SCHEDULE:-}}", command)
                    self.assertIn(f"backup-script.sh {name}", command)
                self.assertEqual(command.count("backup-script.sh "), len(names))
                self.assertIn("--project-directory", (self.root / "args").read_text())
                self.assertFalse(list(self.root.glob("postgres-compose.*.yml")))

    def test_missing_resources_or_invalid_registry_fail_before_compose(self):
        cases = (
            {"MOCK_VOLUMES": VOLUMES.replace("firefoxsync_postgresdata", "")},
            {"MOCK_NETWORKS": NETWORKS.replace("security_network", "")},
        )
        for env in cases:
            with self.subTest(env=env):
                result = self.run_start("local", **env)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("ERROR: Required", result.stderr)
                self.assertFalse((self.root / "args").exists())
        registry = self.root / "backup-databases.conf"
        registry.write_text(registry.read_text() + "invalid|entry\n")
        result = self.run_start("local")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Invalid entry", result.stderr)
        self.assertFalse((self.root / "args").exists())

    def test_compose_failure_removes_temporary_override(self):
        result = self.run_start("prod", MOCK_COMPOSE_EXIT="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(list(self.root.glob("postgres-compose.*.yml")))

    def test_docker_failure_does_not_start_compose(self):
        for resource in ("volume", "network"):
            with self.subTest(resource=resource):
                result = self.run_start("prod", MOCK_DOCKER_FAIL=resource)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("ERROR: Cannot list Docker", result.stderr)
                self.assertFalse((self.root / "args").exists())

    def test_generated_command_validates_and_writes_schedule(self):
        result = self.run_start("prod")
        self.assertEqual(result.returncode, 0, result.stderr)
        command = self.merged_config()["services"]["db-backup"]["command"][2]
        crontab = self.root / "crontab"
        command = command.replace("$$", "$").replace("/etc/crontabs/root", str(crontab))
        crond = self.bin / "crond"
        crond.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        crond.chmod(0o755)
        for schedule, expected_status in (
            ("5 3 * * *", 0),
            ("5 3 * *", 1),
            ("5 3 * * *;invalid", 1),
        ):
            with self.subTest(schedule=schedule):
                result = subprocess.run(
                    ["/bin/sh", "-ec", command],
                    env={"PATH": str(self.bin), "FIREFLY_CRON_SCHEDULE": schedule},
                    text=True,
                    capture_output=True,
                    check=False,
                )
                self.assertEqual(result.returncode, expected_status, result.stderr)
                if expected_status == 0:
                    self.assertIn(
                        "5 3 * * * sh /usr/local/bin/backup-script.sh firefly\n",
                        crontab.read_text(),
                    )
                else:
                    self.assertIn("ERROR:", result.stderr)

    def test_invalid_profile_is_rejected(self):
        result = self.run_start("remote")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Usage:", result.stderr)
        self.assertFalse((self.root / "args").exists())


if __name__ == "__main__":
    unittest.main()
