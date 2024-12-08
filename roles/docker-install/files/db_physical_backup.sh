#!/usr/bin/env bash
set -euo pipefail

# Script to create a database backup from a Docker container.
# Supports MariaDB, MySQL, and PostgreSQL.

# Check if the required arguments are provided
if [[ $# -ne 5 ]]; then
  echo "Usage: $0 <container_name> <database_type> <backup_target_path> <db_user> <db_password>"
  echo "Supported database types: mariadb, mysql, postgres"
  exit 1
fi

# Input parameters
CONTAINER_NAME="$1"
DB_TYPE="$2"
BACKUP_PATH="$3"
DB_USER="$4"
DB_PASSWORD="$5"

# Validate the container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Error: Container '${CONTAINER_NAME}' is not running."
  exit 1
fi

# Ensure the backup path exists
if [[ ! -d "$BACKUP_PATH" ]]; then
  echo "Error: Backup path '${BACKUP_PATH}' does not exist."
  exit 1
fi

# Generate a timestamp for the backup
BACKUP_DIR="${BACKUP_PATH}"
TMP_CONTAINER_DIR="/tmp/backup"

# clean up the backup directory
rm -rf "$BACKUP_DIR"/..?* "$BACKUP_DIR"/.[!.]* "$BACKUP_DIR"/* 2>/dev/null || true


# Create the backup directory
mkdir -p "$BACKUP_DIR"


cleanup_tmp_dir() {
  # Remove the temporary directory in the container
  echo "Removing temporary directory in container..."
  docker exec "$CONTAINER_NAME" rm -rf "$TMP_CONTAINER_DIR" || true
}

mkdir_container_tmp() {
  # Remove existing data
  echo "Removing existing data in temporary directory..."
  cleanup_tmp_dir
  
  # Create a temporary directory in the container
  docker exec "$CONTAINER_NAME" mkdir -p "$TMP_CONTAINER_DIR"
}

# Function to back up MariaDB
backup_mariadb() {
  echo "Starting MariaDB physical backup..."
  docker exec -e MYSQL_PWD="$DB_PASSWORD" "$CONTAINER_NAME" \
    mariadb-backup --backup --user="$DB_USER" --target-dir="$TMP_CONTAINER_DIR" || {
    echo "Error: MariaDB backup command failed."
    exit 1
  }

  docker cp "${CONTAINER_NAME}:$TMP_CONTAINER_DIR/" "${BACKUP_DIR}" || {
    echo "Error: Failed to copy backup from container."
    exit 1
  }

  # Move file up one level
  mv "${BACKUP_DIR}/backup"/* "${BACKUP_DIR}/"
  rmdir "${BACKUP_DIR}/backup"

  echo "MariaDB backup completed successfully."
}

# Function to back up MySQL
backup_mysql() {
  echo "Starting MySQL logical backup..."
  docker exec -e MYSQL_PWD="$DB_PASSWORD" "$CONTAINER_NAME" \
    sh -c "mysqldump --all-databases --single-transaction --quick --lock-tables=false -u $DB_USER > /tmp/mysql_backup.sql" || {
    echo "Error: MySQL backup command failed."
    exit 1
  }

  docker cp "${CONTAINER_NAME}:/tmp/mysql_backup.sql" "${BACKUP_DIR}/mysql_backup.sql" || {
    echo "Error: Failed to copy backup from container."
    exit 1
  }

  echo "MySQL backup completed successfully. Backup saved as '${BACKUP_DIR}/mysql_backup.sql'."
}

# Function to back up PostgreSQL
backup_postgres() {
  echo "Starting PostgreSQL physical backup..."
  docker exec -e PGPASSWORD="$DB_PASSWORD" "$CONTAINER_NAME" \
    pg_basebackup -D "$TMP_CONTAINER_DIR" -Fp -Xs -P -U "$DB_USER" || {
    echo "Error: PostgreSQL backup command failed."
    exit 1
  }

  docker cp "${CONTAINER_NAME}:$TMP_CONTAINER_DIR" "${BACKUP_DIR}" || {
    echo "Error: Failed to copy backup from container."
    exit 1
  }

  echo "PostgreSQL backup completed successfully."
}

# Perform the backup based on the database type
case "$DB_TYPE" in
  mariadb)
    mkdir_container_tmp
    backup_mariadb
    cleanup_tmp_dir
    ;;
  mysql)
    mkdir_container_tmp
    backup_mysql
    cleanup_tmp_dir
    ;;
  postgres)
    mkdir_container_tmp
    backup_postgres
    cleanup_tmp_dir
    ;;
  *)
    echo "Error: Unsupported database type '${DB_TYPE}'. Supported types are mariadb, mysql, and postgres."
    exit 1
    ;;
esac

echo "Backup completed successfully. Backup saved to '${BACKUP_DIR}'."
