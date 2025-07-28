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

# Healthchecks.io monitoring URL (optional)
HEALTHCHECK_URL=""
EOF
        chmod 600 "$CONFIG_FILE"
        error "Please edit $CONFIG_FILE with your Storage Box credentials and run the script again."
    fi

    # Source the configuration file
    source "$CONFIG_FILE"

    # Set WebDAV URL after loading config
    WEBDAV_URL="https://$HETZNER_HOST$HETZNER_REMOTE_DIR"
}

# WordPress path (defaults to $HOME/html if not set)
WORDPRESS_PATH="${WORDPRESS_PATH:-$HOME/html}"

# WP-CLI path (usually just 'wp' if in PATH)
WP_CLI_PATH="wp"

set -euo pipefail

# Date and timestamp
DATE=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log capture variable
LOG_CAPTURE=""

# Logging function
log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${GREEN}${message}${NC}"
    LOG_CAPTURE="${LOG_CAPTURE}${message}
"
}

error() {
    local message="[ERROR] $1"
    local exit_code="${2:-1}"
    echo -e "${RED}${message}${NC}" >&2
    LOG_CAPTURE="${LOG_CAPTURE}${message}
"
    healthcheck_ping "/$exit_code"
    exit $exit_code
}

warning() {
    local message="[WARNING] $1"
    echo -e "${YELLOW}${message}${NC}"
    LOG_CAPTURE="${LOG_CAPTURE}${message}
"
}

webdav_curl() {
    local path="$1"
    shift
    curl \
        --max-time 600 \
        --connect-timeout 30 \
        --retry 2 \
        --retry-delay 15 \
        --user "$HETZNER_USER:$HETZNER_PASSWORD" \
        --silent \
        --fail \
        "$@" \
        "$WEBDAV_URL$path"
}

healthcheck_ping() {
    local endpoint="$1"

    [ -z "$HEALTHCHECK_URL" ] && return

    if [ -n "$LOG_CAPTURE" ]; then
        curl -fsS -m 10 --retry 5 --data-raw "$LOG_CAPTURE" "$HEALTHCHECK_URL$endpoint" >/dev/null 2>&1 || warning "Healthcheck ping failed"
    else
        curl -fsS -m 10 --retry 5 -o /dev/null "$HEALTHCHECK_URL$endpoint" >/dev/null 2>&1 || warning "Healthcheck ping failed"
    fi
}

check_wp_cli() {
    if ! command -v $WP_CLI_PATH &> /dev/null; then
        error "WP-CLI not found. Please install WP-CLI or update WP_CLI_PATH variable."
    fi
}

check_wordpress_path() {
    if [ ! -d "$WORDPRESS_PATH" ]; then
        error "WordPress directory not found at: $WORDPRESS_PATH"
    fi
}

create_remote_backup_folder() {
    log "Creating remote backup folder: $DATE"

    # Create the timestamped folder on remote
    if ! webdav_curl "/$DATE/" --request MKCOL >/dev/null; then
        error "Failed to create remote backup folder"
    fi

    log "Remote backup folder created successfully"
}

backup_database() {
    log "Creating database dump and streaming to remote..."
    cd "$WORDPRESS_PATH"

    # Stream database dump directly to remote folder
    if ! $WP_CLI_PATH db export --add-drop-table - | gzip | webdav_curl "/$DATE/database.sql.gz" --upload-file - >/dev/null; then
        error "Failed to create and upload database dump"
    fi

    log "Database dump created and uploaded successfully"
}

get_plugin_list() {
    log "Getting plugin list with versions and uploading to remote..."
    cd "$WORDPRESS_PATH"

    # Create and upload JSON plugin list
    if ! $WP_CLI_PATH plugin list --format=json | webdav_curl "/$DATE/plugins.json" --upload-file - >/dev/null; then
        warning "Failed to get plugin list in JSON format"
    fi

    # Also create and upload readable text version
    if ! $WP_CLI_PATH plugin list --format=table | webdav_curl "/$DATE/plugins.txt" --upload-file - >/dev/null; then
        warning "Failed to get plugin list in table format"
    fi

    log "Plugin list created and uploaded successfully"
}

