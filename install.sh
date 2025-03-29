#!/bin/bash

# One-liner installation command:
# curl -s https://raw.githubusercontent.com/suzzukin/system-metrics-exporter/main/install.sh | sudo bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if service exists
check_service_exists() {
    if systemctl list-unit-files | grep -q "node-metrics-exporter.service"; then
        return 0
    else
        return 1
    fi
}

# Function to backup config
backup_config() {
    if [ -f "/var/lib/vpn-metrics/config.json" ]; then
        echo -e "${YELLOW}Backing up existing configuration...${NC}"
        sudo cp /var/lib/vpn-metrics/config.json /var/lib/vpn-metrics/config.json.bak
        echo -e "${GREEN}✓ Configuration backed up${NC}"
    fi
}

# Function to restore config
restore_config() {
    if [ -f "/var/lib/vpn-metrics/config.json.bak" ]; then
        echo -e "${YELLOW}Restoring configuration...${NC}"
        sudo mv /var/lib/vpn-metrics/config.json.bak /var/lib/vpn-metrics/config.json
        echo -e "${GREEN}✓ Configuration restored${NC}"
    fi
}

# Function to install Go
install_go() {
    echo -e "${YELLOW}Installing Go...${NC}"
    echo -e "${YELLOW}Step 1: Downloading Go 1.24.1...${NC}"
    if ! wget "https://go.dev/dl/go1.24.1.linux-amd64.tar.gz" -O /tmp/go.tar.gz; then
        echo -e "${RED}Failed to download Go.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Go binary downloaded successfully${NC}"

    echo -e "${YELLOW}Step 2: Removing old Go installation...${NC}"
    sudo rm -rf /usr/local/go
    echo -e "${GREEN}✓ Old Go installation removed${NC}"

    echo -e "${YELLOW}Step 3: Extracting Go to /usr/local...${NC}"
    if ! sudo tar -C /usr/local -xzf /tmp/go.tar.gz; then
        echo -e "${RED}Failed to extract Go.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Go extracted successfully${NC}"

    echo -e "${YELLOW}Step 4: Setting up Go in PATH...${NC}"
    # Add Go to PATH for root user
    if ! grep -q "export PATH=\$PATH:/usr/local/go/bin" /root/.bashrc; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /root/.bashrc
        echo -e "${GREEN}✓ Added Go to PATH in /root/.bashrc${NC}"
    else
        echo -e "${GREEN}✓ Go already in PATH${NC}"
    fi

    # Add Go to PATH for current user
    if ! grep -q "export PATH=\$PATH:/usr/local/go/bin" ~/.bashrc; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
        echo -e "${GREEN}✓ Added Go to PATH in ~/.bashrc${NC}"
    fi

    echo -e "${YELLOW}Step 5: Updating current shell PATH...${NC}"
    export PATH=$PATH:/usr/local/go/bin
    echo -e "${GREEN}✓ PATH updated${NC}"

    echo -e "${YELLOW}Step 6: Verifying Go installation...${NC}"
    if ! command -v go &> /dev/null; then
        echo -e "${RED}Go installation failed.${NC}"
        echo -e "${YELLOW}Trying to use Go directly from /usr/local/go/bin/go...${NC}"
        if [ -f "/usr/local/go/bin/go" ]; then
            echo -e "${GREEN}✓ Found Go binary at /usr/local/go/bin/go${NC}"
            # Create a temporary alias for the current session
            alias go="/usr/local/go/bin/go"
        else
            echo -e "${RED}Go binary not found at /usr/local/go/bin/go${NC}"
            exit 1
        fi
    fi
    echo -e "${GREEN}✓ Go installation verified${NC}"

    echo -e "${YELLOW}Step 7: Cleaning up temporary files...${NC}"
    rm /tmp/go.tar.gz
    echo -e "${GREEN}✓ Temporary files cleaned up${NC}"

    echo -e "${GREEN}Go installed successfully!${NC}"
}

echo -e "${YELLOW}System Metrics Exporter Installation${NC}"
echo "----------------------------------------"

# Check if service exists
if check_service_exists; then
    echo -e "${YELLOW}Existing installation found. Updating...${NC}"
    echo -e "${YELLOW}Step 1: Stopping service...${NC}"
    sudo systemctl stop node-metrics-exporter
    echo -e "${GREEN}✓ Service stopped${NC}"

    # Backup existing config
    backup_config
fi

echo -e "${YELLOW}Step 2: Checking Git installation...${NC}"
if ! command -v git &> /dev/null; then
    echo -e "${RED}Git is not installed. Please install Git first.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Git is installed${NC}"

echo -e "${YELLOW}Step 3: Checking Go installation...${NC}"
if ! command -v go &> /dev/null; then
    echo -e "${YELLOW}Go is not installed. Installing Go...${NC}"
    install_go
else
    echo -e "${GREEN}✓ Go is already installed${NC}"
fi

