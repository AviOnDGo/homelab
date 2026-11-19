# Nginx Proxy Manager Service Documentation

## Overview

Nginx Proxy Manager (npm) is a reverse proxy management tool with a web-based interface that provides easy SSL certificate management via Let's Encrypt, custom SSL support, and advanced proxy configuration capabilities.

**Service Name:** npm  
**Container Name:** npm  
**Image:** jc21/nginx-proxy-manager:latest  
**Category:** Core Infrastructure / Network Services

## Configuration

### Ports

| Port | Protocol | Purpose | Access |
|------|----------|---------|--------|
| 80 | TCP | HTTP traffic | 0.0.0.0 (all interfaces) |
| 443 | TCP | HTTPS traffic | 0.0.0.0 (all interfaces) |
| 9003 | TCP | Admin web interface | Internal only |

**Note:** Port 81 is mapped to host port 9003. Access the admin interface via `http://<host>:9003` or through a tunnel.

### Volumes

The service uses a single named volume mounted to both `/data` and `/etc/letsencrypt`:

**Volume:** `npm_filedata`

| Volume | Container Mount | Purpose |
|--------|----------------|---------|  
| `filedata` | `/data` | Application database, configuration files, nginx configs |
| `filedata` | `/etc/letsencrypt` | Let's Encrypt certificates, account data, renewal hooks (same volume) |

**Volume Structure:**
```
npm_filedata/
├── database.sqlite         # Main application database
├── keys.json              # Encryption keys
├── access/                # Access lists
├── accounts/              # Let's Encrypt account data
├── archive/               # Certificate archives
├── credentials/           # DNS provider credentials
├── custom_ssl/            # Custom SSL certificates
├── live/                  # Current certificates (symlinks)
├── logs/                  # Application and access logs
├── nginx/                 # Nginx configuration files
├── renewal/               # Renewal configuration
├── renewal-hooks/         # Pre/post renewal scripts
└── letsencrypt-acme-challenge/  # ACME challenges
```

**Note:** Both `/data` and `/etc/letsencrypt` mount the same volume, so Let's Encrypt files are stored at the root level.

### Networks

The service connects to multiple Docker networks to proxy services across different categories:

| Network | Purpose |
|---------|---------|
| `service` | Core infrastructure services |
| `media_network` | Media services (Jellyfin, Sonarr, Radarr, etc.) |
| `ai_network` | AI services (Ollama, WebUI) |
| `finance_network` | Financial services (Firefly III) |

**Network Mode:** Bridge (default)  
**External Networks:** All networks are externally created

### Environment Variables

The service uses minimal environment configuration. Most settings are managed through the web interface and stored in the SQLite database.

**Default Admin Credentials:**  
- Email: `admin@example.com`  
- Password: `changeme` (must be changed on first login)

## Architecture

### Reverse Proxy Design

```
Internet
    ↓
[ Nginx Proxy Manager ]
    ↓
    ├─→ [media_network] → Jellyfin, Sonarr, etc.
    ├─→ [ai_network] → Ollama, WebUI
    ├─→ [finance_network] → Firefly III
    └─→ [service] → Homepage
```

**Traffic Flow:**
1. External request arrives on port 80 or 443
2. Nginx Proxy Manager matches the request to a configured proxy host
3. Request is forwarded to the appropriate backend service via Docker networks
4. Response is returned through the proxy to the client

### SSL Termination

**SSL/TLS Handling:**
- **Termination Point:** All SSL/TLS connections terminate at nginx-proxy-manager
- **Backend Communication:** Traffic to backend services is unencrypted (over internal Docker networks)
- **Certificate Management:** Automated via Let's Encrypt ACME protocol
- **Renewal:** Automatic certificate renewal 30 days before expiry
- **Custom Certificates:** Supported for non-public domains

**ACME Challenge Types:**
- HTTP-01: Default method for domain validation
- DNS-01: Supported with provider plugins for wildcard certificates

### Database

**Type:** SQLite  
**Location:** `/data/database.sqlite` (in container)  
**Size:** ~135 KB (typical)  
**Backup:** Included in volume backups

**Schema:** Managed by application migrations  
**Direct Access:** Not recommended - use web interface

## Operation

### Starting the Service

```bash
cd /path/to/homelab/securityServices/npm
docker compose up -d
```

### Stopping the Service

```bash
cd /path/to/homelab/securityServices/npm
docker compose down
```

### Restarting the Service

```bash
cd /path/to/homelab/securityServices/npm
docker compose restart
```

### Viewing Logs

```bash
# Real-time logs
docker compose logs -f

# Last 100 lines
docker compose logs --tail=100

# Specific time range
docker compose logs --since="2026-02-08T10:00:00"
```

### Accessing the Web Interface

