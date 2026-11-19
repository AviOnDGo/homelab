# Radicale — Restore Guide

This guide describes how to restore Radicale CalDAV/CardDAV data from a GPG-encrypted filedata backup produced by `backupServices/filedata`.

---

## Prerequisites

- Docker and Docker Compose installed and running.
- GPG passphrase used during backup (stored in `/run/secrets/gpg-passphrase` or Vaultwarden).
- Access to the target backup file (`radicale_<timestamp>.tar.zst.gpg`).
- Network `knowledge_network` created (`docker network create knowledge_network`).

---

## Restore Steps

### 1. Stop Radicale Stack

Navigate to the Radicale service directory and stop the container stack:

```bash
cd knowledgeServices/radicale
docker compose down
```

### 2. Set Passphrase Environment Variable

Export the GPG decryption passphrase into your shell environment:

```bash
read -sp "Enter GPG Passphrase: " PASSPHRASE
export PASSPHRASE
```

### 3. Ensure Target Volume Exists

Check if the `radicale_filedata` external volume exists, and create it if necessary:

```bash
docker volume inspect radicale_filedata >/dev/null 2>&1 || docker volume create radicale_filedata
```

### 4. Restore Filedata Archive into Target Volume

Use a temporary container to decrypt and extract the backup directly into `radicale_filedata`:

```bash
docker run --rm \
  -v radicale_filedata:/var/lib/radicale \
  -v /path/to/backups:/backup \
  alpine:latest sh -c \
  "apk add --no-cache gnupg tar zstd && \
   gpg --decrypt --batch --passphrase '$PASSPHRASE' /backup/radicale_<timestamp>.tar.zst.gpg | tar -I zstd -x -C /var/lib/radicale"
```

### 5. Start Service Stack

Start the Radicale service container:

```bash
docker compose up -d
```

### 6. Cleanup Sensitive Shell State

Clear the passphrase variable from your active terminal session:

```bash
unset PASSPHRASE
```

---

## Verification

Confirm successful restoration:

1. **Container Status**:
   ```bash
   docker compose ps
   ```
2. **Log Inspection**:
   ```bash
   docker compose logs -f radicale
   ```
3. **CalDAV Capability Response**:
   ```bash
   curl -i -X OPTIONS http://localhost:5232/
   ```
   *Expected*: HTTP 200 OK with `DAV: 1, 2, 3, calendar-access, addressbook` headers.

---

## Troubleshooting

- **GPG Decryption Error**: Verify that the `$PASSPHRASE` matches the key used during the backup run.
- **Permission Denied inside Volume**: Ensure `/var/lib/radicale` file permissions inside `radicale_filedata` allow the Radicale user to read/write.
- **Missing Collections**: Verify the extracted files reside in `/var/lib/radicale/collections` or `/var/lib/radicale/users`.

---

## Optional: Dropbox Download

To fetch the latest backup directly from Dropbox using `rclone`:

```bash
rclone copy dropbox:/Apps/radicale/ /path/to/backups/ --include "radicale_*.tar.zst.gpg"
```
