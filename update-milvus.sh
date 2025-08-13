#!/bin/bash

# Milvus Docker Compose Update Script
# This script checks for newer versions of the official Milvus docker-compose file,
# updates if necessary, and restarts services

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$HOME/Library/Logs/milvus-update.log"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
UPSTREAM_URL="https://github.com/milvus-io/milvus/releases/latest/download/milvus-standalone-docker-compose.yml"
TEMP_FILE="$SCRIPT_DIR/.docker-compose.yml.new"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Function to log messages
log() {
    echo "$(date): $1" | tee -a "$LOG_FILE"
}

# Function to check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log "Error: Not in a git repository"
        exit 1
    fi
}

# Function to check if docker-compose file exists
check_compose_file() {
    if [ ! -f "$COMPOSE_FILE" ]; then
        log "Error: docker-compose.yml not found in $SCRIPT_DIR"
        exit 1
    fi
}

# Function to download the latest compose file
download_latest() {
    log "Downloading latest docker-compose file from upstream..."
    if curl -L -s -o "$TEMP_FILE" "$UPSTREAM_URL"; then
        log "Download successful"
        return 0
    else
        log "Error: Failed to download latest docker-compose file"
        return 1
    fi
}

# Function to compare files and check if update is needed
needs_update() {
    if [ ! -f "$TEMP_FILE" ]; then
        log "Error: Downloaded file not found"
        return 1
    fi
    
    # Compare files, ignoring whitespace differences
    if diff -w "$COMPOSE_FILE" "$TEMP_FILE" > /dev/null; then
        log "No update needed - files are identical"
        rm -f "$TEMP_FILE"
        return 1
    else
        log "Update needed - files differ"
        return 0
    fi
}

# Function to stop Milvus services
stop_services() {
    log "Stopping Milvus services using stop-milvus.sh..."
    if "$SCRIPT_DIR/stop-milvus.sh"; then
        log "Services stopped successfully"
        return 0
    else
        log "Warning: Error stopping services, continuing with update..."
        return 1
    fi
}

# Function to start Milvus services
start_services() {
    log "Starting Milvus services using start-milvus.sh..."
    # Start the services in the background since start-milvus.sh runs continuously
    if "$SCRIPT_DIR/start-milvus.sh" &>/dev/null & then
        local start_pid=$!
        # Give it time to start up
        sleep 10
        # Check if the process is still running (services started successfully)
        if kill -0 "$start_pid" 2>/dev/null; then
            log "Services started successfully (PID: $start_pid)"
            return 0
        else
            log "Error: start-milvus.sh exited unexpectedly"
            return 1
        fi
    else
        log "Error: Failed to start services"
        return 1
    fi
}

# Function to backup current file and update
update_compose_file() {
    log "Backing up current docker-compose.yml..."
    if cp "$COMPOSE_FILE" "${COMPOSE_FILE}.backup"; then
        log "Backup created successfully"
    else
        log "Warning: Failed to create backup"
    fi
    
    log "Updating docker-compose.yml..."
    if mv "$TEMP_FILE" "$COMPOSE_FILE"; then
        log "docker-compose.yml updated successfully"
        return 0
    else
        log "Error: Failed to update docker-compose.yml"
        # Attempt to restore backup
        if [ -f "${COMPOSE_FILE}.backup" ]; then
            mv "${COMPOSE_FILE}.backup" "$COMPOSE_FILE"
            log "Restored backup file"
        fi
        return 1
    fi
}

# Function to commit and push changes
commit_changes() {
    log "Committing updated docker-compose.yml to git..."
    cd "$SCRIPT_DIR"
    
    # Extract version information if available
    local version_info=""
    if grep -q "image.*milvusdb/milvus:" "$COMPOSE_FILE"; then
        version_info=$(grep "image.*milvusdb/milvus:" "$COMPOSE_FILE" | head -1 | sed 's/.*milvusdb\/milvus://' | sed 's/[[:space:]]*//')
    fi
    
    local commit_message="Update Milvus docker-compose to latest version"
    if [ -n "$version_info" ]; then
        commit_message="$commit_message

Updated to version: $version_info
Downloaded from: $UPSTREAM_URL"
    fi
    
    if git add docker-compose.yml && git commit -m "$commit_message"; then
        log "Changes committed successfully"
        
        # Check if there's a remote tracking branch
        local current_branch=$(git rev-parse --abbrev-ref HEAD)
        local tracking_branch=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
        
        if [ -n "$tracking_branch" ]; then
            log "Pushing changes to remote tracking branch: $tracking_branch"
            if git push; then
                log "Changes pushed successfully"
                return 0
            else
                log "Warning: Failed to push changes to remote"
                # Don't fail the whole process if push fails
                return 0
            fi
        else
            log "No remote tracking branch found, skipping push"
            return 0
        fi
    else
        log "Error: Failed to commit changes"
        return 1
    fi
}

# Main execution
main() {
    log "=== Milvus Update Script Started ==="
    
    # Change to script directory
    cd "$SCRIPT_DIR" || {
        log "Error: Could not change to directory $SCRIPT_DIR"
        exit 1
    }
    
    # Perform checks
    check_git_repo
    check_compose_file
    
    # Download and check for updates
    if ! download_latest; then
        exit 1
    fi
    
    if ! needs_update; then
        log "No update required"
        exit 0
    fi
    
    log "Update required - proceeding with update process"
    
    # Stop services
    stop_services
    
    # Update compose file
    if ! update_compose_file; then
        log "Failed to update compose file"
        start_services  # Try to restart with old file
        exit 1
    fi
    
    # Start services with new file
    if ! start_services; then
        log "Failed to start services with new compose file"
        # Attempt to restore backup and restart
        if [ -f "${COMPOSE_FILE}.backup" ]; then
            log "Attempting to restore backup and restart services..."
            mv "${COMPOSE_FILE}.backup" "$COMPOSE_FILE"
            start_services
        fi
        exit 1
    fi
    
    # Clean up backup file
    rm -f "${COMPOSE_FILE}.backup"
    
    # Commit changes
    commit_changes
    
    log "=== Milvus Update Script Completed Successfully ==="
}

# Run main function
main "$@"