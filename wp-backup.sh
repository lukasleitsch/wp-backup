#!/bin/bash

# WordPress Backup Script with Hetzner Storage Box Integration
# This script creates incremental backups of WordPress sites and uploads them to Hetzner Storage Box

# Configuration file path
CONFIG_FILE="$HOME/.wp-backup.conf"

# Load configuration or create example config
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log "Configuration file not found. Creating example config at: $CONFIG_FILE"
        cat > "$CONFIG_FILE" << 'EOF'
# WordPress Backup Configuration

HETZNER_HOST=""
HETZNER_USER=""
HETZNER_PASSWORD=""
HETZNER_REMOTE_DIR="/"

REMOTE_BACKUP_COUNT="3"
EOF
        chmod 600 "$CONFIG_FILE"
        error "Please edit $CONFIG_FILE with your Storage Box credentials and run the script again."
        exit 1
    fi
    
    # Source the configuration file
    source "$CONFIG_FILE"
}

# WordPress path (defaults to $HOME/html if not set)
WORDPRESS_PATH="${WORDPRESS_PATH:-$HOME/html}"

# Local backup directory (temporary storage)
BACKUP_LOCAL_DIR="$HOME/tmp/wp-backups"

# WP-CLI path (usually just 'wp' if in PATH)
WP_CLI_PATH="wp"

set -euo pipefail

# Date and timestamp
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_LOCAL_DIR/$DATE"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if wp-cli is available
check_wp_cli() {
    if ! command -v $WP_CLI_PATH &> /dev/null; then
        error "WP-CLI not found. Please install WP-CLI or update WP_CLI_PATH variable."
        exit 1
    fi
}

# Check if WordPress directory exists
check_wordpress_path() {
    if [ ! -d "$WORDPRESS_PATH" ]; then
        error "WordPress directory not found at: $WORDPRESS_PATH"
        exit 1
    fi
}

# Create backup directory
create_backup_dir() {
    log "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
}

# Create database dump using WP-CLI
backup_database() {
    log "Creating database dump..."
    cd "$WORDPRESS_PATH"
    
    if ! $WP_CLI_PATH db export "$BACKUP_DIR/database.sql" --add-drop-table; then
        error "Failed to create database dump"
        exit 1
    fi
    
    log "Database dump created successfully"
    
    # Compress database dump
    gzip "$BACKUP_DIR/database.sql"
    log "Database dump compressed"
}

# Get plugin list with versions using WP-CLI
get_plugin_list() {
    log "Getting plugin list with versions..."
    cd "$WORDPRESS_PATH"
    
    if ! $WP_CLI_PATH plugin list --format=json > "$BACKUP_DIR/plugins.json"; then
        warning "Failed to get plugin list in JSON format"
    fi
    
    # Also create a readable text version
    if ! $WP_CLI_PATH plugin list --format=table > "$BACKUP_DIR/plugins.txt"; then
        warning "Failed to get plugin list in table format"
    fi
    
    log "Plugin list created successfully"
}

# Create WordPress files backup (only wp-content and wp-config.php)
backup_wordpress_files() {
    log "Creating WordPress files backup (wp-content and wp-config.php only)..."
    
    # Change to WordPress directory
    cd "$WORDPRESS_PATH"
    
    # Create tar archive with only wp-content directory and wp-config.php
    # Exclude WordPress thumbnails (can be regenerated with: wp media regenerate)
    tar -czf "$BACKUP_DIR/wordpress-files.tar.gz" \
        --dereference \
        --exclude="wp-content/cache" \
        --exclude="wp-content/uploads/cache" \
        --exclude="wp-content/plugins" \
        --exclude="wp-content/languages" \
        --exclude="backwpup*" \
        --exclude="*.log" \
        --exclude=".git" \
        --exclude="node_modules" \
        --exclude=".DS_Store" \
        --exclude="Thumbs.db" \
        --exclude="*-[0-9]*x[0-9]*.jpg" \
        --exclude="*-[0-9]*x[0-9]*.jpeg" \
        --exclude="*-[0-9]*x[0-9]*.png" \
        --exclude="*-[0-9]*x[0-9]*.gif" \
        --exclude="*-[0-9]*x[0-9]*.webp" \
        wp-content/ wp-config.php
    
    log "WordPress files backup created (wp-content and wp-config.php only)"
}

