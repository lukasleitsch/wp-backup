# WordPress Backup Script

A simple bash script for creating WordPress backups and uploading them to Hetzner Storage Box via WebDAV. The script uses **streaming** to upload backups directly to remote storage without storing temporary files locally.

## Prerequisites

- **WP-CLI** must be installed and available in PATH
- **Knowledge of WP-CLI** is recommended for restore operations
- **curl** for WebDAV uploads
- **tar** and **gzip** for compression
- **Hetzner Storage Box** account

## What Gets Backed Up

The script creates backups of:

- **Database** - Complete WordPress database dump (compressed with gzip, streamed directly to remote)
- **WordPress Files** - Only essential files (streamed directly to remote):
  - `wp-content/` directory (excluding cache, plugins, languages)
  - `wp-config.php` file
- **Plugin List** - Complete plugin inventory with versions (JSON and text format)
- **Manifest** - Backup metadata including WordPress version, theme, and file sizes

## Streaming Feature

The script uses **direct streaming** to upload backups:
- No temporary files are stored locally
- Database dumps are piped directly from WP-CLI through gzip to curl
- File archives are created by tar and streamed directly to remote storage
- Reduces local disk usage and speeds up backup process

### Exclusions

The following files/directories are excluded from backup:
- WordPress cache directories
- Plugin files (backed up separately as a list)
- Language files
- Thumbnails (can be regenerated with `wp media regenerate`)
- Log files, git directories, node_modules
- System files (.DS_Store, Thumbs.db)

## Installation

```bash
curl -o wp-backup.sh https://raw.githubusercontent.com/lukasleitsch/wp-backup/refs/heads/main/wp-backup.sh && chmod +x wp-backup.sh
```

Then run the script:
```bash
./wp-backup.sh
```

The first run will create `~/.wp-backup.conf` and exit. Edit this file with your credentials, then run again.

## Usage

```bash
./wp-backup.sh
```

## Automating with Cron

To run backups automatically, add the script to your crontab:

```bash
# Edit crontab
crontab -e

# Run daily at 2 AM (suppress output to avoid emails)
0 2 * * * /path/to/wp-backup.sh >/dev/null 2>&1
```

Make sure to use the full path to the script in your cron job.

## Security Note

**No encryption is used** - backups are stored as plain compressed archives.

## Configuration

**Recommendation:** Create a sub-account in your Hetzner Storage Box for backup operations instead of using the main account.

On first run, the script creates a configuration file at `~/.wp-backup.conf`:

```bash
HETZNER_HOST="your-storage-box.your-server.de"
HETZNER_USER="your-username"
HETZNER_PASSWORD="your-password"
HETZNER_REMOTE_DIR="/"
REMOTE_BACKUP_COUNT="3"

# Healthchecks.io monitoring URL (optional)
HEALTHCHECK_URL=""
```

## Monitoring with Healthchecks.io

The script supports monitoring via [Healthchecks.io](https://healthchecks.io/) or self-hosted instances to track backup success/failure:

1. Create a check at https://healthchecks.io/ or your self-hosted instance
2. Copy your ping URL
3. Add it to your config file:
   ```bash
   HEALTHCHECK_URL="https://hc-ping.com/your-uuid-here"
   # or for self-hosted: HEALTHCHECK_URL="https://your-domain.com/ping/your-uuid-here"
   ```

The script will:
- Send `/start` signal when backup begins
- Send success ping with logs when backup completes
- Send failure ping with logs and exit code if backup fails

## Restore Notes

After restoring files, regenerate WordPress thumbnails:
```bash
wp media regenerate
```
