#!/bin/bash

# One-liner installation command:
# curl -s https://raw.githubusercontent.com/suzzukin/system-metrics-exporter/main/install.sh | sudo bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to validate URL
validate_url() {
    if [[ "$1" == http://* || "$1" == https://* ]]; then
        return 0
    else
        return 1
    fi
}

# Function to check if service exists
check_service_exists() {
    systemctl list-unit-files | grep -q "node-metrics-exporter.service"
}

echo -e "${YELLOW}System Metrics Exporter Installation${NC}"
echo "===================================="

# Get URL and token from user
while true; do
    read -p "Enter the server URL (e.g., https://your-server.com): " SERVER_URL < /dev/tty
    if validate_url "$SERVER_URL"; then
        break
    else
        echo -e "${RED}Invalid URL format. Please try again.${NC}"
    fi
done

while true; do
    read -p "Enter the API token: " API_TOKEN < /dev/tty
    if [[ -n "$API_TOKEN" ]]; then
        break
    else
        echo -e "${RED}Token cannot be empty. Please try again.${NC}"
    fi
done

# Check if updating existing installation
if check_service_exists; then
    echo -e "${YELLOW}Updating existing installation...${NC}"
    sudo systemctl stop node-metrics-exporter
fi

# Check dependencies
echo -e "${YELLOW}Checking dependencies...${NC}"
if ! command -v git &> /dev/null; then
    echo -e "${YELLOW}Git not found. Attempting to install...${NC}"
    sudo apt-get update -qq && sudo apt-get install -y git || { echo -e "${RED}Failed to install git via apt-get.${NC}"; exit 1; }
fi

if ! command -v go &> /dev/null; then
    echo -e "${YELLOW}Installing Go...${NC}"
    wget -q "https://go.dev/dl/go1.21.0.linux-amd64.tar.gz" -O /tmp/go.tar.gz
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf /tmp/go.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    rm /tmp/go.tar.gz
    echo -e "${GREEN}✓ Go installed${NC}"
fi

if ! command -v speedtest-cli &> /dev/null; then
    echo -e "${YELLOW}Installing speedtest-cli...${NC}"
    sudo apt-get update -qq && sudo apt-get install -y speedtest-cli
    echo -e "${GREEN}✓ speedtest-cli installed${NC}"
fi

# Build application
echo -e "${YELLOW}Building application...${NC}"
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
git clone -q https://github.com/suzzukin/system-metrics-exporter.git
cd system-metrics-exporter

# Use Go from /usr/local/go/bin if not in PATH
if ! command -v go &> /dev/null && [ -f "/usr/local/go/bin/go" ]; then
    /usr/local/go/bin/go build -o node-metrics-exporter
else
    go build -o node-metrics-exporter
fi

sudo cp node-metrics-exporter /usr/local/bin/
echo -e "${GREEN}✓ Application built and installed${NC}"

# Create configuration
echo -e "${YELLOW}Creating configuration...${NC}"
sudo mkdir -p /var/lib/vpn-metrics
sudo tee /var/lib/vpn-metrics/config.json > /dev/null << EOF
{
    "server_url": "$SERVER_URL",
    "api_token": "$API_TOKEN",
    "report_interval": 300
}
EOF
echo -e "${GREEN}✓ Configuration created${NC}"

# Create systemd service
echo -e "${YELLOW}Setting up service...${NC}"
sudo cp ./node-metrics-exporter.service /etc/systemd/system/node-metrics-exporter.service

# Start service
sudo systemctl daemon-reload
sudo systemctl enable node-metrics-exporter
sudo systemctl start node-metrics-exporter

# Cleanup
cd - > /dev/null
rm -rf "$TEMP_DIR"

echo -e "${GREEN}✓ Installation completed successfully!${NC}"
echo -e "${YELLOW}Check status: sudo systemctl status node-metrics-exporter${NC}"
echo -e "${YELLOW}View logs: sudo journalctl -u node-metrics-exporter -f${NC}"