1. Open browser to `http://<server-ip>:9003`
2. Login with admin credentials
3. Navigate to Dashboard, Hosts, or SSL Certificates sections

### Adding a Proxy Host

1. Navigate to "Hosts" → "Proxy Hosts"
2. Click "Add Proxy Host"
3. Fill in details:
   - **Domain Names:** e.g., `service.example.com`
   - **Scheme:** http or https
   - **Forward Hostname/IP:** Docker service name (e.g., `jellyfin`)
   - **Forward Port:** Service port (e.g., `8096`)
4. Configure SSL tab if needed
5. Save

### Requesting SSL Certificates

1. Edit a proxy host or redirection host
2. Go to "SSL" tab
3. Select "Request a new SSL Certificate"
4. Enter email for Let's Encrypt notifications
5. Enable "Force SSL" and "HTTP/2 Support" as needed
6. Save

**Requirements:**
- Domain must resolve to this server
- Port 80 must be accessible for HTTP-01 challenges
- Or configure DNS provider for DNS-01 challenges

## Troubleshooting

### Common Issues

#### Issue: Can't Access Web Interface on Port 9003

**Symptoms:** Connection refused or timeout when accessing port 9003

**Diagnosis:**
```bash
# Check if container is running
docker compose ps

# Check if port is listening
docker exec npm netstat -tlnp | grep 3000
```

**Solutions:**
- Verify container is running: `docker compose up -d`
- Check firewall rules allow port 9003
- If behind another proxy, ensure traffic is forwarded correctly

#### Issue: SSL Certificate Errors

**Symptoms:** Browser shows certificate warning or "not secure"

**Diagnosis:**
```bash
# Check certificate files exist
docker exec npm ls -la /etc/letsencrypt/live/

# Check renewal configuration
docker exec npm cat /etc/letsencrypt/renewal/*.conf
```

**Solutions:**
- Verify domain DNS points to correct IP
- Check Let's Encrypt rate limits
- Review ACME challenge logs in application logs
- Ensure port 80 is accessible for HTTP-01 validation
- Try manual certificate request through web interface

#### Issue: Proxy Host Not Working

**Symptoms:** 502 Bad Gateway or connection errors

**Diagnosis:**
```bash
# Check backend service is running
docker ps | grep <service-name>

# Test direct connection to backend
docker exec npm wget -O- http://<service>:<port>

# Check nginx error logs
docker exec npm cat /data/logs/error.log
```

**Solutions:**
- Verify backend service is running and healthy
- Check Docker network connectivity: `docker network inspect <network-name>`
- Ensure forward hostname matches service name or IP
- Verify forward port is correct
- Check nginx configuration: `docker exec npm nginx -t`

#### Issue: Database Locked Errors

**Symptoms:** "database is locked" errors in logs

**Diagnosis:**
```bash
# Check for multiple processes accessing database
docker exec npm ps aux

# Check database file permissions
docker exec npm ls -la /data/database.sqlite
```

**Solutions:**
- Restart the service: `docker compose restart`
- Check for file system issues on the host
- Verify volume is not corrupted
- Restore from backup if necessary

#### Issue: High Memory Usage

**Symptoms:** Container using excessive memory

**Diagnosis:**
```bash
# Check container resource usage
docker stats npm

# Check number of proxy hosts
docker exec npm sqlite3 /data/database.sqlite "SELECT COUNT(*) FROM proxy_host;"
```

**Solutions:**
- Normal for many proxy hosts (Node.js backend)
- Consider resource limits in docker-compose.yml if needed
- Review logs for memory leaks (unusual spikes)
- Restart service to clear memory: `docker compose restart`

### Log Locations

| Log Type | Location (in container) | Purpose |
|----------|-------------------------|---------|
| Application | `/data/logs/*.log` | Application-level events |
| Access | `/data/logs/*_access.log` | HTTP access logs per proxy host |
| Error | `/data/logs/error.log` | Nginx error logs |
| Docker | `docker compose logs` | Container stdout/stderr |

### Debug Mode

To enable verbose logging:

1. Access container shell: `docker exec -it npm /bin/sh`
2. Set environment variable: `export NODE_ENV=development`
3. Restart application (exit shell, restart container)

## Security

### Access Control

**Authentication:**
- Web interface requires username/password
- Default credentials should be changed immediately
- Users can be managed through "Users" section

**Access Lists:**
- IP-based whitelisting/blacklisting
- HTTP basic authentication
- Custom authorization schemes

**Best Practices:**
- Change default admin password on first login
- Create separate users for different administrators
- Use strong passwords (minimum 12 characters)
- Enable 2FA if extension available
- Restrict port 9003 access to internal networks only

### SSL/TLS Configuration

