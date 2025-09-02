#!/bin/bash

# Milvus Docker Compose Auto-Start Script
# This script waits for Docker to be ready, then starts the Milvus services
# It also handles shutdown signals to stop services gracefully

# Use the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$HOME/Library/Logs/milvus-docker-compose.log"
MAX_WAIT_TIME=300  # 5 minutes

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Rotate log file on startup (new session) or if it's larger than 10MB
if [ -f "$LOG_FILE" ]; then
    file_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
    if [ $file_size -gt 10485760 ]; then
        # Size-based rotation
        [ -f "${LOG_FILE}.old" ] && rm -f "${LOG_FILE}.old"
        mv "$LOG_FILE" "${LOG_FILE}.old"
        echo "$(date): Log file rotated due to size (${file_size} bytes)" > "$LOG_FILE"
    else
        # Session-based rotation (reboot)
        [ -f "${LOG_FILE}.old" ] && rm -f "${LOG_FILE}.old"
        mv "$LOG_FILE" "${LOG_FILE}.old"
        echo "$(date): New session started, previous log saved as .old" > "$LOG_FILE"
    fi
fi

# Redirect all output to log file
exec > >(tee -a "$LOG_FILE") 2>&1

echo "$(date): Milvus auto-start script initiated from $SCRIPT_DIR"

# Function to stop services gracefully
cleanup() {
    echo "$(date): Received shutdown signal, stopping Milvus services..."
    cd "$SCRIPT_DIR"
    if docker-compose down; then
        echo "$(date): Milvus services stopped successfully"
    else
        echo "$(date): Error stopping Milvus services"
    fi
    exit 0
}

# Set up signal traps for graceful shutdown
trap cleanup SIGTERM SIGINT

# Function to check if Docker is ready
check_docker() {
    /usr/local/bin/docker version
}

# Wait for Docker to be ready
echo "$(date): Waiting for Docker to be ready..."
wait_time=0
while ! check_docker; do
    if [ $wait_time -ge $MAX_WAIT_TIME ]; then
        echo "$(date): Timeout waiting for Docker after 5 minutes. Exiting."
        exit 1
    fi
    
    echo "$(date): Docker not ready yet, waiting... ($wait_time/$MAX_WAIT_TIME seconds)"
    sleep 5
    wait_time=$((wait_time + 5))
done

echo "$(date): Docker is ready!"

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

# Start Milvus services
echo "$(date): Starting Milvus services..."
if /usr/local/bin/docker-compose up -d; then
    echo "$(date): Milvus services started successfully"
    
    # Keep the script running to handle shutdown signals
    echo "$(date): Script running, waiting for shutdown signal..."
    
    # Wait indefinitely for signals
    while true; do
        sleep 30
        # Optional: Check if containers are still running
        if ! /usr/local/bin/docker-compose ps --services --filter "status=running" | grep -q .; then
            echo "$(date): Warning: Some Milvus services may have stopped unexpectedly"
        fi
    done
else
    echo "$(date): Error starting Milvus services"
    exit 1
fi
