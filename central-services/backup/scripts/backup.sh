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

# Validation constants
readonly MIN_BACKUP_SIZE_BYTES=1024
readonly MIN_PHYSICAL_BACKUP_SIZE_BYTES=$((100 * 1024))

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

# Get file size in a cross-platform way
get_file_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        # Try Linux stat first, then macOS/BSD stat
        stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Get human-readable file size
get_human_readable_size() {
    local path="$1"
    du -h "$path" 2>/dev/null | cut -f1 || echo "unknown"
}

# Format file date for display
get_file_date() {
    local file="$1"
    # Try GNU date format first, then BSD format
    stat -c "%y" "$file" 2>/dev/null | cut -d' ' -f1-2 ||
        stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$file" 2>/dev/null ||
        echo "unknown"
}

# Build backup filename/path
build_backup_path() {
    local backup_type="$1"
    local database="${2:-}"
    local backup_dir="${BACKUP_DIRECTORY:-$BACKUP_HOME}/$backup_type"

    case "$backup_type" in
    logical)
        if [[ -n "$database" ]]; then
            echo "$backup_dir/${database}_${TIMESTAMP}.sql.gz"
        else
            echo "$backup_dir/all_databases_${TIMESTAMP}.sql.gz"
        fi
        ;;
    physical)
        echo "$backup_dir/basebackup_${TIMESTAMP}"
        ;;
    *)
        log_error "Unknown backup type: $backup_type"
        return 1
        ;;
    esac
}

# Get database connection parameters
get_db_params() {
    echo "${DB_HOST}" "${DB_PORT:-$DEFAULT_DB_PORT}" "${DB_SUPERUSER:-$DEFAULT_DB_SUPERUSER}" "${DB_DATABASE:-$DEFAULT_DB_DATABASE}"
}

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
    DB_DATABASE            Database name for connection test (default: $DEFAULT_DB_DATABASE)
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
    read -r db_host db_port db_user db_name <<<"$(get_db_params)"

    log_info "Testing database connection to $db_host:$db_port"

    # Capture error output for debugging
    local error_output
    if ! error_output=$(psql -h "$db_host" -p "$db_port" -U "$db_user" -d "$db_name" -c "SELECT 1;" 2>&1 >/dev/null); then
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

# =============================================================================
# BACKUP FUNCTIONS
# =============================================================================

# Execute backup command with common error handling
execute_backup_command() {
    local backup_file="$1"
    local backup_command="$2"
    local backup_description="$3"

    log_info "Creating $backup_description"

    if eval "$backup_command"; then
        log_info "Backup completed: $backup_file"
        log_info "Backup size: $(get_human_readable_size "$backup_file")"
        return 0
    else
        log_error "Backup failed: $backup_description"
        rm -rf "$backup_file" 2>/dev/null || true
        return 1
    fi
}

# Perform logical backup using pg_dump/pg_dumpall
logical_backup() {
    local database="${1:-}"
    local validate_flag="${2:-false}"
    read -r db_host db_port db_user _ <<<"$(get_db_params)"

    local backup_file
    backup_file=$(build_backup_path "logical" "$database")

    local backup_command backup_description
    if [[ -n "$database" ]]; then
        backup_command="pg_dump -h '$db_host' -p '$db_port' -U '$db_user' -d '$database' --verbose --no-password --format=plain | gzip > '$backup_file'"
        backup_description="logical backup of database '$database'"
    else
        backup_command="pg_dumpall -h '$db_host' -p '$db_port' -U '$db_user' --verbose --no-password | gzip > '$backup_file'"
        backup_description="logical backup of all databases"
    fi

    if execute_backup_command "$backup_file" "$backup_command" "$backup_description"; then
        if [[ "$validate_flag" == "true" ]]; then
            validate_backup_if_requested "logical" "$backup_file" "$validate_flag"
            return $?
        fi
        return 0
    else
        return 1
    fi
}

