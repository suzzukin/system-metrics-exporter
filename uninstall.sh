#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}System Metrics Exporter Uninstallation${NC}"
echo "======================================"

# Stop and disable service
echo -e "${YELLOW}Removing service...${NC}"
if sudo systemctl is-active --quiet node-metrics-exporter; then
    sudo systemctl stop node-metrics-exporter
fi
sudo systemctl disable node-metrics-exporter 2>/dev/null
sudo rm -f /etc/systemd/system/node-metrics-exporter.service
sudo systemctl daemon-reload
echo -e "${GREEN}✓ Service removed${NC}"

# Remove binary and configuration
echo -e "${YELLOW}Removing files...${NC}"
sudo rm -f /usr/local/bin/node-metrics-exporter
sudo rm -rf /var/lib/vpn-metrics
echo -e "${GREEN}✓ Files removed${NC}"

echo -e "${GREEN}✓ Uninstallation completed successfully!${NC}"