#!/bin/bash

# Simple PostgreSQL Backup Script
# Performs logical and physical backups of PostgreSQL databases
#
# Features:
# - Logical backups using pg_dump/pg_dumpall
# - Physical backups using pg_basebackup
# - Simplified backup validation focusing on essential checks
# - Configurable retention policy
# - Comprehensive logging

set -euo pipefail

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly BACKUP_HOME="/var/lib/backups"
readonly LOG_FILE="/var/log/backups/backup.log"
readonly DATE_FORMAT="%Y%m%d_%H%M%S"
readonly TIMESTAMP=$(date +"$DATE_FORMAT")

# Default values
readonly DEFAULT_DB_PORT="5432"
readonly DEFAULT_DB_DATABASE="postgres"
readonly DEFAULT_DB_SUPERUSER="postgres"
readonly DEFAULT_RETENTION_DAYS="7"
readonly DEFAULT_BACKUP_TYPE="logical"

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME] $*"
    echo "$message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO: $*"
}

log_warn() {
    log "WARN: $*"
}

log_error() {
    log "ERROR: $*"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Show usage information
show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Simple PostgreSQL backup script that creates compressed database backups.

OPTIONS:
    -t, --type TYPE         Backup type: logical (pg_dump) or physical (pg_basebackup)
                           Default: logical
    -d, --database DB       Database name to backup (for logical backups)
                           Default: all databases
    -r, --retention DAYS    Number of days to retain backups
                           Default: $DEFAULT_RETENTION_DAYS
    -c, --cleanup          Clean old backups only (no new backup)
    -l, --list             List available backups
    --validate             Validate newly created backup
    --validate-existing PATH   Validate existing backup at specified path
    -h, --help             Show this help message

ENVIRONMENT VARIABLES:
    DB_HOST                Database host (required)
    DB_PORT                Database port (default: $DEFAULT_DB_PORT)
    DB_SUPERUSER          Database superuser (default: $DEFAULT_DB_SUPERUSER)
    DB_SUPERUSER_PASSWORD Database password (required, or use .pgpass)
    BACKUP_DIRECTORY      Backup storage directory (default: $BACKUP_HOME)
    SKIP_BACKUP_VALIDATION Set to 'true' to skip backup validation entirely

EXAMPLES:
    $0                          # Create logical backup of all databases
    $0 --validate               # Create logical backup and validate it
    $0 -t physical --validate   # Create physical backup and validate it
    $0 -d mydb                  # Backup specific database
    $0 -c                       # Clean old backups only
    $0 -l                       # List existing backups
    $0 --validate-existing /path/to/backup.sql.gz # Validate specific backup file

EOF
}

# Check if required environment variables are set
check_environment() {
    local missing_vars=()

    if [[ -z "${DB_HOST:-}" ]]; then
        missing_vars+=("DB_HOST")
    fi

    if [[ -z "${DB_SUPERUSER_PASSWORD:-}" ]] && [[ ! -f "${BACKUP_HOME}/.pgpass" ]]; then
        missing_vars+=("DB_SUPERUSER_PASSWORD (or .pgpass file)")
    fi

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            log_error "  - $var"
        done
        return 1
    fi

    return 0
}

# Test database connection
test_connection() {
    local db_host="${DB_HOST}"
    local db_port="${DB_PORT:-$DEFAULT_DB_PORT}"
    local db_user="${DB_SUPERUSER:-$DEFAULT_DB_SUPERUSER}"
    local db_name="${DB_SUPERUSER_DATABASE:-$DEFAULT_DB_DATABASE}"

    log_info "Testing database connection to $db_host:$db_port"

    # Capture error output for debugging
    local error_output
    error_output=$(psql -h "$db_host" -p "$db_port" -U "$db_user" -d "$db_name" -c "SELECT 1;" 2>&1 >/dev/null)

    if [[ $? -ne 0 ]]; then
        log_error "Cannot connect to database at $db_host:$db_port"
        log_error "Please verify credentials and network connectivity"
        if [[ -n "$error_output" ]]; then
            log_error "psql error output:"
            echo "$error_output" | while IFS= read -r line; do
                log_error "  $line"
            done
        fi
        return 1
    fi

    log_info "Database connection successful"
    return 0
}

