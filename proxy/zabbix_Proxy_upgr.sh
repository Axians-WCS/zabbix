#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Define variables
readonly ZABBIX_URL="https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.4+ubuntu22.04_all.deb"
readonly ZABBIX_DEB="/tmp/zabbix-release_latest+ubuntu22.04_all.deb"
readonly MARIADB_CONF="/etc/mysql/mariadb.conf.d/zbxupgrade.cnf"
readonly LOG_FILE="/var/log/zabbix_upgrade.log"
readonly SERVICES=("zabbix-proxy" "mariadb" "zabbix-agent2")

# Ensure log file exists
touch "$LOG_FILE"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

# Function to check if services are running
check_services() {
    for service in "${SERVICES[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log "$service is running."
        else
            log "ERROR: $service is not running."
            exit 1
        fi
    done
}

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
   log "This script must be run as root"
   exit 1
fi

# Stop Zabbix services
log "Stopping Zabbix services..."
systemctl stop zabbix-* || { log "ERROR: Failed to stop Zabbix services"; exit 1; }

# Remove old Zabbix repository list
log "Removing old Zabbix repository list..."
rm -f /etc/apt/sources.list.d/zabbix.list || { log "ERROR: Failed to remove old Zabbix repository list"; exit 1; }

# Download the latest Zabbix release package
log "Downloading the latest Zabbix release package..."
wget -O "$ZABBIX_DEB" "$ZABBIX_URL" || { log "ERROR: Failed to download Zabbix release package"; exit 1; }

# Install the Zabbix release package
log "Installing the Zabbix release package..."
dpkg --force-confnew -i "$ZABBIX_DEB" || { log "ERROR: Failed to install Zabbix release package"; exit 1; }

# Clean up the downloaded package
log "Cleaning up the downloaded package..."
rm -f "$ZABBIX_DEB" || { log "ERROR: Failed to remove downloaded package"; exit 1; }

# Update MariaDB configuration
log "Updating MariaDB configuration..."
cat <<EOF > "$MARIADB_CONF"
[mariadb]
log_bin_trust_function_creators=ON
EOF

# Restart MariaDB service
log "Restarting MariaDB service..."
systemctl restart mariadb || { log "ERROR: Failed to restart MariaDB service"; exit 1; }

# Update package lists
log "Updating package lists..."
apt-get update || { log "ERROR: Failed to update package lists"; exit 1; }

# Upgrade Zabbix packages
log "Upgrading Zabbix packages..."
apt-get install --only-upgrade "zabbix*" -y || { log "ERROR: Failed to upgrade Zabbix packages"; exit 1; }

# Start Zabbix services
log "Starting Zabbix services..."
systemctl start zabbix-proxy zabbix-agent2 || { log "ERROR: Failed to start Zabbix services"; exit 1; }

# Remove temporary MariaDB configuration
log "Removing temporary MariaDB configuration..."
rm -f "$MARIADB_CONF" || { log "ERROR: Failed to remove temporary MariaDB configuration"; exit 1; }

# Restart Zabbix proxy and MariaDB services
log "Restarting Zabbix proxy and MariaDB services..."
systemctl stop zabbix-proxy || { log "ERROR: Failed to stop Zabbix proxy"; exit 1; }
systemctl restart mariadb || { log "ERROR: Failed to restart MariaDB service"; exit 1; }
systemctl start zabbix-proxy || { log "ERROR: Failed to start Zabbix proxy"; exit 1; }

# Check if all services are running
log "Checking if all services are running..."
check_services

log "Zabbix upgrade completed successfully."