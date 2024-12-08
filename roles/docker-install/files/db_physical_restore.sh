#!/usr/bin/env bash
set -euo pipefail

# Script to restore a database backup into a Docker container.
# Supports MariaDB, MySQL, and PostgreSQL.

# Check if the required arguments are provided
if [[ $# -ne 5 ]]; then
  echo "Usage: $0 <container_name> <database_type> <backup_path> <db_user> <db_password>"
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

# Validate the backup path
if [[ ! -d "$BACKUP_PATH" ]]; then
  echo "Error: Backup path '${BACKUP_PATH}' does not exist."
  exit 1
fi

# Function to restore MariaDB
restore_mariadb() {
  echo "Starting MariaDB restore..."

  # Copy the backup to the container
  docker cp "$BACKUP_PATH" "$CONTAINER_NAME:/tmp/backup"

  # Prepare and restore the backup
  docker exec -e MYSQL_PWD="$DB_PASSWORD" "$CONTAINER_NAME" \
    mariabackup --prepare --target-dir="/tmp/backup" || {
    echo "Error: MariaDB prepare step failed."
    exit 1
  }

  docker exec -e MYSQL_PWD="$DB_PASSWORD" "$CONTAINER_NAME" \
    mariabackup --copy-back --target-dir="/tmp/backup" || {
    echo "Error: MariaDB restore step failed."
    exit 1
  }

  docker exec "$CONTAINER_NAME" chown -R mysql:mysql /var/lib/mysql

  echo "MariaDB restore completed successfully."
}

# Function to restore MySQL
restore_mysql() {
  echo "Starting MySQL restore..."

  # Copy the SQL backup file to the container
  SQL_FILE="$BACKUP_PATH/mysql_backup.sql"
  if [[ ! -f "$SQL_FILE" ]]; then
    echo "Error: MySQL backup file '${SQL_FILE}' does not exist."
    exit 1
  fi

  docker cp "$SQL_FILE" "$CONTAINER_NAME:/tmp/mysql_backup.sql"

  # Restore the database
  docker exec -e MYSQL_PWD="$DB_PASSWORD" "$CONTAINER_NAME" \
    sh -c "mysql -u $DB_USER < /tmp/mysql_backup.sql" || {
    echo "Error: MySQL restore command failed."
    exit 1
  }

  echo "MySQL restore completed successfully."
}

# Function to restore PostgreSQL
restore_postgres() {
  echo "Starting PostgreSQL restore..."

  # Copy the backup to the container
  docker cp "$BACKUP_PATH" "$CONTAINER_NAME:/tmp/backup"

  # Stop the PostgreSQL service before restoring
  docker exec "$CONTAINER_NAME" pg_ctl stop -D /var/lib/postgresql/data || {
    echo "Error: Failed to stop PostgreSQL service."
    exit 1
  }

  # Remove existing data and restore from backup
  docker exec "$CONTAINER_NAME" rm -rf /var/lib/postgresql/data/*
  docker exec "$CONTAINER_NAME" cp -r /tmp/backup/* /var/lib/postgresql/data/

  # Fix ownership
  docker exec "$CONTAINER_NAME" chown -R postgres:postgres /var/lib/postgresql/data

  # Start the PostgreSQL service
  docker exec "$CONTAINER_NAME" pg_ctl start -D /var/lib/postgresql/data || {
    echo "Error: Failed to start PostgreSQL service."
    exit 1
  }

  echo "PostgreSQL restore completed successfully."
}

# Perform the restore based on the database type
case "$DB_TYPE" in
  mariadb)
    restore_mariadb
    ;;
  mysql)
    restore_mysql
    ;;
  postgres)
    restore_postgres
    ;;
  *)
    echo "Error: Unsupported database type '${DB_TYPE}'. Supported types are mariadb, mysql, and postgres."
    exit 1
    ;;
esac

echo "Restore completed successfully."
