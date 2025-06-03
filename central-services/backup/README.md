# PostgreSQL Backup Service

A containerized PostgreSQL backup solution providing automated database backups with validation and retention management.

## Technology Stack

- Debian Bullseye Slim Docker image
- PostgreSQL 15 Client Tools
- Ofelia (cron-like job scheduler for Docker)
- Configurable backup directory with volume mounting
- Built-in integrity checking for backup files

## Overview

This service creates and manages PostgreSQL database backups using a containerized approach. It supports both logical backups (SQL dumps) and physical backups (base backups) with automatic validation and cleanup.

### Key Features

- **Logical Backups**: Complete database exports using `pg_dump`/`pg_dumpall`
- **Physical Backups**: Full cluster backups using `pg_basebackup`
- **Automatic Validation**: Fast integrity checks (1-5 seconds)
- **Retention Management**: Configurable cleanup of old backups
- **Scheduled Execution**: Automated backups via Ofelia scheduler
- **Comprehensive Logging**: Detailed operation logs

## Backup Types

### Logical Backups

- **Output**: Compressed SQL files (`.sql.gz`)
- **Location**: `/var/lib/backups/logical/`
- **Use Case**: Individual database restoration, cross-version compatibility

### Physical Backups

- **Output**: Base backup directories with WAL files
- **Location**: `/var/lib/backups/physical/`
- **Use Case**: Complete cluster restoration, point-in-time recovery

## Automated Scheduling

Configured via `ofelia-config.ini`:

- **Backup Creation**: Runs validated backups on schedule
- **Cleanup**: Automatic removal of backups older than retention period

## Security

- Credentials managed via `.pgpass` file
- Secure file permissions on backup directories
- Container runs with dedicated backup user
- Environment variable-based configuration 