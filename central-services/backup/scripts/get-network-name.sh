#!/bin/bash
# Script to dynamically determine the Docker network name for the backup service

if [ ! -z "${BACKUP_NETWORK_NAME}" ]; then
  echo "${BACKUP_NETWORK_NAME}"
  exit 0
fi

docker network ls --format '{{.Name}}' | grep relife-supabase | head -n 1
