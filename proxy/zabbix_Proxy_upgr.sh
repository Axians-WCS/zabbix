#!/bin/bash

# Define variables
ZABBIX_URL="https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest+ubuntu22.04_all.deb"
ZABBIX_DEB="zabbix-release_latest+ubuntu22.04_all.deb"
MARIADB_CONF="/etc/mysql/mariadb.conf.d/zbxupgrade.cnf"
LOG_FILE="/var/log/zabbix_upgrade.log"
SERVICES=("zabbix-proxy" "mariadb" "zabbix-agent2")

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

# Function to check if services are running
check_services() {
    for service in "${SERVICES[@]}"; do
        if systemctl is-active --quiet $service; then
            log "$service is running."
        else
            log "$service is not running."
            exit 1
        fi
    done
}

# Stop Zabbix services
log "Stopping Zabbix services..."
systemctl stop zabbix-* || { log "Failed to stop Zabbix services"; exit 1; }

# Remove old Zabbix repository list
log "Removing old Zabbix repository list..."
rm -rf /etc/apt/sources.list.d/zabbix.list || { log "Failed to remove old Zabbix repository list"; exit 1; }

# Download the latest Zabbix release package
log "Downloading the latest Zabbix release package..."
wget -O $ZABBIX_DEB $ZABBIX_URL || { log "Failed to download Zabbix release package"; exit 1; }

# Install the Zabbix release package
log "Installing the Zabbix release package..."
dpkg --force-confnew -i $ZABBIX_DEB || { log "Failed to install Zabbix release package"; exit 1; }

# Clean up the downloaded package
log "Cleaning up the downloaded package..."
rm -rf $ZABBIX_DEB || { log "Failed to remove downloaded package"; exit 1; }

# Update MariaDB configuration
log "Updating MariaDB configuration..."
echo -e "[mariadb]\nlog_bin_trust_function_creators=ON" | tee -a $MARIADB_CONF || { log "Failed to update MariaDB configuration"; exit 1; }

# Restart MariaDB service
log "Restarting MariaDB service..."
systemctl restart mariadb || { log "Failed to restart MariaDB service"; exit 1; }

# Update package lists
log "Updating package lists..."
apt-get update || { log "Failed to update package lists"; exit 1; }

# Upgrade Zabbix packages
log "Upgrading Zabbix packages..."
apt-get install --only-upgrade zabbix.* -y || { log "Failed to upgrade Zabbix packages"; exit 1; }

# Start Zabbix services
log "Starting Zabbix services..."
systemctl start zabbix-proxy zabbix-agent2 || { log "Failed to start Zabbix services"; exit 1; }

# Remove temporary MariaDB configuration
log "Removing temporary MariaDB configuration..."
rm -rf $MARIADB_CONF || { log "Failed to remove temporary MariaDB configuration"; exit 1; }

# Restart Zabbix proxy and MariaDB services
log "Restarting Zabbix proxy and MariaDB services..."
systemctl stop zabbix-proxy || { log "Failed to stop Zabbix proxy"; exit 1; }
systemctl restart mariadb || { log "Failed to restart MariaDB service"; exit 1; }
systemctl start zabbix-proxy || { log "Failed to start Zabbix proxy"; exit 1; }

# Check if all services are running
log "Checking if all services are running..."
check_services

log "Zabbix upgrade completed successfully."