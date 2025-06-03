FROM debian:bullseye-slim

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    BACKUP_HOME=/var/lib/backups \
    BACKUP_LOG_DIR=/var/log/backups \
    PGPASSFILE=/var/lib/backups/.pgpass

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg2 \
    lsb-release \
    cron \
    gosu \
    procps \
    gzip \
    apt-transport-https && \
    rm -rf /var/lib/apt/lists/*

# Add PostgreSQL repository for latest psql client tools
RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/postgresql-archive-keyring.gpg] http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" >/etc/apt/sources.list.d/pgdg.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        postgresql-client-15 && \
    rm -rf /var/lib/apt/lists/*

# Create backup user and group
RUN groupadd -r backups && \
    useradd -r -g backups -d /var/lib/backups -s /bin/bash backups

# Create required directories
RUN mkdir -p ${BACKUP_HOME} ${BACKUP_LOG_DIR} /opt/backup/scripts && \
    touch ${BACKUP_LOG_DIR}/backup.log && \
    chown -R backups:backups ${BACKUP_HOME} ${BACKUP_LOG_DIR} /opt/backup

# Set up entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create mount points for volumes
VOLUME ["${BACKUP_HOME}", "${BACKUP_LOG_DIR}"]

# Set working directory
WORKDIR ${BACKUP_HOME}

# Define entrypoint
ENTRYPOINT ["/entrypoint.sh"]

# Default command - just keep container running
CMD ["tail", "-f", "/var/log/backups/backup.log"] 