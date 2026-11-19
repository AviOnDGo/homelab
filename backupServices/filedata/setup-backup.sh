#!/bin/bash

set -e

# Filesystem Backup Service Setup Script
# Interactive setup for volume backup configuration

echo "=================================================="
echo "Filesystem Backup Service - Setup"
echo "=================================================="
echo ""

# Check if .env already exists
if [ -f ".env" ]; then
    echo "⚠️  .env already exists!"
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Setup cancelled."
        exit 0
    fi
fi

# Copy template
echo "Creating .env from template..."
cp .env.backup .env

# ============================================
# Dropbox Configuration
# ============================================
echo ""
echo "============================================"
echo "Dropbox Configuration"
echo "============================================"
echo "To get your Dropbox tokens:"
echo "1. Go to https://www.dropbox.com/developers/apps"
echo "2. Create an app with 'Full Dropbox' access"
echo "3. Generate an access token"
echo ""

read -p "Enter Dropbox Access Token: " dropbox_token
read -p "Enter Dropbox Refresh Token: " dropbox_refresh

sed -i "s|DROPBOX_AUTH_TOKEN=.*|DROPBOX_AUTH_TOKEN=${dropbox_token}|" .env
sed -i "s|DROPBOX_REFRESH_TOKEN=.*|DROPBOX_REFRESH_TOKEN=${dropbox_refresh}|" .env

# ============================================
# Discord Webhook (Optional)
# ============================================
echo ""
echo "============================================"
echo "Discord Notifications (Optional)"
echo "============================================"
read -p "Enter Discord Webhook URI (or press Enter to skip): " discord_webhook

if [ -n "$discord_webhook" ]; then
    sed -i "s|DISCORD_WEBHOOK_URI=.*|DISCORD_WEBHOOK_URI=${discord_webhook}|" .env
    echo "✓ Discord notifications enabled"
else
    echo "✓ Discord notifications disabled"
fi

# ============================================
# GPG Passphrase
# ============================================
echo ""
echo "============================================"
echo "GPG Encryption Passphrase"
echo "============================================"
echo "This passphrase will be used to encrypt your backups."
echo "⚠️  IMPORTANT: Keep this safe! You'll need it to restore."
echo ""

read -p "Enter GPG passphrase: " gpg_pass1
echo ""
read -p "Confirm GPG passphrase: " gpg_pass2
echo ""

if [ "$gpg_pass1" != "$gpg_pass2" ]; then
    echo "❌ Passphrases don't match!"
    exit 1
fi

# Create secrets directory and file
mkdir -p ./secrets
echo "$gpg_pass1" > ./secrets/gpg-passphrase
chmod 600 ./secrets/gpg-passphrase
echo "✓ GPG passphrase saved to ./secrets/gpg-passphrase"

# ============================================
# Volume Configuration
# ============================================
echo ""
echo "============================================"
echo "Volume Configuration"
echo "============================================"
echo "Configure which Docker volumes to backup."
echo ""

# Pi-hole (default)
read -p "Backup Pi-hole volume? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    read -p "Pi-hole Dropbox path [/pihole_backup_test]: " pihole_path
    pihole_path=${pihole_path:-/pihole_backup_test}
    
    read -p "Pi-hole retention days [7]: " pihole_retention
    pihole_retention=${pihole_retention:-7}
    
    sed -i "s|PIHOLE_DROPBOX_PATH=.*|PIHOLE_DROPBOX_PATH=${pihole_path}|" .env
    sed -i "s|PIHOLE_RETENTION_DAYS=.*|PIHOLE_RETENTION_DAYS=${pihole_retention}|" .env
    
    mkdir -p ./backups/pihole
    echo "✓ Pi-hole backup configured"
fi

# Additional volumes
echo ""
read -p "Add more volumes to backup? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "To add more volumes:"
    echo "1. Edit .env"
    echo "2. Add {VOLUME_NAME}_DROPBOX_PATH and {VOLUME_NAME}_RETENTION_DAYS"
    echo "3. Edit docker-compose.yml to mount the volume at /backup-sources/{name}:ro"
    echo "4. Update cron command to include the new volume"
    echo ""
    echo "See IMPLEMENTATION_DETAILS.md for full instructions."
fi

# ============================================
# Cron Schedule
# ============================================
echo ""
echo "============================================"
echo "Backup Schedule"
echo "============================================"
read -p "Cron schedule [0 2 * * *] (2 AM daily): " cron_schedule
cron_schedule=${cron_schedule:-0 2 * * *}

sed -i "s|CRON_SCHEDULE=.*|CRON_SCHEDULE=${cron_schedule}|" .env
echo "✓ Backup schedule: ${cron_schedule}"

# ============================================
# Timezone
# ============================================
echo ""
read -p "Timezone [UTC]: " timezone
timezone=${timezone:-UTC}

sed -i "s|TZ=.*|TZ=${timezone}|" .env
echo "✓ Timezone: ${timezone}"

# ============================================
# Make scripts executable
# ============================================
echo ""
echo "Making scripts executable..."
chmod +x filedata-backup-script.sh
chmod +x filesystem-restore-script.sh 2>/dev/null || true

# ============================================
# Create GPG secrets volume
# ============================================
echo ""
echo "Creating GPG secrets volume..."
docker volume create gpg-secrets 2>/dev/null || echo "Volume already exists"

# Copy secrets to volume using temporary container
docker run --rm \
    -v "$(pwd)/secrets:/source:ro" \
    -v gpg-secrets:/secrets \
    alpine sh -c "cp /source/gpg-passphrase /secrets/ && chmod 600 /secrets/gpg-passphrase"

echo "✓ Secrets configured"

# ============================================
# Summary
# ============================================
echo ""
echo "=================================================="
echo "✅ Setup Complete!"
echo "=================================================="
echo ""
echo "Next steps:"
echo "1. Review configuration: cat .env"
echo "2. Start backup service: docker compose up -d"
echo "3. Test backup: docker exec filedata-backup /bin/bash /usr/local/bin/backup-script.sh pihole"
echo "4. View logs: docker logs -f filedata-backup"
echo ""
echo "For more information, see:"
echo "- QUICKSTART_GUIDE.md - Quick reference"
echo "- IMPLEMENTATION_DETAILS.md - Technical documentation"
echo ""
