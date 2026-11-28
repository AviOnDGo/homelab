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
        for name in (
            "start-backup.sh",
            "backup-databases.conf",
            "docker-compose.yml",
            "path.local",
            "path.prod",
        ):
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

    def run_start(self, *args, **env):
        return subprocess.run(
            ["bash", str(self.root / "start-backup.sh"), *args],
            env={**self.env, **env},
            text=True,
            capture_output=True,
            check=False,
        )

    def merged_config(self, resolve_env=False):
        docker = shutil.which("docker")
        if docker is None:
            self.skipTest("Docker Compose is not available")
        args = [
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
            "--format",
            "json",
        ]
        if not resolve_env:
            args.append("--no-env-resolution")
        result = subprocess.run(
            args,
            env={"PATH": os.defpath, "HOME": str(self.root)},
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_profiles_generate_exact_resources_and_cron_jobs(self):
        policies = {}
        for line in (self.root / "backup-databases.conf").read_text().splitlines():
            if line and not line.startswith("#"):
                name, _, _, _, retention, schedule = line.split("|")
                policies[name] = (retention, schedule)
        cases = {
            "default": (
                {"firefly", "romm", "paperless", "immich", "invidious", "firefoxsync"},
                {"finance_network", "games_network", "knowledge_network", "media_network",
                 "security_network"},
            ),
            "local": (
                {"romm", "paperless", "immich", "invidious"},
                {"games_network", "knowledge_network", "media_network"},
            ),
            "prod": ({"firefly"}, {"finance_network"}),
        }
        for profile, (names, networks) in cases.items():
            with self.subTest(profile=profile):
                args = (profile, "local") if profile == "default" else (profile,)
                result = self.run_start(*args)
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
                environment = service["environment"]
                for name in names:
                    self.assertIn(f"${{{name.upper()}_CRON_SCHEDULE:-}}", command)
                    self.assertIn(f"backup-script.sh {name}", command)
                    retention, schedule = policies[name]
                    self.assertEqual(environment[f"{name.upper()}_CRON_SCHEDULE"], schedule)
                    self.assertEqual(
                        environment[f"DB_BACKUP_{name.upper()}_RETENTION_DAYS"],
                        retention,
                    )
                self.assertEqual(len(environment), 2 * len(names))
                self.assertEqual(command.count("backup-script.sh "), len(names))
                self.assertIn("--project-directory", (self.root / "args").read_text())
                self.assertFalse(list(self.root.glob("postgres-compose.*.yml")))

    def test_missing_resources_or_invalid_registry_fail_before_compose(self):
        cases = (
            (("local",), {"MOCK_VOLUMES": VOLUMES.replace("immich_postgresdata", "")}),
            (("local",), {"MOCK_NETWORKS": NETWORKS.replace("knowledge_network", "")}),
            (("default", "local"),
             {"MOCK_VOLUMES": VOLUMES.replace("firefoxsync_postgresdata", "")}),
            (("default", "local"),
             {"MOCK_NETWORKS": NETWORKS.replace("security_network", "")}),
        )
        for args, env in cases:
            with self.subTest(args=args, env=env):
                result = self.run_start(*args, **env)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("ERROR: Required", result.stderr)
                self.assertFalse((self.root / "args").exists())
        registry = self.root / "backup-databases.conf"
        registry.write_text(registry.read_text() + "invalid|entry\n")
        result = self.run_start("local")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Invalid entry", result.stderr)
        self.assertFalse((self.root / "args").exists())

    def test_local_does_not_require_firefoxsync_resources(self):
        result = self.run_start(
            "local",
            MOCK_VOLUMES=VOLUMES.replace("firefoxsync_postgresdata", ""),
            MOCK_NETWORKS=NETWORKS.replace("security_network", ""),
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_each_registry_entry_requires_default_profile(self):
        registry = self.root / "backup-databases.conf"
        registry.write_text(
            registry.read_text().replace(
                "romm|romm_postgresdata|default,local|",
                "romm|romm_postgresdata|local|",
            )
        )
        result = self.run_start("prod")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("romm must include the default profile", result.stderr)
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

    def test_rejects_nonpositive_retention_before_compose(self):
        registry = self.root / "backup-databases.conf"
        original = registry.read_text()
        for network, value in (
            ("finance_network", "0"),
            ("finance_network", "-1"),
            ("games_network", "0"),
        ):
            with self.subTest(network=network, value=value):
                current = "120" if network == "finance_network" else "30"
                registry.write_text(
                    original.replace(f"{network}|{current}|", f"{network}|{value}|")
                )
                result = self.run_start("prod")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("must be at least one day", result.stderr)
                self.assertFalse((self.root / "args").exists())

    def test_one_day_retention_is_generated(self):
        registry = self.root / "backup-databases.conf"
        registry.write_text(
            registry.read_text().replace("finance_network|120|", "finance_network|1|")
        )
        result = self.run_start("prod")
        self.assertEqual(result.returncode, 0, result.stderr)
        environment = self.merged_config()["services"]["db-backup"]["environment"]
        self.assertEqual(environment["DB_BACKUP_FIREFLY_RETENTION_DAYS"], "1")

    def test_schedule_validation_checks_field_count_and_characters(self):
        registry = self.root / "backup-databases.conf"
        original = registry.read_text()
        for schedule in (
            "5 3 * *",
            "5 3 * * * *",
            "5 3 * * *;invalid",
        ):
            with self.subTest(schedule=schedule):
                registry.write_text(original.replace("5 3 * * *", schedule))
                result = self.run_start("prod")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Invalid entry", result.stderr)
                self.assertFalse((self.root / "args").exists())

        schedule = "0,30 1-3/2 * JAN,MAR MON-FRI"
        registry.write_text(original.replace("5 3 * * *", schedule))
        result = self.run_start("prod")
        self.assertEqual(result.returncode, 0, result.stderr)
        environment = self.merged_config()["services"]["db-backup"]["environment"]
        self.assertEqual(environment["FIREFLY_CRON_SCHEDULE"], schedule)

    def test_registry_schedule_overrides_legacy_environment(self):
        base = self.root / "docker-compose.yml"
        base.write_text(
            base.read_text().replace("env_file: .env", "env_file: settings.txt")
        )
        (self.root / "settings.txt").write_text(
            "FIREFLY_CRON_SCHEDULE=0 0 * * *\nFIREFLY_BACKUP_RETENTION_DAYS=90\n"
        )
        result = self.run_start("prod")
        self.assertEqual(result.returncode, 0, result.stderr)
        environment = self.merged_config(resolve_env=True)["services"]["db-backup"][
            "environment"
        ]
        self.assertEqual(environment["FIREFLY_CRON_SCHEDULE"], "5 3 * * *")
        self.assertEqual(environment["DB_BACKUP_FIREFLY_RETENTION_DAYS"], "120")
        self.assertEqual(environment["FIREFLY_BACKUP_RETENTION_DAYS"], "90")

    def test_selected_destination_overrides_legacy_environment(self):
        base = self.root / "docker-compose.yml"
        base.write_text(base.read_text().replace("env_file: .env", "env_file: settings.txt"))
        (self.root / "settings.txt").write_text(
            "FIREFLY_DROPBOX_BACKUP_PATH=/legacy/firefly\n"
        )
        for args, destination in (
            (("local",), "/App_acc/firefly"),
            (("prod",), "/Apps/firefly"),
            (("default", "local"), "/App_acc/firefly"),
            (("default", "prod"), "/Apps/firefly"),
        ):
            with self.subTest(args=args):
                result = self.run_start(*args)
                self.assertEqual(result.returncode, 0, result.stderr)
                environment = self.merged_config(resolve_env=True)["services"]["db-backup"][
                    "environment"
                ]
                self.assertEqual(environment["FIREFLY_DROPBOX_BACKUP_PATH"], destination)

    def test_destination_files_cover_registered_databases(self):
        names = {
            line.split("|", 1)[0].upper().replace("-", "_") + "_DROPBOX_BACKUP_PATH"
            for line in (self.root / "backup-databases.conf").read_text().splitlines()
            if line and not line.startswith("#")
        }
        for path in ("path.local", "path.prod"):
            with self.subTest(path=path):
                keys = {
                    line.split("=", 1)[0]
                    for line in (self.root / path).read_text().splitlines()
                    if line and not line.startswith("#")
                }
                self.assertEqual(keys, names)

    def test_invalid_or_missing_destinations_fail_before_compose(self):
        path = self.root / "path.prod"
        original = path.read_text()
        for contents in (
            original.replace("FIREFLY_DROPBOX_BACKUP_PATH=/Apps/firefly", ""),
            original.replace(
                "FIREFLY_DROPBOX_BACKUP_PATH=/Apps/firefly",
                "FIREFLY_DROPBOX_BACKUP_PATH=",
            ),
            original + "\nFIREFLY_DROPBOX_BACKUP_PATH=/duplicate\n",
            original.replace("/Apps/firefly", "/Apps/$OTHER"),
            original + "\nINVALID=path\n",
        ):
            with self.subTest(contents=contents):
                path.write_text(contents)
                result = self.run_start("prod")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("ERROR:", result.stderr)
                self.assertFalse((self.root / "args").exists())
        path.unlink()
        result = self.run_start("prod")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing destination file", result.stderr)
        self.assertFalse((self.root / "args").exists())

    def test_generated_command_validates_and_writes_schedule(self):
        result = self.run_start("prod")
        self.assertEqual(result.returncode, 0, result.stderr)
        service = self.merged_config()["services"]["db-backup"]
        command = service["command"][2]
        crontab = self.root / "crontab"
        command = command.replace("$$", "$").replace("/etc/crontabs/root", str(crontab))
        crond = self.bin / "crond"
        crond.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        crond.chmod(0o755)
        for schedule, expected_status in (
            (service["environment"]["FIREFLY_CRON_SCHEDULE"], 0),
            ("5 3 * *", 1),
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
        for args in (("remote",), ("default",), ("default", "remote"), ("prod", "local")):
            with self.subTest(args=args):
                result = self.run_start(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Usage:", result.stderr)
                self.assertFalse((self.root / "args").exists())


if __name__ == "__main__":
    unittest.main()
