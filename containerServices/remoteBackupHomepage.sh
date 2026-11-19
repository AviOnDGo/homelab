#!/bin/bash

### Detect operating system
OS="$(uname -s)"
case "${OS}" in
    Linux*)     MACHINE=Linux;;
    Darwin*)    MACHINE=Mac;;
    *)          MACHINE="UNKNOWN:${OS}"
esac

### Load environment variables based on OS
if [ "$MACHINE" = "Mac" ]; then
    # Detect shell and load appropriate profile
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
    
    # Source the profile if it exists
    if [ -f "$SHELL_PROFILE" ]; then
        source "$SHELL_PROFILE"
    fi
else
    # Load environment variables from /etc/environment on Linux
    if [ -f /etc/environment ]; then
        set -a
        source /etc/environment
        set +a
    fi
fi

# Set default values if not set
if [ -z "$HOMEPAGE_TARGET_DIR" ]; then
    export HOMEPAGE_TARGET_DIR="$(eval echo ~$USER)/homepageBackup"
fi

### Remote backup configuration
# List of remote storage providers configured in rclone
remotes=("dropbox")  # Add your configured remotes here: ("dropbox" "googledrive" "onedrive")
remote_path="Apps/homepageBackup"

echo "☁️ Starting remote backup of Homepage files..."
echo "📁 Local backup directory: $HOMEPAGE_TARGET_DIR"

# Check if local backup directory exists
if [ ! -d "$HOMEPAGE_TARGET_DIR" ]; then
    echo "❌ Local backup directory not found: $HOMEPAGE_TARGET_DIR"
    exit 1
fi

# Check if there are any backup files
if [ -z "$(ls -A "$HOMEPAGE_TARGET_DIR" 2>/dev/null)" ]; then
    echo "❌ No backup files found in $HOMEPAGE_TARGET_DIR"
    exit 1
fi

### Upload to each remote
for remote in "${remotes[@]}"; do
    echo "➡️ Uploading to remote: $remote"

    # Check if remote is configured
    if ! rclone listremotes | grep -q "^${remote}:$"; then
        echo "⚠️ Remote '$remote' not configured in rclone. Skipping..."
        continue
    fi

    # Upload files to remote
    echo "📤 Uploading files to $remote:$remote_path..."
    if rclone copy "$HOMEPAGE_TARGET_DIR" "$remote:$remote_path" --progress --update --create-empty-src-dirs; then
        echo "✅ Successfully uploaded to $remote"
    else
        echo "❌ Failed to upload to $remote"
        exit 1
    fi
done

echo "🎉 Remote backup completed successfully!"

# Show summary
echo ""
echo "📊 Remote Backup Summary:"
echo "   - Local directory: $HOMEPAGE_TARGET_DIR"
echo "   - Remotes used: ${remotes[*]}"
echo "   - Remote path: $remote_path"
echo "   - Files uploaded: $(ls -1 "$HOMEPAGE_TARGET_DIR" | wc -l)"
echo "   - Completed: $(date)"