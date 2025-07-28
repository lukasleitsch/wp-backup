# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a WordPress backup script that creates comprehensive backups of WordPress sites and uploads them to Hetzner Storage Box using WebDAV. The script is a single bash file that handles database dumps, file archiving, and remote storage management.

## Key Commands

### Running the backup
```bash
./wp-backup.sh
```

### Testing the script
```bash
bash -n wp-backup.sh  # Syntax check
```

### Making the script executable
```bash
chmod +x wp-backup.sh
```

## Architecture

The script follows a modular approach with distinct phases:
1. **Configuration loading** - Loads config from `~/.wp-backup.conf` (creates template if missing)
2. **Pre-flight checks** - Validates WP-CLI availability and WordPress directory
3. **Backup creation** - Creates database dump, files archive, plugin list, and manifest
4. **Archive consolidation** - Packages everything into a single tar.gz file
5. **Remote upload** - Uploads to Hetzner Storage Box via WebDAV
6. **Cleanup** - Removes old backups and temporary files

## Configuration

**Setup:** The first run creates a config template at `~/.wp-backup.conf` and exits. Edit this file with your credentials before running again.

**Recommendation:** Create a sub-account in your Hetzner Storage Box for backup operations instead of using the main account.

The script requires a config file at `~/.wp-backup.conf` with:
- `HETZNER_HOST` - Storage Box hostname
- `HETZNER_USER` - Storage Box username
- `HETZNER_PASSWORD` - Storage Box password
- `HETZNER_REMOTE_DIR` - Remote directory path
- `REMOTE_BACKUP_COUNT` - Number of backups to keep

## Security Note

**No encryption is used** - backups are stored as plain compressed archives.

## Dependencies

- WP-CLI (for database dumps and WordPress info)
- curl (for WebDAV uploads)
- tar, gzip (for compression)
- Standard bash utilities

## What Gets Backed Up

The script creates backups of:
- **Database** - Complete WordPress database dump (compressed with gzip)
- **WordPress Files** - Only essential files:
  - `wp-content/` directory (excluding cache, languages)
  - `wp-config.php` file
- **Plugin List** - Complete plugin inventory with versions (JSON and text format)
- **Manifest** - Backup metadata including WordPress version, theme, and file sizes

### Exclusions

The following files/directories are excluded from backup:
- WordPress cache directories
- Language files
- **Thumbnails** (can be regenerated with `wp media regenerate`)
- Log files, git directories, node_modules
- System files (.DS_Store, Thumbs.db)

## Key Functions

- `backup_database()` - Uses WP-CLI to create and compress database dump
- `backup_wordpress_files()` - Creates tar archive excluding cache/temp files and thumbnails
- `upload_to_hetzner()` - Handles WebDAV upload to Storage Box
- `cleanup_remote_backups()` - Maintains backup retention policy
- `create_manifest()` - Creates detailed backup information file

## File Structure

The script creates temporary backups in `~/tmp/wp-backups/` with timestamped directories containing:
- `database.sql.gz` - Compressed database dump
- `wordpress-files.tar.gz` - WordPress file archive
- `plugins.json/txt` - Plugin inventory
- `manifest.txt` - Backup metadata
- `wp-backup-YYYYMMDD_HHMMSS.tar.gz` - Final consolidated archive

## Restore Notes

After restoring files, regenerate WordPress thumbnails:
```bash
wp media regenerate
```

## Coding Guidelines

- Don't use short parameter versions. Always use the long parameter format
- Avoid redundant comments that simply restate what the function name already conveys
- Only one empty line between functions