# Create backup directory structure
setup_backup_directories() {
    local backup_dir="${BACKUP_DIRECTORY:-$BACKUP_HOME}"

    mkdir -p "$backup_dir/logical"
    mkdir -p "$backup_dir/physical"
    mkdir -p "$(dirname "$LOG_FILE")"

    log_info "Backup directories ready at $backup_dir"
}

# Perform logical backup using pg_dump
logical_backup() {
    local database="${1:-}"
    local validate_flag="${2:-false}"
    local db_host="${DB_HOST}"
    local db_port="${DB_PORT:-$DEFAULT_DB_PORT}"
    local db_user="${DB_SUPERUSER:-$DEFAULT_DB_SUPERUSER}"
    local backup_dir="${BACKUP_DIRECTORY:-$BACKUP_HOME}/logical"
    local backup_file=""

    if [[ -n "$database" ]]; then
        # Backup specific database
        backup_file="$backup_dir/${database}_${TIMESTAMP}.sql.gz"
        log_info "Creating logical backup of database '$database'"

        if pg_dump -h "$db_host" -p "$db_port" -U "$db_user" -d "$database" \
            --verbose --no-password --format=plain |
            gzip >"$backup_file"; then
            log_info "Logical backup completed: $backup_file"
            log_info "Backup size: $(du -h "$backup_file" | cut -f1)"

            # Validate the backup if requested
            if [[ "$validate_flag" == "true" ]]; then
                if [[ "${SKIP_BACKUP_VALIDATION:-false}" == "true" ]]; then
                    log_info "Backup validation skipped (SKIP_BACKUP_VALIDATION=true)"
                elif validate_backup "logical" "$backup_file"; then
                    log_info "Backup validation successful"
                else
                    log_error "Backup validation failed"
                    return 1
                fi
            fi
        else
            log_error "Logical backup failed for database '$database'"
            rm -f "$backup_file"
            return 1
        fi
    else
        # Backup all databases
        backup_file="$backup_dir/all_databases_${TIMESTAMP}.sql.gz"
        log_info "Creating logical backup of all databases"

        if pg_dumpall -h "$db_host" -p "$db_port" -U "$db_user" \
            --verbose --no-password |
            gzip >"$backup_file"; then
            log_info "Logical backup completed: $backup_file"
            log_info "Backup size: $(du -h "$backup_file" | cut -f1)"

            # Validate the backup if requested
            if [[ "$validate_flag" == "true" ]]; then
                if [[ "${SKIP_BACKUP_VALIDATION:-false}" == "true" ]]; then
                    log_info "Backup validation skipped (SKIP_BACKUP_VALIDATION=true)"
                elif validate_backup "logical" "$backup_file"; then
                    log_info "Backup validation successful"
                else
                    log_error "Backup validation failed"
                    return 1
                fi
            fi
        else
            log_error "Logical backup failed for all databases"
            rm -f "$backup_file"
            return 1
        fi
    fi

    return 0
}

# Perform physical backup using pg_basebackup
physical_backup() {
    local validate_flag="${1:-false}"
    local db_host="${DB_HOST}"
    local db_port="${DB_PORT:-$DEFAULT_DB_PORT}"
    local db_user="${DB_SUPERUSER:-$DEFAULT_DB_SUPERUSER}"
    local backup_dir="${BACKUP_DIRECTORY:-$BACKUP_HOME}/physical"
    local backup_path="$backup_dir/basebackup_${TIMESTAMP}"

    log_info "Creating physical backup (base backup)"

    if pg_basebackup -h "$db_host" -p "$db_port" -U "$db_user" \
        -D "$backup_path" --format=tar --gzip \
        --progress --verbose --no-password; then
        log_info "Physical backup completed: $backup_path"
        log_info "Backup size: $(du -sh "$backup_path" | cut -f1)"

        # Validate the backup if requested
        if [[ "$validate_flag" == "true" ]]; then
            if [[ "${SKIP_BACKUP_VALIDATION:-false}" == "true" ]]; then
                log_info "Backup validation skipped (SKIP_BACKUP_VALIDATION=true)"
            elif validate_backup "physical" "$backup_path"; then
                log_info "Backup validation successful"
            else
                log_error "Backup validation failed"
                return 1
            fi
        fi
    else
        log_error "Physical backup failed"
        rm -rf "$backup_path"
        return 1
    fi

    return 0
}

