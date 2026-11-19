# Kasm Workspaces — Restore Guide

This guide covers restoring Kasm from a GPG-encrypted filedata backup produced by `backupServices/filedata`.

---

## Prerequisites

- Docker installed and running
- `container_network` Docker network exists (create with `docker network create container_network` if absent)
- `kasm_filedata` Docker volume exists or will be recreated in Step 4
- GPG symmetric key (passphrase) used for encryption — stored in Vaultwarden
- `rclone` configured with the Dropbox remote (if downloading from cloud)

---

## Step 1 — Stop Kasm

```bash
docker compose -f containerServices/kasm/docker-compose.yml down
```

---

## Step 2 — Locate the Backup Archive

List available backups in Dropbox:

```bash
rclone ls dropbox:/Apps/kasm/
```

The archive filename follows the pattern:
```
backup_kasm_YYYYMMDD_HHMMSS.tar.zst.gpg
```

Download the desired archive:

```bash
rclone copy dropbox:/Apps/kasm/backup_kasm_YYYYMMDD_HHMMSS.tar.zst.gpg /tmp/
```

---

## Step 3 — Decrypt the Archive

```bash
gpg --output /tmp/backup_kasm.tar.zst \
    --decrypt /tmp/backup_kasm_YYYYMMDD_HHMMSS.tar.zst.gpg
```

Enter the GPG passphrase when prompted.

---

## Step 4 — Recreate the Volume

If the volume does not exist (fresh host or clean wipe), create it:

```bash
docker volume create kasm_filedata
```

If the volume exists and you want to wipe it before restoring (clean restore):

```bash
docker volume rm kasm_filedata
docker volume create kasm_filedata
```

---

## Step 5 — Restore Data into the Volume

Use a temporary Alpine container to extract the archive into the volume:

```bash
docker run --rm \
  -v kasm_filedata:/opt/kasm \
  -v /tmp:/backup \
  alpine \
  sh -c "cd /opt/kasm && zstd -d /backup/backup_kasm.tar.zst -c | tar -xf - --strip-components=1"
```

> **Note**: The `--strip-components=1` flag removes the leading directory from the archive. Verify the archive structure with `zstd -d /tmp/backup_kasm.tar.zst -c | tar -tf - | head -5` first — adjust `--strip-components` if the archive nests data differently.

---

## Step 6 — Restart Kasm and Verify

Start Kasm:

```bash
docker compose -f containerServices/kasm/docker-compose.yml up -d
```

Watch logs for successful initialisation (allow ~60 seconds on first start):

```bash
docker compose -f containerServices/kasm/docker-compose.yml logs -f kasm
```

Verify via NPM:
- Navigate to `https://kasm.<your-domain>`
- Log in with the admin account
- Confirm previously configured workspaces are present

---

## Cleanup

Remove temporary files after a successful restore:

```bash
rm /tmp/backup_kasm_YYYYMMDD_HHMMSS.tar.zst.gpg /tmp/backup_kasm.tar.zst
```
