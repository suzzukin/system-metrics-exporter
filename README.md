# System Metrics Exporter

A lightweight system metrics collector and exporter written in Go that monitors CPU, memory, network usage, and internet speed. Designed for system administrators and monitoring systems.

## Features

- **CPU Monitoring**
  - Real-time CPU usage tracking
  - Average CPU utilization over time

- **Memory Monitoring**
  - RAM usage tracking
  - Memory utilization percentage

- **Network Monitoring**
  - Bandwidth utilization tracking
  - Network I/O statistics
  - Upload/Download speed monitoring

- **Internet Speed Testing**
  - Integration with speedtest-cli
  - Regular speed measurements
  - Real-time bandwidth capacity monitoring

- **Easy Integration**
  - JSON metrics export
  - Configurable endpoint
  - Systemd service integration
  - Simple installation process

## Requirements

- Linux system
- Git
- Go 1.24.1 or later
- speedtest-cli
- Systemd

## Installation

### Quick Install

```bash
curl -H 'Cache-Control: no-cache' -s "https://raw.githubusercontent.com/suzzukin/system-metrics-exporter/main/install.sh?t=$(date +%s)" | sudo bash
```

**During installation, you will be prompted to enter:**
- The server URL (e.g., `https://your-server.com`)
- The API token

The script will:
- Check and install required dependencies (`git`, `speedtest-cli`, `go`)
- Clone the repository and build the application
- Set up the systemd service
- Create the configuration file interactively

### Update

```bash
curl -H 'Cache-Control: no-cache' -s "https://raw.githubusercontent.com/suzzukin/system-metrics-exporter/main/update.sh?t=$(date +%s)" | sudo bash
```

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/suzzukin/system-metrics-exporter.git
   cd system-metrics-exporter
   ```

2. Install dependencies:
   ```bash
   sudo apt-get update
   sudo apt-get install -y speedtest-cli git
   ```

3. Build the application:
   ```bash
   go build -o node-metrics-exporter
   ```

4. Create configuration:
   ```bash
   sudo mkdir -p /var/lib/vpn-metrics
   sudo nano /var/lib/vpn-metrics/config.json
   ```
   Example config:
   ```json
   {
       "server_url": "https://your-server.com",
       "api_token": "your-token",
       "report_interval": 60
   }
   ```

5. Set up systemd service:
   ```bash
   sudo cp node-metrics-exporter /usr/local/bin/
   sudo nano /etc/systemd/system/node-metrics-exporter.service
   ```
   Add service configuration:
   ```ini
   [Unit]
   Description=Node Metrics Exporter

   [Service]
   Type=simple
   ExecStart=/usr/local/bin/node-metrics-exporter
   Restart=always
   RestartSec=10

   [Install]
   WantedBy=multi-user.target
   ```

6. Start the service:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable node-metrics-exporter
   sudo systemctl start node-metrics-exporter
   ```

## Uninstallation

### Quick Uninstall

```bash
curl -H 'Cache-Control: no-cache' -s "https://raw.githubusercontent.com/suzzukin/system-metrics-exporter/main/uninstall.sh?t=$(date +%s)" | sudo bash
```

The uninstallation script will:
1. Stop the service
2. Disable the service
3. Remove the service file
4. Remove the binary
5. Remove configuration files
6. Clean up systemd

### Manual Uninstallation

1. Stop and disable the service:
   ```bash
   sudo systemctl stop node-metrics-exporter
   sudo systemctl disable node-metrics-exporter
   ```

2. Remove service file:
   ```bash
   sudo rm /etc/systemd/system/node-metrics-exporter.service
   ```

3. Reload systemd:
   ```bash
   sudo systemctl daemon-reload
   ```

4. Remove binary and configuration:
   ```bash
   sudo rm /usr/local/bin/node-metrics-exporter
   sudo rm -rf /var/lib/vpn-metrics
   ```

## Configuration

The exporter is configured via `/var/lib/vpn-metrics/config.json`, which is created automatically during installation:

```json
{
    "server_url": "https://your-server.com",
    "api_token": "your-token",
    "report_interval": 60
}
```

## Metrics Format

The exporter sends JSON metrics in the following format:

```json
{
    "cpu_percent": 45.2,
    "memory_percent": 68.5,
    "net_in_percent": 25.3,
    "net_out_percent": 15.7,
    "speedtest_mbps": 100.5
}
```

## Usage

### Check Service Status

```bash
sudo systemctl status node-metrics-exporter
```

### View Logs

```bash
sudo journalctl -u node-metrics-exporter
```

### Stop Service

```bash
sudo systemctl stop node-metrics-exporter
```

### Start Service

```bash
sudo systemctl start node-metrics-exporter
```

## License

MIT License - see LICENSE file for details