echo -e "${YELLOW}Step 4: Installing speedtest-cli...${NC}"
if ! command -v speedtest-cli &> /dev/null; then
    echo -e "${YELLOW}Installing speedtest-cli...${NC}"
    if ! sudo apt-get update; then
        echo -e "${RED}Failed to update package list.${NC}"
        exit 1
    fi
    if ! sudo apt-get install -y speedtest-cli; then
        echo -e "${RED}Failed to install speedtest-cli.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ speedtest-cli installed successfully${NC}"
else
    echo -e "${GREEN}✓ speedtest-cli is already installed${NC}"
fi

echo -e "${YELLOW}Step 5: Creating temporary directory...${NC}"
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
echo -e "${GREEN}✓ Created temporary directory: $TEMP_DIR${NC}"

echo -e "${YELLOW}Step 6: Cloning repository...${NC}"
git clone https://github.com/suzzukin/system-metrics-exporter.git
cd system-metrics-exporter
echo -e "${GREEN}✓ Repository cloned successfully${NC}"

# Always ask for URL and token
echo -e "${YELLOW}Step 7: Configuring metrics endpoint...${NC}"
read -p "Enter the URL where metrics will be sent (e.g., http://example.com/metrics): " METRICS_URL
echo -e "${GREEN}✓ Metrics endpoint configured: $METRICS_URL${NC}"

echo -e "${YELLOW}Step 8: Configuring JWT token...${NC}"
read -p "Enter the JWT token for authentication (press Enter to skip): " JWT_TOKEN
echo -e "${GREEN}✓ JWT token configured${NC}"

echo -e "${YELLOW}Step 9: Setting up configuration directory...${NC}"
CONFIG_DIR="/var/lib/vpn-metrics"
if [ ! -d "$CONFIG_DIR" ]; then
    sudo mkdir -p "$CONFIG_DIR"
    echo -e "${GREEN}✓ Created config directory: $CONFIG_DIR${NC}"
else
    echo -e "${GREEN}✓ Config directory already exists${NC}"
fi

# Only create new config if no existing config
if [ ! -f "$CONFIG_DIR/config.json" ]; then
    echo -e "${YELLOW}Step 10: Creating configuration file...${NC}"
    CONFIG_FILE="$CONFIG_DIR/config.json"

    # Create JSON configuration using echo and jq for proper JSON escaping
    echo "{
        \"url\": \"$METRICS_URL\",
        \"token\": \"$JWT_TOKEN\"
    }" > "$CONFIG_FILE"

    echo -e "${GREEN}✓ Configuration file created${NC}"
else
    echo -e "${YELLOW}Step 10: Preserving existing configuration...${NC}"
    restore_config
    echo -e "${GREEN}✓ Existing configuration restored${NC}"
fi

echo -e "${YELLOW}Step 11: Building application...${NC}"
go build -o /usr/local/bin/node-metrics-exporter
echo -e "${GREEN}✓ Application built successfully${NC}"

echo -e "${YELLOW}Step 12: Creating systemd service...${NC}"
SERVICE_FILE="/etc/systemd/system/node-metrics-exporter.service"
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Node Metrics Exporter

[Service]
Type=simple
ExecStart=/usr/local/bin/node-metrics-exporter
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
echo -e "${GREEN}✓ Systemd service file created${NC}"

echo -e "${YELLOW}Step 13: Starting service...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable node-metrics-exporter
sudo systemctl start node-metrics-exporter
echo -e "${GREEN}✓ Service started and enabled${NC}"

echo -e "${YELLOW}Step 14: Verifying service status...${NC}"
if sudo systemctl is-active --quiet node-metrics-exporter; then
    echo -e "${GREEN}✓ Service is running${NC}"

    echo -e "${YELLOW}Step 15: Testing metrics sending...${NC}"
    echo -e "${YELLOW}Waiting for service to initialize (5 seconds)...${NC}"
    sleep 5

    # Check if metrics were sent successfully
    if sudo journalctl -u node-metrics-exporter -n 50 | grep -q "Collected metrics:"; then
        echo -e "${GREEN}✓ Metrics sent successfully${NC}"
        echo -e "${GREEN}Installation completed successfully!${NC}"
        echo -e "You can check the status with: ${YELLOW}sudo systemctl status node-metrics-exporter${NC}"
        echo -e "View logs with: ${YELLOW}sudo journalctl -u node-metrics-exporter -f${NC}"
    else
        echo -e "${RED}Failed to send metrics.${NC}"
        echo -e "Check the logs with: ${YELLOW}sudo journalctl -u node-metrics-exporter${NC}"
        exit 1
    fi
else
    echo -e "${RED}Service failed to start.${NC}"
    echo -e "Check the logs with: ${YELLOW}sudo journalctl -u node-metrics-exporter${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 16: Cleaning up...${NC}"
cd - > /dev/null
rm -rf "$TEMP_DIR"
echo -e "${GREEN}✓ Temporary files cleaned up${NC}"