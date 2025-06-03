#!/bin/bash

# Path to the main backup script that performs the actual backup operations
BACKUP_SCRIPT="/opt/backup/scripts/backup.sh"

# Parse the first command line argument, defaulting to empty string if none provided
# This determines which backup operation to perform
case "${1:-}" in

# LOGICAL BACKUP OPERATION
# Creates SQL dump files using pg_dump (single DB) or pg_dumpall (all DBs)
# This is the default operation when no argument is provided
"logical" | "")
  echo "Running logical backup (all databases)..."
  echo "  → Creates compressed SQL files (.sql.gz)"
  echo "  → Portable across PostgreSQL versions"
  echo "  → Can be used for selective database restoration"
  # Use 'exec' to replace current process with backup script
  # This ensures proper signal handling and exit codes
  exec "$BACKUP_SCRIPT" --type logical
  ;;

# PHYSICAL BACKUP OPERATION
# Creates binary copy of entire PostgreSQL cluster using pg_basebackup
"physical")
  echo "Running physical backup..."
  echo "  → Creates binary cluster copy (tar.gz files)"
  echo "  → Faster for large databases"
  echo "  → Must restore to compatible PostgreSQL version"
  echo "  → Includes all databases and configuration"
  exec "$BACKUP_SCRIPT" --type physical
  ;;

# LIST AVAILABLE BACKUPS
# Shows all existing backups with file sizes and dates
"list")
  echo "Listing available backups..."
  echo "  → Shows both logical and physical backups"
  echo "  → Displays file sizes and creation dates"
  echo "  → Helps identify backups for restoration"
  exec "$BACKUP_SCRIPT" --list
  ;;

# CLEANUP OLD BACKUPS
# Removes backups older than the configured retention period
"cleanup")
  echo "Cleaning up old backups..."
  echo "  → Removes backups older than retention period"
  echo "  → Frees up disk space"
  echo "  → Keeps recent backups based on policy"
  exec "$BACKUP_SCRIPT" --cleanup
  ;;

# INVALID COMMAND HANDLER
# Shows usage information when an unrecognized command is provided
*)
  echo "ERROR: Unknown command '${1:-}'"
  echo ""
  echo "Usage: $0 [logical|physical|list|cleanup]"
  echo ""
  echo "COMMANDS:"
  echo "  logical  - Create logical backup of all databases (default)"
  echo "           → Uses pg_dump/pg_dumpall to create SQL scripts"
  echo "           → Portable across PostgreSQL versions"
  echo "           → Smaller file sizes, good for development/testing"
  echo ""
  echo "  physical - Create physical backup of database cluster"
  echo "           → Uses pg_basebackup for binary cluster copy"
  echo "           → Faster for large production databases"
  echo "           → Requires same PostgreSQL version for restore"
  echo ""
  echo "  list     - List all available backups with details"
  echo "           → Shows backup types, sizes, and creation dates"
  echo "           → Helps identify backups for restoration"
  echo ""
  echo "  cleanup  - Clean up old backups based on retention policy"
  echo "           → Removes backups older than configured days"
  echo "           → Frees disk space while preserving recent backups"
  echo ""
  echo "EXAMPLES:"
  echo "  $0                    # Create logical backup (default)"
  echo "  $0 logical            # Create logical backup explicitly"
  echo "  $0 physical           # Create physical backup"
  echo "  $0 list               # Show available backups"
  echo "  $0 cleanup            # Remove old backups"
  echo ""
  echo "For more detailed options, run: $BACKUP_SCRIPT --help"

  # Exit with error code to indicate invalid usage
  exit 1
  ;;
esac

# Note: This line should never be reached due to 'exec' calls above
# The 'exec' command replaces the current shell process with the backup script
