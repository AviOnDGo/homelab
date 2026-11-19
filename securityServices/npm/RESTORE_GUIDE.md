# Nginx Proxy Manager Restore Guide

## Overview

This guide provides step-by-step procedures for restoring the Nginx Proxy Manager (npm) service from backups.

## Prerequisites

- Docker and Docker Compose installed
- Access to backup files
- Network configuration knowledge

## Volume Information

**Current Volume Structure:**
- **Volume Name:** `npm_filedata`
- **Mount Points:**
  - `filedata` → `/data` (Main configuration and database)
  - `filedata` → `/etc/letsencrypt` (SSL certificates - same volume, different mount)

## Backup Locations

**Automated Backups (Filedata Backup Service):**
- **Service:** `filedata-backup` (automated daily backups)
- **Location:** `backupServices/filedata/backups/npm/`
- **Format:** Encrypted GPG archives (`.tar.zst.gpg`)
- **Cloud Storage:** Dropbox (path configured in filedata service `.env`)
- **Documentation:** See [backupServices/filedata/SERVICE_DOCUMENTATION.md](../../backupServices/filedata/SERVICE_DOCUMENTATION.md)

**What's Included in Backups:**
- SQLite database (`database.sqlite`)
- Nginx configuration files
- Let's Encrypt certificates and account data
- SSL certificates (archive, live, renewal data)
- Custom SSL certificates
- Access lists and authentication data

## Restoration Procedure

**Step 1:** Set the GPG passphrase
```bash
export PASSPHRASE=<your_gpg_passphrase_here>
```

**Step 2:** Stop the npm service
```bash
cd securityServices/npm
docker compose down
```

**Step 3:** Remove existing volume (optional)
```bash
# Only if starting fresh
docker volume rm npm_filedata
docker volume create npm_filedata
```

**Step 4:** Decrypt and restore in one command
```bash
# Find latest backup or specify filename
# This restores to the volume root, which npm mounts as both /data and /etc/letsencrypt
gpg --batch --yes --passphrase "$PASSPHRASE" -d /path/to/npm_<timestamp>.tar.zst.gpg | zstd -d \
  | docker run --rm -i -v npm_filedata:/restore alpine sh -c "cd /restore && tar -xf -"
```

**Step 5:** Start the service
```bash
cd securityServices/npm
docker compose up -d
```

**Step 6:** Cleanup
```bash
unset PASSPHRASE
```

**Note:** Replace `npm_filedata_*.tar.zst.gpg` with your specific backup filename if needed.

## Verification Steps

After restoration, verify the following:

### 1. Service Health
```bash
cd securityServices/npm
docker compose ps
docker compose logs
```

**Expected:** Container status should be "Up" and logs show no errors

### 2. Database Integrity
```bash
docker exec npm ls -lh /data/database.sqlite
```

**Expected:** database.sqlite file exists and has non-zero size

### 3. SSL Certificates
```bash
docker exec npm ls -la /etc/letsencrypt/live/
```

**Expected:** Certificate directories exist for configured domains

### 4. Web Interface
- Navigate to `http://<server-ip>:9003`
- Login with admin credentials
- Verify proxy hosts are listed

**Expected:** Admin interface loads and shows configured hosts

### 5. Proxy Functionality
- Test accessing a proxied service
- Verify SSL certificates are valid
- Check that redirects work correctly

**Expected:** Services accessible through proxy with valid SSL

### 6. File Counts
```bash
# Check volume root (includes both data and letsencrypt files)
docker run --rm -v npm_filedata:/vol alpine find /vol -type f | wc -l
```

**Expected:** File counts match documented state (77 files as of 2026-02-08)

## Troubleshooting

### Issue: Service Won't Start

**Symptoms:** Container exits immediately or won't create

**Solutions:**
1. Check logs: `docker compose logs`
2. Verify volume exists: `docker volume inspect npm_filedata`
3. Check permissions: Ensure volume data has correct ownership
4. Validate docker-compose.yml syntax

### Issue: Database Corruption

**Symptoms:** Errors about database.sqlite in logs

**Solutions:**
1. Restore from an earlier backup
2. Check database integrity:
   ```bash
   docker run --rm -v npm_filedata:/data alpine \
     sqlite3 /data/data/database.sqlite "PRAGMA integrity_check;"
   ```
3. If corrupted, restore from backup and replay recent changes manually

### Issue: SSL Certificates Not Loading

**Symptoms:** Certificate errors or missing domains

**Solutions:**
1. Verify Let's Encrypt data exists:
   ```bash
   docker exec npm ls -la /etc/letsencrypt/
   ```
2. Check certificate file permissions
3. Regenerate certificates if necessary through the web interface

### Issue: Missing Proxy Hosts

**Symptoms:** Configured hosts don't appear in web interface

**Solutions:**
1. Verify database was restored correctly
2. Check backup file contains all necessary data
3. Review backup date - ensure using correct backup version

## Recovery from Total Failure

If encrypted backups are unavailable:

1. **Check Dropbox:** Download backups from cloud storage if local backups are lost
2. **Reconfigure from scratch:** Use the web interface to recreate proxy hosts
3. **Regenerate SSL certificates:** Let's Encrypt will issue new certificates
4. **Check documentation:** Review `SERVICE_DOCUMENTATION.md` for configuration details

## Backup Best Practices

1. **Regular backups:** Automated daily backups via filedata-backup service
2. **Cloud storage:** Backups automatically synced to Dropbox
3. **Test restores:** Periodically test restoration procedures
4. **Document changes:** Note configuration changes in service documentation
5. **Retention:** Keep multiple backup versions (configured in filedata service)

## Post-Restoration Checklist

- [ ] Service starts without errors
- [ ] Database file present and readable
- [ ] SSL certificates loaded correctly
- [ ] Web interface accessible
- [ ] All proxy hosts listed
- [ ] Test proxy functionality
- [ ] Verify certificate auto-renewal works
- [ ] Check logs for warnings
- [ ] Document restoration date and backup used
- [ ] Update monitoring/alerts if applicable

## Emergency Contacts

For critical issues:
- Check GitHub Copilot documentation
- Review upstream nginx-proxy-manager docs: https://nginxproxymanager.com/
- Check Docker logs and system logs

---

**Last Updated:** 2026-02-08  
**Service Version:** nginx-proxy-manager:latest  
**Volume Structure:** filedata with subpath mounts

## Download from Dropbox

If your backup is stored on Dropbox, see the centralized guide for how to
download it into the VM before performing the restore: [openspec/specs/dropbox-download-guide/spec.md](../../openspec/specs/dropbox-download-guide/spec.md)

Example (update the shared link `dl` parameter to `dl=1`):

```bash
curl -O "https://www.dropbox.com/scl/fi/<id>/<filename>.tar.zst.gpg?dl=1"
```

Remember to delete the shared link or set it to expire after the download.