**Supported Protocols:**
- TLS 1.2 (minimum recommended)
- TLS 1.3 (preferred)

**Cipher Suites:**
- Managed by nginx-proxy-manager
- Default configuration is secure and modern

**HSTS (HTTP Strict Transport Security):**
- Can be enabled per proxy host
- Recommended for production services
- Set appropriate max-age value

**Certificate Management:**
- Let's Encrypt certificates renewed automatically
- Custom certificates can be uploaded
- Certificates stored in `/etc/letsencrypt/`
- Private keys encrypted at rest

### Network Security

**Isolation:**
- Service connects to multiple networks by design
- Backend services not directly exposed to internet
- All external traffic filtered through proxy

**Recommendations:**
- Use Docker network isolation for sensitive services
- Implement access lists for admin interfaces
- Keep nginx-proxy-manager image updated
- Monitor access logs for suspicious activity
- Use fail2ban or similar for brute-force protection

### Data Protection

**Sensitive Data:**
- Passwords hashed in database
- SSL private keys encrypted
- API tokens stored securely

**Backup Security:**
- Backup files contain sensitive data
- Store backups in secure locations
- Encrypt backups at rest and in transit
- Restrict backup file permissions: `chmod 600 backups/*.tar.zst`

### Updates and Patching

**Update Strategy:**
- Pull latest image regularly: `docker compose pull`
- Review changelog before updating
- Test in non-production first if possible
- Backup before major version updates

**Security Notifications:**
- Monitor nginx-proxy-manager GitHub releases
- Subscribe to security mailing lists
- Check Docker Hub for image updates

## Performance

### Resource Usage

**Typical Requirements:**
- CPU: < 5% idle, spikes during SSL negotiation
- Memory: 100-300 MB depending on proxy hosts
- Disk I/O: Minimal except during log writes

### Optimization Tips

1. **Log Rotation:** Configured by default, runs daily
2. **Keep Databases Small:** Remove unused proxy hosts and certificates
3. **Use HTTP/2:** Enable for better performance with modern clients
4. **Limit Active Connections:** Configure nginx worker connections if needed
5. **Monitor Resource Usage:** Use `docker stats npm` to track

### Scalability

**Limitations:**
- Single container instance (no built-in clustering)
- Suitable for small to medium deployments (< 100 proxy hosts)
- Database performance depends on SQLite limits

**High Availability:**
- Not supported out of the box
- Consider nginx + external certificate manager for HA requirements
- Database replication not available with SQLite

## Monitoring

### Health Checks

**Container Health:**
```bash
# Check container status
docker compose ps

# Check if backend is responding
curl -f http://localhost:9003/ || echo "Health check failed"
```

**Certificate Expiry:**
```bash
# List certificate expiry dates
docker exec npm find /etc/letsencrypt/live -name cert.pem -exec openssl x509 -in {} -noout -dates \;
```

### Metrics

**Key Metrics to Monitor:**
- Container uptime and restarts
- Certificate expiry dates
- Proxy host response times
- Error rates in logs
- Database size growth
- Disk usage of volume

### Alerts

**Recommended Alerts:**
- Container down or unhealthy
- Certificates expiring within 15 days
- High error rates in access logs
- Disk space low on volume
- Unusual traffic patterns

## Integration

### Docker Compose Integration

The service is part of the homelab's modular docker-compose structure:

```yaml
# Located in: securityServices/npm/docker-compose.yml
services:
  npm:
    image: jc21/nginx-proxy-manager:latest
    container_name: npm
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - filedata:/data
      - filedata:/etc/letsencrypt
    networks:
      - service
      - media_network
      - ai_network
      - finance_network

volumes:
  filedata:

networks:
  service:
    external: true
  media_network:
    external: true
  ai_network:
    external: true
  finance_network:
    external: true
```

### Backup Integration

See `RESTORE_GUIDE.md` for comprehensive backup and restoration procedures.

**Backup Schedule:**
- Manual backups before configuration changes
- Automated backups recommended daily
- Retention: Minimum 7 days

## Changelog

| Date | Change | Version |
|------|--------|---------|
| 2026-02-08 | Standardized service naming and volume structure | 1.0.0 |
| 2026-02-08 | Created SERVICE_DOCUMENTATION.md | 1.0.0 |

## References

- **Official Documentation:** https://nginxproxymanager.com/
- **GitHub Repository:** https://github.com/NginxProxyManager/nginx-proxy-manager
- **Docker Hub:** https://hub.docker.com/r/jc21/nginx-proxy-manager
- **Let's Encrypt:** https://letsencrypt.org/docs/

---

**Last Updated:** 2026-02-08  
**Maintained By:** Homelab Infrastructure Team  
**Service Version:** nginx-proxy-manager:latest
