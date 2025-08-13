#!/bin/bash

# Milvus Docker Compose Stop Script
# This script cleanly stops the Milvus services

# Use the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$HOME/Library/Logs/milvus-docker-compose.log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Redirect all output to log file
exec > >(tee -a "$LOG_FILE") 2>&1

echo "$(date): Milvus stop script initiated from $SCRIPT_DIR"

# Change to the script's directory (where docker-compose.yml should be)
cd "$SCRIPT_DIR" || {
    echo "$(date): Error: Could not change to directory $SCRIPT_DIR"
    exit 1
}

# Verify docker-compose.yml exists
if [ ! -f "docker-compose.yml" ]; then
    echo "$(date): Error: docker-compose.yml not found in $SCRIPT_DIR"
    exit 1
fi

# Stop Milvus services
echo "$(date): Stopping Milvus services..."
if docker-compose down; then
    echo "$(date): Milvus services stopped successfully"
    exit 0
else
    echo "$(date): Error stopping Milvus services"
    exit 1
fi