# Perform physical backup using pg_basebackup
physical_backup() {
    local validate_flag="${1:-false}"
    read -r db_host db_port db_user _ <<<"$(get_db_params)"

    local backup_path
    backup_path=$(build_backup_path "physical")

    local backup_command="pg_basebackup -h '$db_host' -p '$db_port' -U '$db_user' -D '$backup_path' --format=tar --gzip --progress --verbose --no-password"

    if execute_backup_command "$backup_path" "$backup_command" "physical backup (base backup)"; then
        if [[ "$validate_flag" == "true" ]]; then
            validate_backup_if_requested "physical" "$backup_path" "$validate_flag"
            return $?
        fi
        return 0
    else
        return 1
    fi
}

# Validate backup if requested
validate_backup_if_requested() {
    local backup_type="$1"
    local backup_path="$2"
    local validate_flag="$3"

    if [[ "$validate_flag" == "true" ]]; then
        if [[ "${SKIP_BACKUP_VALIDATION:-false}" == "true" ]]; then
            log_info "Backup validation skipped (SKIP_BACKUP_VALIDATION=true)"
            return 0
        elif validate_backup "$backup_type" "$backup_path"; then
            log_info "Backup validation successful"
            return 0
        else
            log_error "Backup validation failed"
            return 1
        fi
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
        local logical_files
        logical_files=$(find "$backup_dir/logical" -name "*.sql.gz" -mtime +$retention_days 2>/dev/null || true)
        if [[ -n "$logical_files" ]]; then
            local logical_count
            logical_count=$(echo "$logical_files" | wc -l)
            echo "$logical_files" | xargs rm -f
            log_info "Removed $logical_count old logical backup(s)"
        fi
    fi

    # Clean physical backups
    if [[ -d "$backup_dir/physical" ]]; then
        local physical_dirs
        physical_dirs=$(find "$backup_dir/physical" -name "basebackup_*" -type d -mtime +$retention_days 2>/dev/null || true)
        if [[ -n "$physical_dirs" ]]; then
            local physical_count
            physical_count=$(echo "$physical_dirs" | wc -l)
            echo "$physical_dirs" | xargs rm -rf
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
    local initial_size final_size
    initial_size=$(get_file_size "$backup_file")
    sleep 2
    final_size=$(get_file_size "$backup_file")

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

    # Check file size (minimum threshold)
    local file_size
    file_size=$(get_file_size "$backup_file")
    if [[ $file_size -lt $MIN_BACKUP_SIZE_BYTES ]]; then
        log_error "Backup file suspiciously small: ${file_size} bytes"
        ((validation_errors++))
    else
        log_info "Backup file size acceptable: $(get_human_readable_size "$backup_file")"
    fi

    # Simplified content validation
    log_info "Performing basic content validation..."
    if [[ -n "$(gunzip -c "$backup_file" 2>/dev/null | head -1)" ]]; then
        log_info "Backup file can be read and decompressed successfully"

        # Try a simple grep for PostgreSQL indicators
        if [[ -n "$(gunzip -c "$backup_file" 2>/dev/null | head -50 | grep -i "postgresql\|pg_dump\|database" 2>/dev/null)" ]]; then
            log_info "Found PostgreSQL database content indicators"
        else
            log_info "Basic content check completed (no specific indicators found, but file is readable)"
        fi
    else
        log_warn "Could not perform basic content validation, but gzip integrity passed"
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

    # Check for main data files
    local has_data_files=false

    # Check for base.tar.gz or base directory
    if [[ -f "$backup_path/base.tar.gz" ]]; then
        log_info "Found base.tar.gz"
        # Test tar file integrity
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
    local compressed_files_count
    compressed_files_count=$(find "$backup_path" -name "*.tar.gz" 2>/dev/null | wc -l)
    if [[ $compressed_files_count -gt 0 ]]; then
        log_info "Found $compressed_files_count compressed archive files"
        has_data_files=true
    fi

    if [[ "$has_data_files" == false ]]; then
        log_warn "No recognizable data files found in backup"
        ((validation_errors++))
    fi

    # Check overall backup size
    local backup_size
    backup_size=$(du -sb "$backup_path" 2>/dev/null | cut -f1)
    if [[ -n "$backup_size" ]] && [[ $backup_size -lt $MIN_PHYSICAL_BACKUP_SIZE_BYTES ]]; then
        log_warn "Physical backup suspiciously small: $(get_human_readable_size "$backup_path")"
        ((validation_errors++))
    else
        log_info "Backup size appears reasonable: $(get_human_readable_size "$backup_path")"
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
    local validation_start_time validation_end_time validation_duration
    validation_start_time=$(date +%s)

    local result=0
    case "$backup_type" in
    logical)
        if validate_logical_backup "$backup_path"; then
            log_info "Logical backup validation successful"
        else
            log_error "Logical backup validation failed"
            result=1
        fi
        ;;
    physical)
        if validate_physical_backup "$backup_path"; then
            log_info "Physical backup validation successful"
        else
            log_error "Physical backup validation failed"
            result=1
        fi
        ;;
    *)
        log_error "Unknown backup type for validation: $backup_type"
        result=1
        ;;
    esac

    validation_end_time=$(date +%s)
    validation_duration=$((validation_end_time - validation_start_time))
    log_info "Backup validation completed in ${validation_duration} seconds"

    return $result
}

