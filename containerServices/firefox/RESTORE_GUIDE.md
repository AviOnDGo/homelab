# Firefox — Restore Guide

This guide covers restoring Firefox from a GPG-encrypted filedata backup produced by `backupServices/filedata`.

---

## Prerequisites

- Docker installed and running
- `firefox_filedata` Docker volume exists or will be recreated in Step 4
- GPG symmetric key (passphrase) used for encryption — stored in Vaultwarden
- `rclone` configured with the Dropbox remote (if downloading from cloud)

---

## Step 1 — Stop Firefox

```bash
docker compose -f containerServices/firefox/docker-compose.yml down
```

---

## Step 2 — Locate the Backup Archive

List available backups in Dropbox:

```bash
rclone ls dropbox:/Apps/firefox/
```

The archive filename follows the pattern:
```
backup_firefox_YYYYMMDD_HHMMSS.tar.zst.gpg
```

Download the desired archive:

```bash
rclone copy dropbox:/Apps/firefox/backup_firefox_YYYYMMDD_HHMMSS.tar.zst.gpg /tmp/
```

---

## Step 3 — Decrypt the Archive

```bash
gpg --output /tmp/backup_firefox.tar.zst \
    --decrypt /tmp/backup_firefox_YYYYMMDD_HHMMSS.tar.zst.gpg
```

Enter the GPG passphrase when prompted.

---

## Step 4 — Recreate the Volume

If the volume does not exist (fresh host or clean wipe), create it:

```bash
docker volume create firefox_filedata
```

If the volume exists and you want to wipe it before restoring (clean restore):

```bash
docker volume rm firefox_filedata
docker volume create firefox_filedata
```

---

## Step 5 — Restore Data into the Volume

Use a temporary Alpine container to extract the archive into the volume:

```bash
docker run --rm \
  -v firefox_filedata:/config \
  -v /tmp:/backup \
  alpine \
  sh -c "cd /config && zstd -d /backup/backup_firefox.tar.zst -c | tar -xf - --strip-components=1"
```

> **Note**: The `--strip-components=1` flag removes the leading directory from the archive. Verify the archive structure with `zstd -d /tmp/backup_firefox.tar.zst -c | tar -tf - | head -5` first — adjust `--strip-components` if the archive nests data differently.

---

## Step 6 — Restart Firefox and Verify

Start Firefox:

```bash
docker compose -f containerServices/firefox/docker-compose.yml up -d
```

Watch the logs for successful startup:

```bash
docker compose -f containerServices/firefox/docker-compose.yml logs -f firefox
```

Verify the browser profile is restored:
- Navigate to `https://firefox.<your-domain>` (via NPM) or `http://<host-ip>:3000` (direct noVNC)
- Confirm bookmarks, extensions, and settings are present

---

## Cleanup

Remove temporary files after a successful restore:

```bash
rm /tmp/backup_firefox_YYYYMMDD_HHMMSS.tar.zst.gpg /tmp/backup_firefox.tar.zst
```