# Clean old backups based on retention policy
cleanup_old_backups() {
    local retention_days="${1:-$DEFAULT_RETENTION_DAYS}"
    local backup_dir="${BACKUP_DIRECTORY:-$BACKUP_HOME}"

    log_info "Cleaning up backups older than $retention_days days"

    # Clean logical backups
    if [[ -d "$backup_dir/logical" ]]; then
        local logical_count
        logical_count=$(find "$backup_dir/logical" -name "*.sql.gz" -mtime +$retention_days -delete -print | wc -l)
        if [[ $logical_count -gt 0 ]]; then
            log_info "Removed $logical_count old logical backup(s)"
        fi
    fi

    # Clean physical backups
    if [[ -d "$backup_dir/physical" ]]; then
        local physical_count
        physical_count=$(find "$backup_dir/physical" -name "basebackup_*" -mtime +$retention_days -exec rm -rf {} \; -print | wc -l)
        if [[ $physical_count -gt 0 ]]; then
            log_info "Removed $physical_count old physical backup(s)"
        fi
    fi
}

# =============================================================================
# BACKUP VALIDATION FUNCTIONS
# =============================================================================

# Validate logical backup integrity
validate_logical_backup() {
    local backup_file="$1"
    local validation_errors=0

    log_info "Validating logical backup: $(basename "$backup_file")"

    # Check if file exists and is not empty
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file does not exist: $backup_file"
        return 1
    fi

    if [[ ! -s "$backup_file" ]]; then
        log_error "Backup file is empty: $backup_file"
        return 1
    fi

    # Wait for file to stabilize (ensure it's completely written)
    log_info "Checking file stability..."
    local initial_size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null)
    sleep 2
    local final_size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null)

    if [[ "$initial_size" != "$final_size" ]]; then
        log_warn "Backup file size changed during validation check - file may still be writing"
        log_info "Waiting additional 3 seconds for file stability..."
        sleep 3
    fi

    # Test gzip integrity
    log_info "Testing gzip file integrity..."
    if ! gzip -t "$backup_file" 2>/dev/null; then
        log_error "Backup file is corrupted (gzip test failed)"
        ((validation_errors++))
    else
        log_info "Gzip integrity check passed"
    fi

    # Check file size (minimum threshold - 1KB for small DBs, but should be reasonable)
    local file_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null)
    if [[ $file_size -lt 1024 ]]; then
        log_error "Backup file suspiciously small: ${file_size} bytes"
        ((validation_errors++))
    else
        log_info "Backup file size acceptable: $(du -h "$backup_file" | cut -f1)"
    fi

    # Simplified content validation - just check if we can read the first few bytes
    log_info "Performing basic content validation..."
    if zcat "$backup_file" 2>/dev/null | head -1 >/dev/null 2>&1; then
        log_info "Backup file can be read and decompressed successfully"

        # Try a simple grep for PostgreSQL indicators without extracting to temp file
        if zcat "$backup_file" 2>/dev/null | head -50 | grep -q -i "postgresql\|pg_dump\|database" 2>/dev/null; then
            log_info "Found PostgreSQL database content indicators"
        else
            log_info "Basic content check completed (no specific indicators found, but file is readable)"
        fi
    else
        log_warn "Could not perform basic content validation, but gzip integrity passed"
        # Don't increment errors since gzip test already passed
    fi

    if [[ $validation_errors -eq 0 ]]; then
        log_info "Logical backup validation passed"
        return 0
    else
        log_error "Logical backup validation failed with $validation_errors errors"
        return 1
    fi
}

