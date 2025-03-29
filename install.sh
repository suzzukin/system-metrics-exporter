#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}System Metrics Exporter Installation${NC}"
echo "----------------------------------------"

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo -e "${RED}Git is not installed. Please install Git first.${NC}"
    exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed. Please install Docker first.${NC}"
    exit 1
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Clone repository
echo -e "${YELLOW}Cloning repository...${NC}"
git clone https://github.com/suzzukin/system-metrics-exporter.git
cd system-metrics-exporter

# Get URL for metrics endpoint
read -p "Enter the URL where metrics will be sent (e.g., http://example.com/metrics): " METRICS_URL

# Create config directory
CONFIG_DIR="/var/lib/vpn-metrics"
if [ ! -d "$CONFIG_DIR" ]; then
    sudo mkdir -p "$CONFIG_DIR"
fi

# Create config file
CONFIG_FILE="$CONFIG_DIR/config.json"
cat > "$CONFIG_FILE" << EOF
{
    "url": "$METRICS_URL"
}
EOF

# Build Docker image
echo -e "${YELLOW}Building Docker image...${NC}"
docker build -t node-metrics-exporter .

# Create systemd service file
SERVICE_FILE="/etc/systemd/system/node-metrics-exporter.service"
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Node Metrics Exporter
Requires=docker.service
After=docker.service

[Service]
ExecStart=/usr/bin/docker run \\
    --name node-metrics-exporter \\
    -v /var/lib/vpn-metrics:/var/lib/vpn-metrics \\
    -v /proc:/proc:ro \\
    -v /sys:/sys:ro \\
    --net=host \\
    node-metrics-exporter
ExecStop=/usr/bin/docker stop node-metrics-exporter
ExecStopPost=/usr/bin/docker rm node-metrics-exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start service
echo -e "${YELLOW}Starting service...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable node-metrics-exporter
sudo systemctl start node-metrics-exporter

# Check service status
if sudo systemctl is-active --quiet node-metrics-exporter; then
    echo -e "${GREEN}Installation completed successfully!${NC}"
    echo -e "${GREEN}Service is running.${NC}"
    echo -e "You can check the status with: ${YELLOW}sudo systemctl status node-metrics-exporter${NC}"
    echo -e "Or check Docker container with: ${YELLOW}docker ps | grep node-metrics-exporter${NC}"
else
    echo -e "${RED}Service failed to start.${NC}"
    echo -e "Check the logs with: ${YELLOW}sudo journalctl -u node-metrics-exporter${NC}"
    echo -e "Or check Docker logs with: ${YELLOW}docker logs node-metrics-exporter${NC}"
    exit 1
fi

# Cleanup
cd - > /dev/null
rm -rf "$TEMP_DIR"