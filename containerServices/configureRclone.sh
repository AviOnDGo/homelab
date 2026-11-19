#!/bin/bash

### Detect operating system
OS="$(uname -s)"
case "${OS}" in
    Linux*)     MACHINE=Linux;;
    Darwin*)    MACHINE=Mac;;
    *)          MACHINE="UNKNOWN:${OS}"
esac

echo "Detected OS: $MACHINE"

### Detect container runtime
CONTAINER_RUNTIME=""
if command -v docker &> /dev/null && docker info &> /dev/null 2>&1; then
    CONTAINER_RUNTIME="docker"
elif command -v podman &> /dev/null; then
    CONTAINER_RUNTIME="podman"
else
    echo "❌ No container runtime found. Please install Docker or Podman."
    exit 1
fi

echo "Using container runtime: $CONTAINER_RUNTIME"

### Setup the directories
mkdir -p ~/homepageBackup # create the backup repo

### Install dependencies based on OS
if [ "$MACHINE" = "Mac" ]; then
    echo "Installing dependencies on macOS..."
    
    # Check if Homebrew is installed
    if ! command -v brew &> /dev/null; then
        echo "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    
    # Install dependencies via Homebrew
    brew install gnupg rclone age
    
else
    echo "Installing dependencies on Linux..."
    
    # Linux installation
    sudo apt update
    sudo apt install -y gnupg rclone age
fi

### Configure backup encryption
if [ ! -f "secret.age" ]; then
    echo "⚠️ secret.age file not found. Please create it first with your encryption key."
    echo "You can create it by running: echo 'your-secure-passphrase' | age -p > secret.age"
    exit 1
fi

export PASSPHRASE=$(age -d secret.age)
export HOMEPAGE_TARGET_DIR="$(eval echo ~$USER)/homepageBackup"

### Environment variable setup based on OS
if [ "$MACHINE" = "Mac" ]; then
    echo "Configuring environment variables for macOS..."
    
    # macOS uses different shell profiles
    SHELL_PROFILE=""
    
    # Detect which shell is being used
    if [ -n "$ZSH_VERSION" ]; then
        SHELL_PROFILE="$HOME/.zshrc"
    elif [ -n "$BASH_VERSION" ]; then
        SHELL_PROFILE="$HOME/.bash_profile"
    else
        # Default to .zshrc on macOS (common default)
        SHELL_PROFILE="$HOME/.zshrc"
    fi
    
    echo "Using shell profile: $SHELL_PROFILE"
    
    # Add environment variables to shell profile
    USER_HOME=$(eval echo ~$USER)
    
    # Remove existing entries and add new ones
    sed -i '' '/^export HOME=/d' "$SHELL_PROFILE" 2>/dev/null || true
    sed -i '' '/^export PASSPHRASE=/d' "$SHELL_PROFILE" 2>/dev/null || true
    sed -i '' '/^export HOMEPAGE_TARGET_DIR=/d' "$SHELL_PROFILE" 2>/dev/null || true
    
    echo "export HOME=\"$USER_HOME\"" >> "$SHELL_PROFILE"
    echo "export PASSPHRASE=\"$PASSPHRASE\"" >> "$SHELL_PROFILE"
    echo "export HOMEPAGE_TARGET_DIR=\"$HOMEPAGE_TARGET_DIR\"" >> "$SHELL_PROFILE"
    
    # Source the profile to apply changes
    source "$SHELL_PROFILE"
    
else
    echo "Configuring environment variables for Linux..."
    
    # Linux environment variable setup
    USER_HOME=$(eval echo ~$USER)
    
    sudo grep -q '^HOME=' /etc/environment && sudo sed -i "s|^HOME=.*|HOME=\"$USER_HOME\"|" /etc/environment || echo "HOME=\"$USER_HOME\"" | sudo tee -a /etc/environment > /dev/null
    sudo grep -q '^PASSPHRASE=' /etc/environment && sudo sed -i 's/^PASSPHRASE=.*/PASSPHRASE="'$PASSPHRASE'"/' /etc/environment || echo 'PASSPHRASE="'$PASSPHRASE'"' | sudo tee -a /etc/environment > /dev/null
    sudo grep -q '^HOMEPAGE_TARGET_DIR=' /etc/environment && sudo sed -i 's/^HOMEPAGE_TARGET_DIR=.*/HOMEPAGE_TARGET_DIR="'$HOMEPAGE_TARGET_DIR'"/' /etc/environment || echo 'HOMEPAGE_TARGET_DIR="'$HOMEPAGE_TARGET_DIR'"' | sudo tee -a /etc/environment > /dev/null