# Validate physical backup integrity
validate_physical_backup() {
    local backup_path="$1"
    local validation_errors=0

    log_info "Validating physical backup: $(basename "$backup_path")"

    # Check if backup directory exists
    if [[ ! -d "$backup_path" ]]; then
        log_error "Backup directory does not exist: $backup_path"
        return 1
    fi

    # Check for backup_label file (essential for physical backups)
    if [[ -f "$backup_path/backup_label" ]]; then
        log_info "Found backup_label file"

        # Basic validation of backup_label content
        if grep -q -E "(START WAL LOCATION|CHECKPOINT LOCATION|START TIME)" "$backup_path/backup_label" 2>/dev/null; then
            log_info "backup_label contains expected content"
        else
            log_info "backup_label found but content format unclear (may still be valid)"
        fi
    else
        log_error "backup_label file missing - this is required for physical backups"
        ((validation_errors++))
    fi

    # Check for PG_VERSION file
    if [[ -f "$backup_path/PG_VERSION" ]]; then
        log_info "Found PG_VERSION file"
    else
        log_warn "PG_VERSION file missing (may indicate incomplete backup)"
        ((validation_errors++))
    fi

    # Check for main data files (more flexible check)
    local has_data_files=false

    # Check for base.tar.gz or base directory
    if [[ -f "$backup_path/base.tar.gz" ]]; then
        log_info "Found base.tar.gz"
        # Test tar file integrity if possible
        if tar -tzf "$backup_path/base.tar.gz" >/dev/null 2>&1; then
            log_info "base.tar.gz integrity check passed"
        else
            log_warn "base.tar.gz integrity check failed"
            ((validation_errors++))
        fi
        has_data_files=true
    elif [[ -d "$backup_path/base" ]]; then
        log_info "Found base directory"
        has_data_files=true
    fi

    # Check for other compressed files that might contain data
    local compressed_files_count=$(find "$backup_path" -name "*.tar.gz" 2>/dev/null | wc -l)
    if [[ $compressed_files_count -gt 0 ]]; then
        log_info "Found $compressed_files_count compressed archive files"
        has_data_files=true
    fi

    if [[ "$has_data_files" == false ]]; then
        log_warn "No recognizable data files found in backup"
        ((validation_errors++))
    fi

    # Check overall backup size (should be reasonable)
    local backup_size=$(du -sb "$backup_path" 2>/dev/null | cut -f1)
    if [[ -n "$backup_size" ]]; then
        if [[ $backup_size -lt $((100 * 1024)) ]]; then # Less than 100KB
            log_warn "Physical backup suspiciously small: $(du -sh "$backup_path" | cut -f1)"
            ((validation_errors++))
        else
            log_info "Backup size appears reasonable: $(du -sh "$backup_path" | cut -f1)"
        fi
    fi

    if [[ $validation_errors -eq 0 ]]; then
        log_info "Physical backup validation passed"
        return 0
    else
        log_error "Physical backup validation failed with $validation_errors errors"
        return 1
    fi
}

# Main validation function
validate_backup() {
    local backup_type="$1"
    local backup_path="$2"

    log_info "Starting backup validation for $backup_type backup"
    local validation_start_time=$(date +%s)

    case "$backup_type" in
    logical)
        if validate_logical_backup "$backup_path"; then
            log_info "Logical backup validation successful"
            return 0
        else
            log_error "Logical backup validation failed"
            return 1
        fi
        ;;
    physical)
        if validate_physical_backup "$backup_path"; then
            log_info "Physical backup validation successful"
            return 0
        else
            log_error "Physical backup validation failed"
            return 1
        fi
        ;;
    *)
        log_error "Unknown backup type for validation: $backup_type"
        return 1
        ;;
    esac

    local validation_end_time=$(date +%s)
    local validation_duration=$((validation_end_time - validation_start_time))
    log_info "Backup validation completed in ${validation_duration} seconds"
}

