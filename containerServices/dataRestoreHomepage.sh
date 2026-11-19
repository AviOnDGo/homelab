#!/bin/bash

### Detect operating system
OS="$(uname -s)"
case "${OS}" in
    Linux*)     MACHINE=Linux;;
    Darwin*)    MACHINE=Mac;;
    *)          MACHINE="UNKNOWN:${OS}"
esac

echo "Detected OS: $MACHINE"

### Load environment variables based on OS
if [ "$MACHINE" = "Mac" ]; then
    echo "🍎 Configuring for macOS..."
    
    if [ -n "$ZSH_VERSION" ]; then
        SHELL_PROFILE="$HOME/.zshrc"
    elif [ -n "$BASH_VERSION" ]; then
        SHELL_PROFILE="$HOME/.bash_profile"
    else
        if [ -f "$HOME/.zshrc" ]; then
            SHELL_PROFILE="$HOME/.zshrc"
        elif [ -f "$HOME/.bash_profile" ]; then
            SHELL_PROFILE="$HOME/.bash_profile"
        else
            SHELL_PROFILE="$HOME/.profile"
        fi
    fi
    
    if [ -f "$SHELL_PROFILE" ]; then
        source "$SHELL_PROFILE"
    fi
    
    if [ -z "$HOMEPAGE_TARGET_DIR" ]; then
        export HOMEPAGE_TARGET_DIR="$(eval echo ~$USER)/homepageBackup"
    fi
    
else
    echo "🐧 Configuring for Linux..."
    
    if [ -f /etc/environment ]; then
        set -a
        source /etc/environment
        set +a
    fi
    
    if [ -z "$HOMEPAGE_TARGET_DIR" ]; then
        export HOMEPAGE_TARGET_DIR="$(eval echo ~$USER)/homepageBackup"
    fi
fi

### Download from remote storage
remotes=("dropbox")
restoreDirectory="$HOMEPAGE_TARGET_DIR"
remote_path="Apps/homepageBackup"

echo "📦 Starting restore of Homepage backup files from remotes..."
echo "📁 Restore directory: $restoreDirectory"

mkdir -p "$restoreDirectory"

for remote in "${remotes[@]}"; do
    echo "➡️ Checking remote: $remote"

    FILE_LIST=$(rclone lsf "$remote:$remote_path" 2>/dev/null)
    if [ -z "$FILE_LIST" ]; then
        echo "❌ No files found on $remote:$remote_path"
        continue
    fi

    echo "⬇️ Downloading files from $remote..."
    rclone copy "$remote:$remote_path" "$restoreDirectory" --progress --update --create-empty-src-dirs

    echo "✅ Finished downloading from $remote"
done

# Find the latest backup file
echo "🔍 Looking for latest backup file in $HOMEPAGE_TARGET_DIR..."
LATEST_FILE=$(ls -1t "$HOMEPAGE_TARGET_DIR"/homepage_*.tar.gpg 2>/dev/null | head -n 1)

if [ -z "$LATEST_FILE" ]; then
    echo "❌ No backup files found in $HOMEPAGE_TARGET_DIR"
    exit 1
fi

echo "📄 Latest backup file: $LATEST_FILE"

# Check if PASSPHRASE is set
if [ -z "$PASSPHRASE" ]; then
    echo "❌ PASSPHRASE environment variable is not set"
    read -s -p "Enter passphrase for decryption: " PASSPHRASE
    export PASSPHRASE
    echo
fi

# Restore the backup
echo "🔄 Restoring Homepage backup..."
if gpg --batch --yes --passphrase "$PASSPHRASE" -d "$LATEST_FILE" | zstd -d | tar -xf - -C ~; then
    echo "✅ Backup restored successfully!"
else
    echo "❌ Failed to restore backup"
    exit 1
fi

echo "🎉 Data restore completed successfully!"
echo "📁 Homepage configuration restored to: ~/.homepage"