fi

### Configure RClone sync
echo "Configuring RClone..."
rclone config

### Copy the backup scripts to user home
if [ -f "remoteBackupHomepage.sh" ]; then
    cp dataBackupHomepage.sh ~/dataBackupHomepage.sh
    cp remoteBackupHomepage.sh ~/remoteBackupHomepage.sh
    chmod +x ~/dataBackupHomepage.sh
    chmod +x ~/remoteBackupHomepage.sh
else
    echo "Warning: Backup scripts not found in current directory"
fi

### Configure auto backups with crontab
echo "Setting up automated backups with cron..."

# Function to find container runtime full path
find_container_runtime_path() {
    local runtime_path=""
    
    if [ "$CONTAINER_RUNTIME" = "docker" ]; then
        runtime_path=$(which docker 2>/dev/null)
    elif [ "$CONTAINER_RUNTIME" = "podman" ]; then
        runtime_path=$(which podman 2>/dev/null)
    fi
    
    if [ -z "$runtime_path" ]; then
        # Try common installation paths
        if [ "$CONTAINER_RUNTIME" = "docker" ]; then
            for path in /usr/bin/docker /usr/local/bin/docker /opt/homebrew/bin/docker; do
                if [ -x "$path" ]; then
                    runtime_path="$path"
                    break
                fi
            done
        elif [ "$CONTAINER_RUNTIME" = "podman" ]; then
            for path in /usr/bin/podman /usr/local/bin/podman /opt/homebrew/bin/podman; do
                if [ -x "$path" ]; then
                    runtime_path="$path"
                    break
                fi
            done
        fi
    fi
    
    echo "$runtime_path"
}

# Function to remove existing homepage cron jobs
remove_existing_homepage_cron() {
    echo "Checking for existing homepage cron jobs..."
    
    CURRENT_CRONTAB=$(crontab -l 2>/dev/null)
    
    if echo "$CURRENT_CRONTAB" | grep -q "homepage"; then
        echo "Found existing homepage cron jobs, removing them..."
        echo "$CURRENT_CRONTAB" | grep -v "homepage" > /tmp/crontab_temp
        crontab /tmp/crontab_temp
        rm -f /tmp/crontab_temp
        echo "Existing homepage cron jobs removed."
    else
        echo "No existing homepage cron jobs found."
    fi
}

# Remove existing homepage cron jobs
remove_existing_homepage_cron

# Get the full path to the container runtime
CONTAINER_RUNTIME_PATH=$(find_container_runtime_path)

if [ -z "$CONTAINER_RUNTIME_PATH" ]; then
    echo "❌ Could not find full path to $CONTAINER_RUNTIME"
    echo "Please ensure $CONTAINER_RUNTIME is properly installed and accessible"
    exit 1
fi

echo "Container runtime path: $CONTAINER_RUNTIME_PATH"

# Set up new cron job based on OS with full paths
if [ "$MACHINE" = "Mac" ]; then
    # macOS cron setup with full paths
    CRON_COMMAND="0 4 * * * export PATH=/usr/local/bin:/opt/homebrew/bin:\$PATH && source $SHELL_PROFILE && bash \$HOME/dataBackupHomepage.sh"
    
    # Add to crontab
    (crontab -l 2>/dev/null; echo "$CRON_COMMAND") | crontab -
    
else
    # Linux cron setup with full paths
    LINUX_CRON_COMMAND="0 4 * * * export PATH=/usr/local/bin:/usr/bin:\$PATH && . /etc/environment && bash \$HOME/dataBackupHomepage.sh"
    
    # Add to crontab
    (crontab -l 2>/dev/null; echo "$LINUX_CRON_COMMAND") | crontab -
fi

echo "Setup complete!"
echo "Configuration summary:"
echo "- OS detected: $MACHINE"
echo "- Container runtime: $CONTAINER_RUNTIME"
echo "- Container runtime path: $CONTAINER_RUNTIME_PATH"
echo "- Backup directory: $HOMEPAGE_TARGET_DIR"
echo "- Cron job scheduled for 4:00 AM daily with full PATH"

if [ "$MACHINE" = "Mac" ]; then
    echo "- Environment variables added to: $SHELL_PROFILE"
    echo "Note: You may need to restart your terminal or run 'source $SHELL_PROFILE' to use the environment variables"
fi

# Display the new cron job for verification
echo ""
echo "📅 Current cron jobs:"
crontab -l | grep -E "(homepage|cron)" || echo "No homepage-related cron jobs found"