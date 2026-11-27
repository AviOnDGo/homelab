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
        for name in (
            "start-backup.sh", "backup-volumes.conf", "docker-compose.yml",
            "path.local", "path.prod",
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

    def run_start(self, profile, destination=None, **env):
        args = ["bash", str(self.root / "start-backup.sh"), profile]
        if destination is not None:
            args.append(destination)
        return subprocess.run(
            args,
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
            "default", "local", MOCK_VOLUMES="hermes_filedata\nromm_filedata"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        override = (self.root / "override.yml").read_text()
        self.assertIn("hermes_filedata:/backup-sources/hermes:ro", override)
        self.assertIn("romm_filedata:/backup-sources/romm:ro", override)
        self.assertIn("HERMES_CRON_SCHEDULE", override)
        self.assertIn("ROMM_CRON_SCHEDULE", override)
        self.assertIn("HERMES_BACKUP_MODE: archive", override)
        self.assertIn("ROMM_BACKUP_MODE: sync-crypt", override)

    def test_media_backups_run_in_local_and_default_but_not_prod(self):
        names = ("jackett", "radarr", "sonarr", "transmission")
        volumes = "\n".join(f"{name}_filedata" for name in names) + "\nnpm_filedata"
        for profile, destination in (
            ("local", None), ("default", "local"), ("prod", None)
        ):
            with self.subTest(profile=profile):
                result = self.run_start(profile, destination, MOCK_VOLUMES=volumes)
                self.assertEqual(result.returncode, 0, result.stderr)
                override = (self.root / "override.yml").read_text()
                for name in names:
                    mount = f"{name}_filedata:/backup-sources/{name}:ro"
                    job = f"/usr/local/bin/backup-script.sh {name}"
                    if profile == "prod":
                        self.assertNotIn(mount, override)
                        self.assertNotIn(job, override)
                    else:
                        self.assertIn(mount, override)
                        self.assertIn(job, override)

    def test_registered_policies_match_previous_examples(self):
        expected_sync = {
            "immich-library",
            "immich-profile",
            "immich-upload",
            "paperless",
            "romm",
        }
        expected = {
            "hermes": ("14", "35 2 * * *"),
            "n8n": ("30", "25 2 * * *"),
            "omniroute": ("14", "30 2 * * *"),
            "openwebui": ("14", "20 2 * * *"),
            "firefox": ("14", "10 4 * * *"),
            "syncthing": ("7", "15 1 * * *"),
            "romm": ("30", "0 5 * * *"),
            "freshrss": ("7", "0 4 * * *"),
            "paperless": ("0", "15 4 * * *"),
            "radicale": ("7", "0 3 * * *"),
            "immich-library": ("30", "0 3 * * *"),
            "immich-profile": ("30", "15 3 * * *"),
            "immich-upload": ("30", "30 3 * * *"),
            "jackett": ("7", "30 4 * * *"),
            "jellyfin": ("7", "20 1 * * *"),
            "radarr": ("2", "20 4 * * *"),
            "sonarr": ("2", "25 4 * * *"),
            "transmission": ("7", "35 4 * * *"),
            "npm": ("57", "10 2 */7 * *"),
            "pihole": ("61", "0 2 */10 * *"),
            "vaultwarden": ("7", "15 2 * * *"),
        }
        entries = [
            line.split("|")
            for line in (ROOT / "backup-volumes.conf").read_text().splitlines()
            if line and not line.startswith("#")
        ]
        result = self.run_start(
            "default", "prod", MOCK_VOLUMES="\n".join(entry[1] for entry in entries)
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        override = (self.root / "override.yml").read_text()
        self.assertEqual({entry[0] for entry in entries}, set(expected))
        for name, _, _, mode, retention, schedule in entries:
            expected_mode = "sync-crypt" if name in expected_sync else "archive"
            self.assertEqual(mode, expected_mode, name)
            self.assertEqual((retention, schedule), expected[name], name)
            key = name.upper().replace("-", "_")
            self.assertIn(f"{key}_BACKUP_MODE: {expected_mode}", override)
            self.assertIn(f'{key}_RETENTION_DAYS: "{retention}"', override)
            self.assertIn(f'{key}_CRON_SCHEDULE: "{schedule}"', override)
        for example in (".env.example", "path.local", "path.prod"):
            text = (ROOT / example).read_text()
            for suffix in ("_BACKUP_MODE=", "_RETENTION_DAYS=", "_CRON_SCHEDULE="):
                self.assertNotIn(suffix, text)

    def test_invalid_or_missing_registry_policy_stops_deployment(self):
        for entry in (
            "npm|npm_filedata|default,prod||7|0 2 * * *",
            "npm|npm_filedata|default,prod|sync|7|0 2 * * *",
            "npm|npm_filedata|default,prod|archive||0 2 * * *",
            "npm|npm_filedata|default,prod|archive|-1|0 2 * * *",
            "npm|npm_filedata|default,prod|archive|07|0 2 * * *",
            "npm|npm_filedata|default,prod|archive|7|0 2 * *",
            "npm|npm_filedata|default,prod|archive|7|0 2 * * *;echo",
            "npm|npm_filedata|default,prod|archive|7|0 2 * * *|extra",
        ):
            with self.subTest(entry=entry):
                (self.root / "backup-volumes.conf").write_text(
                    f"# Security Services\n{entry}\n"
                )
                result = self.run_start("prod", MOCK_VOLUMES="npm_filedata")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Invalid entry", result.stderr)
                self.assertFalse((self.root / "args").exists())

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
        for profile, destination in (
            ("other", None), ("remote", None), ("default", None),
            ("default", "other"), ("prod", "local"),
        ):
            result = self.run_start(profile, destination, MOCK_VOLUMES="npm_filedata")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Usage:", result.stderr)
        (self.root / "backup-volumes.conf").write_text(
            "# Security Services\nnpm|npm_filedata|prod|archive|7|0 2 * * *\n"
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
    def test_registered_policies_override_legacy_env_file_values(self):
        result = self.run_start("local", MOCK_VOLUMES="romm_filedata")
        self.assertEqual(result.returncode, 0, result.stderr)
        compose_file = self.root / "docker-compose.yml"
        compose_file.write_text(
            compose_file.read_text().replace("- .env", "- fixture-input")
        )
        (self.root / "fixture-input").write_text(
            "ROMM_BACKUP_MODE=archive\n"
            "ROMM_RETENTION_DAYS=0\n"
            "ROMM_CRON_SCHEDULE=0 0 * * *\n"
            "ROMM_SYNC_CRYPT_REMOTE=legacy:wrong\n"
            "DROPBOX_AUTH_TOKEN=fixture-token\n"
        )
        config = subprocess.run(
            [
                shutil.which("docker"),
                "compose",
                "--env-file",
                "/dev/null",
                "--project-directory",
                str(self.root),
                "-f",
                str(compose_file),
                "-f",
                str(self.root / "override.yml"),
                "config",
                "--format",
                "json",
            ],
            env={
                "PATH": os.defpath,
                "HOME": str(self.root),
                "ROMM_CRON_SCHEDULE": "0 1 * * *",
                "ROMM_RETENTION_DAYS": "1",
            },
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(config.returncode, 0, config.stderr)
        values = json.loads(config.stdout)["services"]["filedata-backup"]["environment"]
        self.assertEqual(values["ROMM_BACKUP_MODE"], "sync-crypt")
        self.assertEqual(values["ROMM_RETENTION_DAYS"], "30")
        self.assertEqual(values["ROMM_CRON_SCHEDULE"], "0 5 * * *")
        self.assertEqual(values["ROMM_SYNC_CRYPT_REMOTE"], "filen-crypt:/Romm")
        self.assertEqual(values["DROPBOX_AUTH_TOKEN"], "fixture-token")

    def test_missing_or_invalid_destination_fails_before_compose(self):
        path_file = self.root / "path.prod"
        for contents in (
            "",
            "NPM_DROPBOX_PATH=\n",
            "NPM_DROPBOX_PATH=/one\nNPM_DROPBOX_PATH=/two\n",
            "NPM_DROPBOX_PATH=$INTERPOLATED\n",
            "DROPBOX_AUTH_TOKEN=not-a-destination\n",
        ):
            with self.subTest(contents=contents):
                path_file.write_text(contents)
                result = self.run_start("prod", MOCK_VOLUMES="npm_filedata")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("ERROR:", result.stderr)
                self.assertFalse((self.root / "args").exists())

    def test_missing_path_file_fails_before_compose(self):
        (self.root / "path.local").unlink()
        result = self.run_start("local", MOCK_VOLUMES="npm_filedata")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing destination file", result.stderr)
        self.assertFalse((self.root / "args").exists())

    def test_path_files_match_and_example_contains_no_destinations(self):
        def keys(path):
            return {
                line.split("=", 1)[0]
                for line in path.read_text().splitlines()
                if line and not line.startswith("#")
            }

        local_keys = keys(ROOT / "path.local")
        self.assertEqual(local_keys, keys(ROOT / "path.prod"))
        self.assertTrue(local_keys)
        self.assertTrue(
            all(
                key.endswith(("_DROPBOX_PATH", "_SYNC_CRYPT_REMOTE"))
                for key in local_keys
            )
        )
        self.assertTrue(keys(ROOT / ".env.example").isdisjoint(local_keys))

    @unittest.skipUnless(shutil.which("docker"), "Docker Compose is not installed")
    def test_generated_override_is_valid_compose(self):
        result = self.run_start("prod", MOCK_VOLUMES="npm_filedata")
        self.assertEqual(result.returncode, 0, result.stderr)
        env = {
            "PATH": os.defpath,
            "HOME": str(self.root),
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
            service["environment"]["NPM_CRON_SCHEDULE"], "10 2 */7 * *"
        )
        self.assertEqual(service["environment"]["NPM_RETENTION_DAYS"], "57")
        self.assertEqual(service["environment"]["NPM_BACKUP_MODE"], "archive")
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
            env={**env, **service["environment"]},
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
    @unittest.skipUnless(shutil.which("docker"), "Docker Compose is not installed")
    def test_all_host_profiles_render_with_their_environment_examples(self):
        compose_file = self.root / "docker-compose.yml"
        compose_file.write_text(
            compose_file.read_text().replace("- .env", "- fixture-input")
        )
        (self.root / "fixture-input").write_text("DROPBOX_AUTH_TOKEN=fixture-token\n")
        entries = []
        for line in (ROOT / "backup-volumes.conf").read_text().splitlines():
            if line and not line.startswith("#"):
                name, volume, profiles, mode, retention, schedule = line.split("|")
                entries.append(
                    (name, volume, profiles.split(","), mode, retention, schedule)
                )

        for profile, destination in (
            ("default", "local"), ("default", "prod"), ("local", None), ("prod", None)
        ):
            with self.subTest(profile=profile, destination=destination):
                environment = {
                    "PATH": os.defpath,
                    "HOME": str(self.root),
                }
                selected = [
                    (name, volume, mode, retention, schedule)
                    for name, volume, profiles, mode, retention, schedule in entries
                    if profile in profiles
                ]

                result = self.run_start(
                    profile,
                    destination,
                    MOCK_VOLUMES="\n".join(entry[1] for entry in selected),
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
                        for name, volume, _, _, _ in selected
                    },
                )
                service = model["services"]["filedata-backup"]
                self.assertEqual(service["environment"]["TZ"], "UTC")
                path_profile = destination or profile
                path_lines = (self.root / f"path.{path_profile}").read_text().splitlines()
                paths = dict(
                    line.split("=", 1)
                    for line in path_lines
                    if line and not line.startswith("#")
                )
                self.assertEqual(
                    service["environment"]["NPM_DROPBOX_PATH"],
                    "/App_acc/npm" if path_profile == "local" else "/Apps/npm",
                )
                command = "\n".join(service["command"])
                for name, _, mode, retention, schedule in selected:
                    self.assertIn(f"backup-script.sh {name}", command)
                    mode_key = name.upper().replace("-", "_") + "_BACKUP_MODE"
                    self.assertEqual(service["environment"][mode_key], mode)
                    schedule_key = name.upper().replace("-", "_") + "_CRON_SCHEDULE"
                    self.assertEqual(service["environment"][schedule_key], schedule)
                    retention_key = name.upper().replace("-", "_") + "_RETENTION_DAYS"
                    self.assertEqual(service["environment"][retention_key], retention)
                    destination_key = name.upper().replace("-", "_") + (
                        "_DROPBOX_PATH" if mode == "archive" else "_SYNC_CRYPT_REMOTE"
                    )
                    self.assertTrue(paths[destination_key])
                    self.assertEqual(
                        service["environment"][destination_key], paths[destination_key]
                    )


if __name__ == "__main__":
    unittest.main()
