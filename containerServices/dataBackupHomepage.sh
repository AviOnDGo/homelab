#!/bin/bash

### Detect operating system
OS="$(uname -s)"
case "${OS}" in
    Linux*)     MACHINE=Linux;;
    Darwin*)    MACHINE=Mac;;
    *)          MACHINE="UNKNOWN:${OS}"
esac

echo "Detected OS: $MACHINE"

### Enhanced container runtime detection for cron execution
detect_container_runtime_with_path() {
    local runtime=""
    local runtime_path=""
    
    # Try to find Docker first
    for docker_path in /usr/bin/docker /usr/local/bin/docker /opt/homebrew/bin/docker $(which docker 2>/dev/null); do
        if [ -x "$docker_path" ] && $docker_path info &> /dev/null 2>&1; then
            runtime="docker"
            runtime_path="$docker_path"
            break
        fi
    done
    
    # Try to find Podman if Docker not found
    if [ -z "$runtime" ]; then
        for podman_path in /usr/bin/podman /usr/local/bin/podman /opt/homebrew/bin/podman $(which podman 2>/dev/null); do
            if [ -x "$podman_path" ]; then
                runtime="podman"
                runtime_path="$podman_path"
                break
            fi
        done
    fi
    
    if [ -z "$runtime" ]; then
        echo "❌ No container runtime found in common paths"
        echo "Searched paths: /usr/bin, /usr/local/bin, /opt/homebrew/bin"
        exit 1
    fi
    
    echo "$runtime:$runtime_path"
}

# Get runtime info
RUNTIME_INFO=$(detect_container_runtime_with_path)
CONTAINER_RUNTIME=$(echo "$RUNTIME_INFO" | cut -d: -f1)
CONTAINER_RUNTIME_PATH=$(echo "$RUNTIME_INFO" | cut -d: -f2)

echo "Using container runtime: $CONTAINER_RUNTIME at $CONTAINER_RUNTIME_PATH"

### Load environment variables based on OS
if [ "$MACHINE" = "Mac" ]; then
    echo "🍎 Configuring for macOS..."
    
    # Detect shell and load appropriate profile
    if [ -n "$ZSH_VERSION" ]; then
        SHELL_PROFILE="$HOME/.zshrc"
    elif [ -n "$BASH_VERSION" ]; then
        SHELL_PROFILE="$HOME/.bash_profile"
    else
        # Try common profile files
        if [ -f "$HOME/.zshrc" ]; then
            SHELL_PROFILE="$HOME/.zshrc"
        elif [ -f "$HOME/.bash_profile" ]; then
            SHELL_PROFILE="$HOME/.bash_profile"
        else
            SHELL_PROFILE="$HOME/.profile"
        fi
    fi
    
    echo "Loading environment from: $SHELL_PROFILE"
    
    # Source the profile if it exists
    if [ -f "$SHELL_PROFILE" ]; then
        source "$SHELL_PROFILE"
    fi
    
    # Set default values if not set
    if [ -z "$HOMEPAGE_TARGET_DIR" ]; then
        export HOMEPAGE_TARGET_DIR="$(eval echo ~$USER)/homepageBackup"
    fi
    
    if [ -z "$PASSPHRASE" ]; then
        echo "⚠️ PASSPHRASE not set. Please set it manually or run configureDuplicityRclone.sh first."
        read -s -p "Enter passphrase manually (hidden input): " PASSPHRASE
        export PASSPHRASE
        echo
    fi
    
else
    echo "🐧 Configuring for Linux..."
    
    # Load environment variables from /etc/environment on Linux
    if [ -f /etc/environment ]; then
        set -a  # automatically export all variables
        source /etc/environment
        set +a  # turn off automatic export
    fi
    
    # Set default values if not set
    if [ -z "$HOMEPAGE_TARGET_DIR" ]; then
        export HOMEPAGE_TARGET_DIR="$(eval echo ~$USER)/homepageBackup"
    fi
fi

### Create backup directory if it doesn't exist
mkdir -p "$HOMEPAGE_TARGET_DIR"

### Perform backup
echo "💾 Starting Homepage backup..."

# Generate backup filename with timestamp
BACKUP_FILENAME="homepage_$(date +%F_%H-%M-%S).tar.gpg"
BACKUP_PATH="$HOMEPAGE_TARGET_DIR/$BACKUP_FILENAME"

echo "📄 Backup file: $BACKUP_PATH"

# Check if PASSPHRASE is set
if [ -z "$PASSPHRASE" ]; then
    echo "❌ PASSPHRASE environment variable is not set"
    read -s -p "Enter passphrase for encryption: " PASSPHRASE
    export PASSPHRASE
    echo
fi

# Create backup of Homepage config directory with encryption
echo "🔄 Creating encrypted Homepage backup..."
if tar -czf - -C ~ .homepage | gpg --symmetric --cipher-algo AES256 --batch --yes --passphrase "$PASSPHRASE" -o "$BACKUP_PATH"; then
    echo "✅ Homepage backup created successfully!"
    echo "📁 Backup saved to: $BACKUP_PATH"
else
    echo "❌ Failed to create Homepage backup"
    exit 1
fi

### Upload to remote storage
echo "☁️ Uploading backup to remote storage..."
if [ -f "./remoteBackupHomepage.sh" ]; then
    if bash ./remoteBackupHomepage.sh; then
        echo "✅ Backup uploaded to remote storage successfully!"
    else
        echo "⚠️ Failed to upload backup to remote storage, but local backup was created"
        exit 1
    fi
elif [ -f "$HOME/remoteBackupHomepage.sh" ]; then
    if bash "$HOME/remoteBackupHomepage.sh"; then
        echo "✅ Backup uploaded to remote storage successfully!"
    else
        echo "⚠️ Failed to upload backup to remote storage, but local backup was created"
        exit 1
    fi
else
    echo "⚠️ remoteBackupHomepage.sh not found. Skipping remote upload."
    echo "💡 Local backup created successfully at: $BACKUP_PATH"
fi

echo "🎉 Backup process completed successfully!"

# Show backup info
echo ""
echo "📊 Backup Summary:"
echo "   - Container Runtime: $CONTAINER_RUNTIME"
echo "   - Operating System: $MACHINE"
echo "   - Backup File: $BACKUP_PATH"
echo "   - File Size: $(du -h "$BACKUP_PATH" | cut -f1)"
echo "   - Created: $(date)"