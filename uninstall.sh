#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}System Metrics Exporter Uninstallation${NC}"
echo "----------------------------------------"

echo -e "${YELLOW}Step 1: Stopping service...${NC}"
if sudo systemctl is-active --quiet node-metrics-exporter; then
    sudo systemctl stop node-metrics-exporter
    echo -e "${GREEN}✓ Service stopped${NC}"
else
    echo -e "${GREEN}✓ Service was not running${NC}"
fi

echo -e "${YELLOW}Step 2: Disabling service...${NC}"
sudo systemctl disable node-metrics-exporter
echo -e "${GREEN}✓ Service disabled${NC}"

echo -e "${YELLOW}Step 3: Removing service file...${NC}"
sudo rm -f /etc/systemd/system/node-metrics-exporter.service
echo -e "${GREEN}✓ Service file removed${NC}"

echo -e "${YELLOW}Step 4: Reloading systemd...${NC}"
sudo systemctl daemon-reload
echo -e "${GREEN}✓ Systemd reloaded${NC}"

echo -e "${YELLOW}Step 5: Removing binary...${NC}"
sudo rm -f /usr/local/bin/node-metrics-exporter
echo -e "${GREEN}✓ Binary removed${NC}"

echo -e "${YELLOW}Step 6: Removing configuration...${NC}"
sudo rm -rf /var/lib/vpn-metrics
echo -e "${GREEN}✓ Configuration removed${NC}"

echo -e "${GREEN}Uninstallation completed successfully!${NC}" 