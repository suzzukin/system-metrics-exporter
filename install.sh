#!/bin/bash

# One-liner installation command:
# curl -s https://raw.githubusercontent.com/suzzukin/system-metrics-exporter/main/install.sh | sudo bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to install Go
install_go() {
    echo -e "${YELLOW}Installing Go...${NC}"

    # Get the latest Go version
    GO_VERSION=$(curl -s https://go.dev/VERSION?m=text)
    if [ -z "$GO_VERSION" ]; then
        echo -e "${RED}Failed to get Go version. Using latest stable version.${NC}"
        GO_VERSION="go1.22.1"
    fi

    # Download Go
    echo -e "${YELLOW}Downloading Go ${GO_VERSION}...${NC}"
    if ! wget "https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz; then
        echo -e "${RED}Failed to download Go.${NC}"
        exit 1
    fi

    # Remove old Go installation if exists
    sudo rm -rf /usr/local/go

    # Extract Go
    echo -e "${YELLOW}Extracting Go...${NC}"
    if ! sudo tar -C /usr/local -xzf /tmp/go.tar.gz; then
        echo -e "${RED}Failed to extract Go.${NC}"
        exit 1
    fi

    # Add Go to PATH if not already present
    if ! grep -q "export PATH=\$PATH:/usr/local/go/bin" ~/.bashrc; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    fi

    # Source the updated PATH
    source ~/.bashrc

    # Verify Go installation
    if ! command -v go &> /dev/null; then
        echo -e "${RED}Go installation failed.${NC}"
        exit 1
    fi

    # Cleanup
    rm /tmp/go.tar.gz

    echo -e "${GREEN}Go installed successfully!${NC}"
}

echo -e "${YELLOW}System Metrics Exporter Installation${NC}"
echo "----------------------------------------"

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo -e "${RED}Git is not installed. Please install Git first.${NC}"
    exit 1
fi

# Check if Go is installed, if not install it
if ! command -v go &> /dev/null; then
    echo -e "${YELLOW}Go is not installed. Installing Go...${NC}"
    install_go
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

# Build the application
echo -e "${YELLOW}Building application...${NC}"
go build -o /usr/local/bin/node-metrics-exporter

# Create systemd service file
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
else
    echo -e "${RED}Service failed to start.${NC}"
    echo -e "Check the logs with: ${YELLOW}sudo journalctl -u node-metrics-exporter${NC}"
    exit 1
fi

# Cleanup
cd - > /dev/null
rm -rf "$TEMP_DIR"