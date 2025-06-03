#!/bin/bash

# Simple PostgreSQL Backup Service Entrypoint Script
# This script configures and starts a simple PostgreSQL backup service

set -euo pipefail # Exit on error, undefined vars, and pipe failures

# =============================================================================
# CONSTANTS AND DEFAULTS
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly BACKUP_USER="backups"
readonly BACKUP_GROUP="backups"
readonly BACKUP_HOME="/var/lib/backups"
readonly BACKUP_LOG_DIR="/var/log/backups"

# Default environment variables
readonly DEFAULT_LOG_LEVEL="INFO"
readonly DEFAULT_BACKUP_DIRECTORY="/var/lib/backups"
readonly DEFAULT_RETENTION_DAYS="7"
readonly DEFAULT_DB_PORT="5432"
readonly DEFAULT_DB_DATABASE="postgres"
readonly DEFAULT_DB_SUPERUSER="postgres"

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME] $*" >&2
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

# Set ownership and permissions safely
set_ownership_and_permissions() {
    local path="$1"
    local owner="$2"
    local permissions="$3"

    if [[ ! -e "$path" ]]; then
        log_warn "Path does not exist, skipping: $path"
        return 0
    fi

    # Test if the path is writable (not read-only mounted)
    if ! touch "$path/.write_test" 2>/dev/null; then
        log_info "Path $path appears to be read-only mounted, skipping ownership/permission changes"
        return 0
    else
        # Clean up test file
        rm -f "$path/.write_test" 2>/dev/null || true
    fi

    log_info "Setting ownership of $path to $owner"
    if ! chown -R "$owner" "$path" 2>/dev/null; then
        log_warn "Failed to change ownership of $path (may be read-only)"
        return 0
    fi

    log_info "Setting permissions of $path to $permissions"
    if ! chmod -R "$permissions" "$path" 2>/dev/null; then
        log_warn "Failed to change permissions of $path (may be read-only)"
        return 0
    fi
}

# =============================================================================
# CONFIGURATION FUNCTIONS
# =============================================================================

# Set up environment variables with defaults
setup_environment() {
    log_info "Setting up environment variables"

    export BACKUP_LOG_LEVEL="${BACKUP_LOG_LEVEL:-$DEFAULT_LOG_LEVEL}"
    export BACKUP_DIRECTORY="${BACKUP_DIRECTORY:-$DEFAULT_BACKUP_DIRECTORY}"
    export BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-$DEFAULT_RETENTION_DAYS}"

    log_info "Environment configured:"
    log_info "  Log Level: $BACKUP_LOG_LEVEL"
    log_info "  Backup Directory: $BACKUP_DIRECTORY"
    log_info "  Retention Days: $BACKUP_RETENTION_DAYS"
    log_info "  PGPASSFILE: ${PGPASSFILE:-'(not set yet)'}"
}

# Setup PostgreSQL password file
setup_pgpass() {
    local pgpass_file="${BACKUP_HOME}/.pgpass"

    # Check if database password is provided
    if [[ -z "${DB_SUPERUSER_PASSWORD:-}" ]]; then
        log_error "DB_SUPERUSER_PASSWORD not provided, cannot create .pgpass file"
        return 1
    fi

    if [[ -z "${DB_HOST:-}" ]]; then
        log_error "DB_HOST not provided, cannot create .pgpass entries"
        return 1
    fi

    log_info "Setting up .pgpass file"

    # Create and secure .pgpass file
    touch "$pgpass_file"
    chmod 600 "$pgpass_file"
    set_ownership_and_permissions "$pgpass_file" "$BACKUP_USER:$BACKUP_GROUP" "600"

    # Add database credentials
    local db_port="${DB_PORT:-$DEFAULT_DB_PORT}"
    local db_database="${DB_SUPERUSER_DATABASE:-$DEFAULT_DB_DATABASE}"
    local db_superuser="${DB_SUPERUSER:-$DEFAULT_DB_SUPERUSER}"

    echo "${DB_HOST}:${db_port}:*:${db_superuser}:${DB_SUPERUSER_PASSWORD}" >"$pgpass_file"
    log_info "Added database credentials to .pgpass"
}

# Setup directory permissions
setup_directory_permissions() {
    log_info "Setting up directory permissions"

    # Create backup directory if it doesn't exist
    if [[ ! -d "$BACKUP_DIRECTORY" ]]; then
        mkdir -p "$BACKUP_DIRECTORY"
    fi

    # Set proper ownership and permissions
    set_ownership_and_permissions "$BACKUP_DIRECTORY" "$BACKUP_USER:$BACKUP_GROUP" "755"
    set_ownership_and_permissions "$BACKUP_LOG_DIR" "$BACKUP_USER:$BACKUP_GROUP" "755"
}

# Test database connection
test_database_connection() {
    log_info "Testing database connection"

    local db_host="${DB_HOST:-}"
    local db_port="${DB_PORT:-$DEFAULT_DB_PORT}"
    local db_database="${DB_SUPERUSER_DATABASE:-$DEFAULT_DB_DATABASE}"
    local db_superuser="${DB_SUPERUSER:-$DEFAULT_DB_SUPERUSER}"

    if [[ -z "$db_host" ]]; then
        log_error "DB_HOST not provided, cannot test connection"
        return 1
    fi

    # Test connection as backup user
    if ! gosu "$BACKUP_USER" psql -h "$db_host" -p "$db_port" -U "$db_superuser" -d "$db_database" -c "SELECT 1;" >/dev/null 2>&1; then
        log_error "Failed to connect to database at $db_host:$db_port"
        log_error "Please verify database credentials and network connectivity"
        return 1
    fi

    log_info "Database connection test successful"
    return 0
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log_info "Starting PostgreSQL backup service initialization"

    # Setup environment
    setup_environment

    # Setup directories and permissions
    setup_directory_permissions

    # Setup database credentials
    setup_pgpass

    # Test database connection
    if ! test_database_connection; then
        log_error "Database connection test failed, exiting"
        exit 1
    fi

    log_info "Backup service initialized successfully"

    # Execute provided command or default
    if [[ $# -gt 0 ]]; then
        log_info "Executing command: $*"
        exec "$@"
    else
        log_info "No command provided, running default command"
        exec tail -f "$BACKUP_LOG_DIR/backup.log"
    fi
}

# Run main function with all arguments
main "$@"
