#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to install Go
install_go() {
    echo -e "${YELLOW}Installing Go...${NC}"

    # Get the latest Go version
    GO_VERSION=$(curl -s https://golang.org/VERSION?m=text)

    # Download Go
    wget "https://golang.org/dl/${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz

    # Remove old Go installation if exists
    sudo rm -rf /usr/local/go

    # Extract Go
    sudo tar -C /usr/local -xzf /tmp/go.tar.gz

    # Add Go to PATH if not already present
    if ! grep -q "export PATH=\$PATH:/usr/local/go/bin" ~/.bashrc; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    fi

    # Source the updated PATH
    source ~/.bashrc

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

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed. Please install Docker first.${NC}"
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

# Build Docker image
echo -e "${YELLOW}Building Docker image...${NC}"
docker build -t node-metrics-exporter .

# Build the application
echo -e "${YELLOW}Building application...${NC}"
go build -o /usr/local/bin/node-metrics-exporter

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
    --privileged \\
    --cap-add=SYS_ADMIN \\
    --cap-add=SYS_RESOURCE \\
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