# Create manifest file with backup information
create_manifest() {
    log "Creating backup manifest..."
    
    cat > "$BACKUP_DIR/manifest.txt" << EOF
Backup Date: $(date)
WordPress Path: $WORDPRESS_PATH
Backup Type: Full WordPress Backup
Database: Included (database.sql.gz)
Files: Included (wordpress-files.tar.gz)
Plugins List: Included (plugins.json, plugins.txt)

File Sizes:
$(ls -lh "$BACKUP_DIR" | tail -n +2)

WordPress Version: $(cd "$WORDPRESS_PATH" && $WP_CLI_PATH core version 2>/dev/null || echo "Unknown")
Active Theme: $(cd "$WORDPRESS_PATH" && $WP_CLI_PATH theme list --status=active --field=name 2>/dev/null || echo "Unknown")
Total Plugins: $(cd "$WORDPRESS_PATH" && $WP_CLI_PATH plugin list --format=count 2>/dev/null || echo "Unknown")
EOF

    log "Manifest created"
}

# Create final comprehensive archive
create_final_archive() {
    log "Creating final backup archive..."
    
    # Create a comprehensive tar.gz archive containing all backup components
    cd "$BACKUP_LOCAL_DIR"
    tar -czf "$DATE.tar.gz" -C "$DATE" .
    
    # Move the archive to the backup directory for upload
    mv "$DATE.tar.gz" "$BACKUP_DIR/"
    
    log "Final backup archive created: $DATE.tar.gz"
}

# Upload backup to Hetzner Storage Box using WebDAV
upload_to_hetzner() {
    log "Uploading backup to Hetzner Storage Box via WebDAV..."
    
    # WebDAV URL construction for Hetzner Storage Box
    WEBDAV_BASE_URL="https://$HETZNER_HOST"
    WEBDAV_DIR_URL="$WEBDAV_BASE_URL$HETZNER_REMOTE_DIR"
    
    # Upload only the final archive file
    ARCHIVE_FILE="$BACKUP_DIR/$DATE.tar.gz"
    if [ -f "$ARCHIVE_FILE" ]; then
        filename=$(basename "$ARCHIVE_FILE")
        log "Uploading $filename..."
        
        if curl -T "$ARCHIVE_FILE" -u "$HETZNER_USER:$HETZNER_PASSWORD" "$WEBDAV_DIR_URL/$filename" --progress-bar; then
            log "Successfully uploaded $filename"
        else
            error "Failed to upload $filename"
            exit 1
        fi
    else
        error "Archive file not found: $ARCHIVE_FILE"
        exit 1
    fi
    
    log "Backup uploaded successfully to Hetzner Storage Box"
}


# Clean up old remote backups
cleanup_remote_backups() {
    log "Cleaning up old remote backups (keeping $REMOTE_BACKUP_COUNT)..."
    
    # WebDAV URL for listing files
    WEBDAV_LIST_URL="https://$HETZNER_HOST$HETZNER_REMOTE_DIR"
    
    # Get list of backup files (date-formatted .tar.gz files)
    BACKUP_FILES=$(curl -s -u "$HETZNER_USER:$HETZNER_PASSWORD" -X PROPFIND "$WEBDAV_LIST_URL/" \
        -H "Depth: 1" \
        -H "Content-Type: text/xml" \
        --data '<?xml version="1.0" encoding="utf-8"?><propfind xmlns="DAV:"><prop><displayname/></prop></propfind>' \
        | grep -oE '[0-9]{8}_[0-9]{6}\.tar\.gz' | sort -r)
    
    # Keep only the specified number of backups
    FILES_TO_DELETE=$(echo "$BACKUP_FILES" | tail -n +$((REMOTE_BACKUP_COUNT + 1)))
    
    if [ -n "$FILES_TO_DELETE" ]; then
        for file in $FILES_TO_DELETE; do
            log "Deleting old backup: $file"
            curl -s -u "$HETZNER_USER:$HETZNER_PASSWORD" -X DELETE "$WEBDAV_LIST_URL/$file" 2>/dev/null || warning "Could not delete backup: $file"
        done
    else
        log "No old backups to clean up"
    fi
}

# Main execution
main() {
    log "Starting WordPress backup process..."
    
    # Load configuration
    load_config
    
    # Pre-flight checks
    check_wp_cli
    check_wordpress_path
    
    # Create backup
    create_backup_dir
    backup_database
    get_plugin_list
    backup_wordpress_files
    create_manifest
    
    # Create single archive
    create_final_archive
    
    # Upload to Hetzner
    upload_to_hetzner
    
    # Cleanup
    cleanup_remote_backups
    
    log "Backup process completed successfully!"
    log "Backup location: $HETZNER_USER@$HETZNER_HOST:$HETZNER_REMOTE_DIR/$DATE"
    
    # Display backup size
    BACKUP_SIZE=$(du -sh "$BACKUP_DIR/$DATE.tar.gz" | cut -f1)
    log "Total backup size: $BACKUP_SIZE"
}

# Trap to cleanup on exit
cleanup_on_exit() {
    if [ -d "$BACKUP_LOCAL_DIR" ]; then
        log "Cleaning up temporary files..."
        rm -rf "$BACKUP_LOCAL_DIR"
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"