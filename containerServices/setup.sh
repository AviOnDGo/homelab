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

COMPOSE_CMD="$CONTAINER_RUNTIME compose"

echo "Using container runtime: $CONTAINER_RUNTIME"
echo "Using compose command: $COMPOSE_CMD"

## Setting up certificates
mkdir -p ~/vaultwarden # main vaultwarden data directory

## Configurations
echo "Setting up Vaultwarden backup configuration..."
bash ./configureDuplicityRclone.sh

### Create containers without starting them
if [ "$CONTAINER_RUNTIME" = "docker" ]; then
    echo "Creating containers with Docker Compose..."
    $COMPOSE_CMD create
elif [ "$CONTAINER_RUNTIME" = "podman" ]; then
    echo "Creating containers with Podman..."
    if command -v podman-compose &> /dev/null; then
        $COMPOSE_CMD up --no-start 2>/dev/null || {
            echo "podman-compose up --no-start not supported, using alternative method..."
            $COMPOSE_CMD up -d
            $COMPOSE_CMD stop
        }
    else
        $COMPOSE_CMD up -d
        $COMPOSE_CMD stop
    fi
fi

## Create necessary directories
echo ""
echo "📁 Creating data directories..."
mkdir -p ~/.homepage

## Restore homepage backup if available
echo ""
echo "📦 Checking for homepage backups..."

# Try to restore from backup
if [ -f "./dataRestoreHomepage.sh" ]; then
    echo "🔄 Running homepage restore script..."
    bash ./dataRestoreHomepage.sh
elif [ -f "$HOME/dataRestoreHomepage.sh" ]; then
    echo "🔄 Running homepage restore script from home directory..."
    bash "$HOME/dataRestoreHomepage.sh"
else
    echo "⚠️  No restore script found. Will use default configuration."
    echo "💡 If you have backups, run ./dataRestoreHomepage.sh manually after setup."
fi

## Start all containers
echo ""
echo "🚀 Starting all containers..."
$COMPOSE_CMD up -d

## Display service URLs
echo ""
echo "🎉 Setup Complete!"
echo "=================="
echo ""
echo "Container Runtime: $CONTAINER_RUNTIME"
echo ""
echo "🌐 Service URLs:"
echo "  - Homepage:   http://localhost:9001"
echo ""
echo "📂 Data locations:"
echo "  - Homepage config: ~/.homepage"
echo ""
echo "🔧 Useful commands:"
echo "  - View logs:        $COMPOSE_CMD logs -f [service_name]"
echo "  - Restart:          $COMPOSE_CMD restart [service_name]"
echo "  - Stop all:         $COMPOSE_CMD stop"
echo "  - Start all:        $COMPOSE_CMD start"
echo "  - Remove all:       $COMPOSE_CMD down"
echo "  - Remove with data: $COMPOSE_CMD down -v"
echo ""
echo "💡 First time setup:"
echo "  1. Configure Homepage at ~/.homepage/services.yaml"
echo "  2. Set up backups by running: ./configureRclone.sh"