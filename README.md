# WordPress Backup Script

A simple bash script for creating WordPress backups and uploading them to Hetzner Storage Box via WebDAV.

## Prerequisites

- **WP-CLI** must be installed and available in PATH
- **Knowledge of WP-CLI** is recommended for restore operations
- **curl** for WebDAV uploads
- **tar** and **gzip** for compression
- **Hetzner Storage Box** account

## What Gets Backed Up

The script creates backups of:

- **Database** - Complete WordPress database dump (compressed with gzip)
- **WordPress Files** - Only essential files:
  - `wp-content/` directory (excluding cache, plugins, languages)
  - `wp-config.php` file
- **Plugin List** - Complete plugin inventory with versions (JSON and text format)
- **Manifest** - Backup metadata including WordPress version, theme, and file sizes

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
```

## Restore Notes

After restoring files, regenerate WordPress thumbnails:
```bash
wp media regenerate
```

Reinstall plugins using the backed up plugin list:
```bash
wp plugin install --activate $(jq -r '.[].name' plugins.json)
```
