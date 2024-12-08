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

  # Remove existing data
  echo "Removing existing MariaDB data..."
  docker exec "$CONTAINER_NAME" bash -c 'rm -rf /var/lib/mysql/* /var/lib/mysql/.[!.]*'

  # Prepare and restore the backup
  docker exec -e MYSQL_PWD="$DB_PASSWORD" "$CONTAINER_NAME" \
    mariadb-backup --prepare --target-dir="/tmp/backup" || {
    echo "Error: MariaDB prepare step failed."
    exit 1
  }

  docker exec -e MYSQL_PWD="$DB_PASSWORD" "$CONTAINER_NAME" \
    mariadb-backup --copy-back --target-dir="/tmp/backup" || {
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


  echo "Stopping PostgreSQL service..."
  docker stop "$CONTAINER_NAME"

  # Check mount type of /var/lib/postgresql/data
  TEMP_CONTAINER_NAME="temp-restore-$(date +%s)"
  IMAGE=$(docker inspect --format '{{ .Config.Image }}' "$CONTAINER_NAME")
  MOUNT_TYPE=$(docker inspect --format '{{ range .Mounts }}{{ if eq .Destination "/var/lib/postgresql/data" }}{{ .Type }}{{ end }}{{ end }}' "$CONTAINER_NAME")
  if [[ "$MOUNT_TYPE" == "volume" ]]; then
    VOLUME_NAME=$(docker inspect --format '{{ range .Mounts }}{{ if eq .Destination "/var/lib/postgresql/data" }}{{ .Name }}{{ end }}{{ end }}' "$CONTAINER_NAME")
    docker run -d --name "$TEMP_CONTAINER_NAME" --mount source="$VOLUME_NAME",target=/var/lib/postgresql/data -v "$BACKUP_PATH":/tmp/backup "$IMAGE" tail -f /dev/null
  elif [[ "$MOUNT_TYPE" == "bind" ]]; then
    VOLUME_PATH=$(docker inspect --format '{{ range .Mounts }}{{ if eq .Destination "/var/lib/postgresql/data" }}{{ .Source }}{{ end }}{{ end }}' "$CONTAINER_NAME")
    docker run -d --name "$TEMP_CONTAINER_NAME" -v "$VOLUME_PATH":/var/lib/postgresql/data -v "$BACKUP_PATH":/tmp/backup "$IMAGE" tail -f /dev/null
  fi


  # Remove existing data
  docker exec "$TEMP_CONTAINER_NAME" rm -rf /var/lib/postgresql/data/*

  # Restore the backup using pg_restore
  # Restore the backup using pg_basebackup
  docker exec "$TEMP_CONTAINER_NAME" sh -c "cp -r /tmp/backup/* /var/lib/postgresql/data/"

    # Fix ownership
  docker exec "$TEMP_CONTAINER_NAME" chown -R postgres:postgres /var/lib/postgresql/data

  # Stop the temporary container
  docker stop "$TEMP_CONTAINER_NAME"
  docker rm "$TEMP_CONTAINER_NAME"
  
  echo "Starting PostgreSQL service..."
  docker start "$CONTAINER_NAME"


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
