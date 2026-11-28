#!/bin/bash
# setup-backup.sh
# Quick setup script for database backup service

set -e

echo "================================"
echo "Database Backup Service Setup"
echo "================================"
echo ""

# Check if .env.backup exists
if [ ! -f .env.backup ]; then
    echo "❌ Error: .env.backup file not found!"
    echo "Please create .env.backup from .env.backup template first."
    exit 1
fi

# Prompt for configuration
echo "Configure the backup service:"
echo ""

read -p "Enter Dropbox Auth Token (or press Enter to skip): " dropbox_token
if [ -n "$dropbox_token" ]; then
    sed -i "s|your_dropbox_auth_token_here|$dropbox_token|g" .env.backup
    echo "✅ Dropbox token updated"
fi

read -p "Enter Discord Webhook URI (or press Enter to skip): " discord_uri
if [ -n "$discord_uri" ]; then
    sed -i "s|your_discord_webhook_uri_here|$discord_uri|g" .env.backup
    echo "✅ Discord webhook updated"
fi

read -p "Enter GPG Passphrase (or press Enter to skip): " gpg_pass
if [ -n "$gpg_pass" ]; then
    sed -i "s|your_gpg_passphrase_here|$gpg_pass|g" .env.backup
    echo "✅ GPG passphrase updated"
fi

# Create backup directories
echo ""
echo "Creating backup directories..."
mkdir -p ./backups/invidious
mkdir -p ./backups/firefly
chmod 755 ./backups/invidious ./backups/firefly
echo "✅ Backup directories created"

# Create secrets directory
echo ""
echo "Setting up GPG secrets..."
mkdir -p ./secrets
if [ -n "$gpg_pass" ]; then
    echo "$gpg_pass" > ./secrets/gpg-passphrase
    chmod 600 ./secrets/gpg-passphrase
    echo "✅ GPG passphrase saved to ./secrets/gpg-passphrase"
fi

# Verify media_network exists (created by NPM - run securityServices/npm first)
echo ""
echo "Checking media_network..."
if docker network ls | grep -q "media_network"; then
    echo "✅ media_network found"
else
    echo "⚠️  media_network not found. Start NPM first: cd securityServices/npm && docker compose up -d"
    exit 1
fi

# Make script executable
chmod +x db-backup-script.sh

echo ""
echo "================================"
echo "✅ Setup Complete!"
echo "================================"
echo ""
echo "Next steps:"
echo "1. Review and verify .env.backup configuration"
echo "2. Start the backup service:"
echo "   ./start-backup.sh local"
echo "3. Check logs:"
echo "   docker logs -f db-backup"
echo "4. Test manual backup:"
echo "   docker exec db-backup /usr/local/bin/backup-script.sh invidious"
echo ""
echo "For detailed information, see DATABASE_BACKUP_SETUP.md"
echo ""