# List available backups
list_backups() {
    local backup_dir="${BACKUP_DIRECTORY:-$BACKUP_HOME}"

    echo "=== Available Backups ==="
    echo

    if [[ -d "$backup_dir/logical" ]] && [[ -n "$(ls -A "$backup_dir/logical" 2>/dev/null)" ]]; then
        echo "Logical Backups:"
        ls -lh "$backup_dir/logical"/*.sql.gz 2>/dev/null | awk '{print "  "$9" ("$5", "$6" "$7" "$8")"}'
        echo
    fi

    if [[ -d "$backup_dir/physical" ]] && [[ -n "$(ls -A "$backup_dir/physical" 2>/dev/null)" ]]; then
        echo "Physical Backups:"
        for dir in "$backup_dir/physical"/basebackup_*; do
            if [[ -d "$dir" ]]; then
                local size=$(du -sh "$dir" | cut -f1)
                local date=$(stat -c %y "$dir" | cut -d' ' -f1-2)
                echo "  $(basename "$dir") ($size, $date)"
            fi
        done
        echo
    fi

    echo "Total backup directory size: $(du -sh "$backup_dir" | cut -f1)"
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

main() {
    local backup_type="$DEFAULT_BACKUP_TYPE"
    local database=""
    local retention_days="$DEFAULT_RETENTION_DAYS"
    local cleanup_only=false
    local list_only=false
    local validate_path=""
    local validate_new_backup=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
        -t | --type)
            backup_type="$2"
            shift 2
            ;;
        -d | --database)
            database="$2"
            shift 2
            ;;
        -r | --retention)
            retention_days="$2"
            shift 2
            ;;
        -c | --cleanup)
            cleanup_only=true
            shift
            ;;
        -l | --list)
            list_only=true
            shift
            ;;
        --validate)
            validate_new_backup=true
            shift
            ;;
        --validate-existing)
            validate_path="$2"
            shift 2
            ;;
        -h | --help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
        esac
    done

    # Validate backup type
    if [[ "$backup_type" != "logical" && "$backup_type" != "physical" ]]; then
        log_error "Invalid backup type: $backup_type. Must be 'logical' or 'physical'"
        exit 1
    fi

    # Handle list-only mode
    if [[ "$list_only" == true ]]; then
        list_backups
        exit 0
    fi

    # Handle validate-only mode
    if [[ -n "$validate_path" ]]; then
        setup_backup_directories

        # Determine backup type from file extension/path
        local backup_type_to_validate=""
        if [[ "$validate_path" == *.sql.gz ]] || [[ "$validate_path" == *.sql ]]; then
            backup_type_to_validate="logical"
        elif [[ -d "$validate_path" ]] && [[ "$(basename "$validate_path")" == basebackup_* ]]; then
            backup_type_to_validate="physical"
        else
            log_error "Cannot determine backup type for: $validate_path"
            log_error "Logical backups should be .sql.gz files, physical backups should be basebackup_* directories"
            exit 1
        fi

        if validate_backup "$backup_type_to_validate" "$validate_path"; then
            log_info "Backup validation completed successfully"
            exit 0
        else
            log_error "Backup validation failed"
            exit 1
        fi
    fi

    # Check environment
    if ! check_environment; then
        exit 1
    fi

    # Setup directories
    setup_backup_directories

    # Test database connection
    if ! test_connection; then
        exit 1
    fi

    # Perform cleanup
    cleanup_old_backups "$retention_days"

    # Exit if cleanup-only mode
    if [[ "$cleanup_only" == true ]]; then
        log_info "Cleanup completed"
        exit 0
    fi

    # Perform backup
    log_info "Starting $backup_type backup process"
    local backup_start_time=$(date +%s)

    case "$backup_type" in
    logical)
        if logical_backup "$database" "$validate_new_backup"; then
            log_info "Logical backup completed successfully"
        else
            log_error "Logical backup failed"
            exit 1
        fi
        ;;
    physical)
        if [[ -n "$database" ]]; then
            log_warn "Database parameter ignored for physical backups"
        fi
        if physical_backup "$validate_new_backup"; then
            log_info "Physical backup completed successfully"
        else
            log_error "Physical backup failed"
            exit 1
        fi
        ;;
    esac

    local backup_end_time=$(date +%s)
    local backup_duration=$((backup_end_time - backup_start_time))

    log_info "Backup process completed in ${backup_duration} seconds"
}

# Execute main function with all arguments
main "$@"