backup_wordpress_files() {
    log "Creating WordPress files backup and streaming to remote..."

    # Change to WordPress directory
    cd "$WORDPRESS_PATH"

    # Create tar archive and stream directly to remote
    # Exclude WordPress thumbnails (can be regenerated with: wp media regenerate)
    if ! tar -czf - \
        --dereference \
        --warning=no-file-changed \
        --exclude="wp-content/cache" \
        --exclude="wp-content/uploads/cache" \
        --exclude="wp-content/languages" \
        --exclude="upgrade*" \
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
        wp-content/ wp-config.php | webdav_curl "/$DATE/wordpress-files.tar.gz" --upload-file - >/dev/null; then
        error "Failed to create and upload WordPress files backup"
    fi

    log "WordPress files backup created and uploaded successfully"
}

create_manifest() {
    log "Creating backup manifest and uploading to remote..."

    # Create manifest and stream to remote
    cat << EOF | webdav_curl "/$DATE/manifest.txt" --upload-file - >/dev/null
Backup Date: $(date)
WordPress Path: $WORDPRESS_PATH
Backup Type: Full WordPress Backup (Streamed)
Database: Included (database.sql.gz)
Files: Included (wordpress-files.tar.gz)
Plugins List: Included (plugins.json, plugins.txt)

WordPress Version: $(cd "$WORDPRESS_PATH" && $WP_CLI_PATH core version 2>/dev/null || echo "Unknown")
Active Theme: $(cd "$WORDPRESS_PATH" && $WP_CLI_PATH theme list --status=active --field=name 2>/dev/null || echo "Unknown")
Total Plugins: $(cd "$WORDPRESS_PATH" && $WP_CLI_PATH plugin list --format=count 2>/dev/null || echo "Unknown")
EOF

    log "Manifest created and uploaded successfully"
}

cleanup_remote_backups() {
    log "Cleaning up old remote backup folders (keeping $REMOTE_BACKUP_COUNT)..."

    # Get list of backup directories (date-formatted folders)
    BACKUP_DIRS=$(curl -s -u "$HETZNER_USER:$HETZNER_PASSWORD" -X PROPFIND "$WEBDAV_URL/" \
        -H "Depth: 1" \
        -H "Content-Type: text/xml" \
        --data '<?xml version="1.0" encoding="utf-8"?><propfind xmlns="DAV:"><prop><displayname/></prop></propfind>' \
        | grep -oE '[0-9]{8}_[0-9]{6}' | sort -r)

    # Keep only the specified number of backups
    DIRS_TO_DELETE=$(echo "$BACKUP_DIRS" | tail -n +$((REMOTE_BACKUP_COUNT + 1)))

    if [ -n "$DIRS_TO_DELETE" ]; then
        for dir in $DIRS_TO_DELETE; do
            log "Deleting old backup folder: $dir"
            curl -s -u "$HETZNER_USER:$HETZNER_PASSWORD" -X DELETE "$WEBDAV_URL/$dir/" --fail 2>/dev/null || warning "Could not delete backup folder: $dir"
        done
    else
        log "No old backup folders to clean up"
    fi
}

main() {
    log "Starting WordPress backup process..."

    # Load configuration
    load_config

    # Signal backup start
    healthcheck_ping "/start"

    # Pre-flight checks
    check_wp_cli
    check_wordpress_path

    # Create backup
    create_remote_backup_folder
    backup_database
    get_plugin_list
    backup_wordpress_files
    create_manifest

    # Cleanup
    cleanup_remote_backups

    log "Backup process completed successfully!"

    # Signal backup success
    healthcheck_ping ""
}

# Run main function
main "$@"
