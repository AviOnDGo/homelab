import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class StartBackupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ("start-backup.sh", "backup-volumes.conf", "docker-compose.yml"):
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
    if os.environ.get("MOCK_DOCKER_FAIL"):
        print("daemon unavailable", file=sys.stderr)
        sys.exit(1)
    print(os.environ.get("MOCK_VOLUMES", ""))
elif sys.argv[1] == "compose":
    args = sys.argv[1:]
    override = args[args.index("-f", args.index("-f") + 1) + 1]
    shutil.copyfile(override, os.environ["MOCK_OVERRIDE"])
    open(os.environ["MOCK_ARGS"], "w").write("\\n".join(args))
    sys.exit(int(os.environ.get("MOCK_COMPOSE_EXIT", "0")))
else:
    sys.exit(2)
"""
        )
        docker.chmod(0o755)
        self.env = {
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "HOME": str(self.root),
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

    def test_selects_existing_volumes_and_warns_for_missing(self):
        result = self.run_start(
            "prod", MOCK_VOLUMES="freshrss_filedata\nnpm_filedata\nromm_filedata"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("pihole_filedata", result.stderr)
        self.assertIn("vaultwarden_filedata", result.stderr)
        override = (self.root / "override.yml").read_text()
        self.assertIn("freshrss_filedata:/backup-sources/freshrss:ro", override)
        self.assertIn("npm_filedata:/backup-sources/npm:ro", override)
        self.assertNotIn("romm_filedata", override)
        self.assertNotIn("PIHOLE_CRON_SCHEDULE", override)
        args = (self.root / "args").read_text()
        self.assertIn("--force-recreate", args)
        self.assertIn("--wait", args)

    def test_refuses_missing_volumes_or_docker_failure(self):
        for env in ({}, {"MOCK_DOCKER_FAIL": "1"}):
            with self.subTest(env=env):
                result = self.run_start("prod", **env)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("ERROR:", result.stderr)
                self.assertFalse((self.root / "args").exists())

    def test_default_selects_local_only_entries_when_present(self):
        result = self.run_start(
            "default", MOCK_VOLUMES="hermes_filedata\nromm_filedata"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        override = (self.root / "override.yml").read_text()
        self.assertIn("hermes_filedata:/backup-sources/hermes:ro", override)
        self.assertIn("romm_filedata:/backup-sources/romm:ro", override)
        self.assertIn("HERMES_CRON_SCHEDULE", override)
        self.assertIn("ROMM_CRON_SCHEDULE", override)

    def test_prod_selects_the_same_volumes_as_the_prod_compose(self):
        volumes = (
            "freshrss_filedata\nnpm_filedata\npihole_filedata\n"
            "vaultwarden_filedata\nhermes_filedata"
        )
        result = self.run_start("prod", MOCK_VOLUMES=volumes)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        override = (self.root / "override.yml").read_text()
        for name in ("freshrss", "npm", "pihole", "vaultwarden"):
            self.assertIn(f"{name}_filedata:/backup-sources/{name}:ro", override)
        self.assertNotIn("hermes_filedata", override)

    def test_rejects_bad_profile_and_invalid_configuration(self):
        for profile in ("other", "remote"):
            result = self.run_start(profile, MOCK_VOLUMES="npm_filedata")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Usage:", result.stderr)
        (self.root / "backup-volumes.conf").write_text(
            "# Security Services\nnpm|npm_filedata|prod\n"
        )
        result = self.run_start("prod", MOCK_VOLUMES="npm_filedata")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must include the default profile", result.stderr)
        self.assertFalse((self.root / "args").exists())

    def test_compose_failure_is_propagated(self):
        result = self.run_start(
            "prod", MOCK_VOLUMES="npm_filedata", MOCK_COMPOSE_EXIT="9"
        )
        self.assertEqual(result.returncode, 9)

    @unittest.skipUnless(shutil.which("docker"), "Docker Compose is not installed")
    def test_generated_override_is_valid_compose(self):
        result = self.run_start("prod", MOCK_VOLUMES="npm_filedata")
        self.assertEqual(result.returncode, 0, result.stderr)
        env = {
            "PATH": os.defpath,
            "HOME": str(self.root),
            "NPM_CRON_SCHEDULE": "10 2 */7 * *",
        }
        config = subprocess.run(
            [
                shutil.which("docker"),
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
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(config.returncode, 0, config.stderr)
        compose = json.loads(config.stdout)
        service = compose["services"]["filedata-backup"]
        self.assertEqual(
            service["environment"]["NPM_CRON_SCHEDULE"], env["NPM_CRON_SCHEDULE"]
        )
        # Compose's canonical output escapes literal dollars for another parse.
        command = service["command"][2].replace("$$", "$")
        self.assertIn("set -- ${NPM_CRON_SCHEDULE}", command)
        self.assertIn('pidof crond', service["healthcheck"]["test"][1])
        self.assertEqual(
            {mount["target"] for mount in service["volumes"]},
            {"/run/secrets", "/backup-sources/npm"},
        )
        crontab = self.root / "crontab"
        command = command.replace("/etc/crontabs/root", str(crontab))
        command = command.replace("/usr/local/bin/configure-rclone.sh", "true")
        command = command.replace("touch /var/log/cron.log", ":")
        command = command.replace("crond -L /var/log/cron.log", ":")
        command = command.replace("tail -f /var/log/cron.log", ":")
        run = subprocess.run(
            ["/bin/sh", "-ec", command],
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn(
            "10 2 */7 * * /bin/bash /usr/local/bin/backup-script.sh npm",
            crontab.read_text(),
        )
        run = subprocess.run(
            ["/bin/sh", "-ec", command],
            env={**env, "NPM_CRON_SCHEDULE": "10 2"},
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertNotEqual(run.returncode, 0)
        self.assertIn("must have five cron fields", run.stderr)
        no_schedule = subprocess.run(
            config.args,
            env={"PATH": os.defpath, "HOME": str(self.root)},
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertNotEqual(no_schedule.returncode, 0)
        self.assertIn("NPM_CRON_SCHEDULE is required", no_schedule.stderr)

    @unittest.skipUnless(shutil.which("docker"), "Docker Compose is not installed")
    def test_all_host_profiles_render_with_their_environment_examples(self):
        entries = []
        for line in (ROOT / "backup-volumes.conf").read_text().splitlines():
            if line and not line.startswith("#"):
                name, volume, profiles = line.split("|")
                entries.append((name, volume, profiles.split(",")))

        for profile in ("default", "local", "prod"):
            with self.subTest(profile=profile):
                environment_file = ROOT / (
                    "env.local.example" if profile == "local" else "env.prod.example"
                )
                environment = {
                    "PATH": os.defpath,
                    "HOME": str(self.root),
                }
                for line in environment_file.read_text().splitlines():
                    if line and not line.startswith("#") and "=" in line:
                        key, value = line.split("=", 1)
                        environment[key] = value
                selected = [
                    (name, volume)
                    for name, volume, profiles in entries
                    if profile in profiles
                ]
                missing_schedules = [
                    name.upper().replace("-", "_") + "_CRON_SCHEDULE"
                    for name, _ in selected
                    if not environment.get(
                        name.upper().replace("-", "_") + "_CRON_SCHEDULE"
                    )
                ]
                self.assertEqual(missing_schedules, [])

                result = self.run_start(
                    profile,
                    MOCK_VOLUMES="\n".join(volume for _, volume in selected),
                    **{
                        key: value
                        for key, value in environment.items()
                        if key.endswith("_CRON_SCHEDULE")
                    },
                )
                self.assertEqual(result.returncode, 0, result.stderr)

                compose = subprocess.run(
                    [
                        shutil.which("docker"),
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
                    env=environment,
                    text=True,
                    capture_output=True,
                    check=False,
                )
                self.assertEqual(compose.returncode, 0, compose.stderr)
                model = json.loads(compose.stdout)
                mounts = {
                    mount["source"]: mount["target"]
                    for mount in model["services"]["filedata-backup"]["volumes"]
                    if mount["target"].startswith("/backup-sources/")
                }
                self.assertEqual(
                    mounts,
                    {
                        volume: f"/backup-sources/{name}"
                        for name, volume in selected
                    },
                )
                service = model["services"]["filedata-backup"]
                command = "\n".join(service["command"])
                for name, _ in selected:
                    self.assertIn(f"backup-script.sh {name}", command)
                    schedule_key = name.upper().replace("-", "_") + "_CRON_SCHEDULE"
                    self.assertEqual(
                        service["environment"][schedule_key],
                        environment[schedule_key],
                    )


if __name__ == "__main__":
    unittest.main()