# Determine backup type from file extension/path
detect_backup_type() {
    local backup_path="$1"

    if [[ "$backup_path" == *.sql.gz ]] || [[ "$backup_path" == *.sql ]]; then
        echo "logical"
    elif [[ -d "$backup_path" ]] && [[ "$(basename "$backup_path")" == basebackup_* ]]; then
        echo "physical"
    else
        return 1
    fi
}

# List available backups
list_backups() {
    local backup_dir="${BACKUP_DIRECTORY:-$BACKUP_HOME}"

    echo "=== Available Backups ==="
    echo

    if [[ -d "$backup_dir/logical" ]] && [[ -n "$(ls -A "$backup_dir/logical" 2>/dev/null)" ]]; then
        echo "Logical Backups:"
        for file in "$backup_dir/logical"/*.sql.gz; do
            if [[ -f "$file" ]]; then
                local size date
                size=$(get_human_readable_size "$file")
                date=$(get_file_date "$file")
                echo "  $(basename "$file") ($size, $date)"
            fi
        done
        echo
    fi

    if [[ -d "$backup_dir/physical" ]] && [[ -n "$(ls -A "$backup_dir/physical" 2>/dev/null)" ]]; then
        echo "Physical Backups:"
        for dir in "$backup_dir/physical"/basebackup_*; do
            if [[ -d "$dir" ]]; then
                local size date
                size=$(get_human_readable_size "$dir")
                date=$(get_file_date "$dir")
                echo "  $(basename "$dir") ($size, $date)"
            fi
        done
        echo
    fi

    echo "Total backup directory size: $(get_human_readable_size "$backup_dir")"
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

        local backup_type_to_validate
        if backup_type_to_validate=$(detect_backup_type "$validate_path"); then
            if validate_backup "$backup_type_to_validate" "$validate_path"; then
                log_info "Backup validation completed successfully"
                exit 0
            else
                log_error "Backup validation failed"
                exit 1
            fi
        else
            log_error "Cannot determine backup type for: $validate_path"
            log_error "Logical backups should be .sql.gz files, physical backups should be basebackup_* directories"
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
    local backup_start_time backup_end_time backup_duration
    backup_start_time=$(date +%s)

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

    backup_end_time=$(date +%s)
    backup_duration=$((backup_end_time - backup_start_time))

    log_info "Backup process completed in ${backup_duration} seconds"
}

# Execute main function with all arguments
main "$@"
