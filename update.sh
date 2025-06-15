#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to print colored messages
print_message() {
    echo -e "${2}${1}${NC}"
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_message "Please run as root" "$RED"
        exit 1
    fi
}

# Function to check if git is installed
check_git() {
    if ! command -v git &> /dev/null; then
        print_message "Git is not installed. Installing..." "$YELLOW"
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y git
        elif command -v yum &> /dev/null; then
            yum install -y git
        else
            print_message "Could not install git. Please install it manually." "$RED"
            exit 1
        fi
    fi
}

# Function to check current version
check_current_version() {
    if ! command -v node-metrics-exporter &> /dev/null; then
        print_message "node-metrics-exporter not found, needs installation" "$YELLOW"
        return 1
    fi

    # Try to get version from CLI
    if version_output=$(node-metrics-exporter -version 2>&1); then
        echo "$version_output"
        return 0
    else
        print_message "Current version does not support version check (old version)" "$YELLOW"
        return 1
    fi
}

# Function to check for updates
check_updates() {
    print_message "Checking for updates..." "$YELLOW"

    # Get current version
    CURRENT_VERSION=$(check_current_version)
    CURRENT_VERSION_STATUS=$?

    # Create and enter temp directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR" || exit 1

    # Clone repository
    git clone -q https://github.com/suzzukin/system-metrics-exporter.git
    cd system-metrics-exporter

    # Build new version
    print_message "Building new version..." "$YELLOW"
    # Use Go from /usr/local/go/bin if not in PATH
    if ! command -v go &> /dev/null && [ -f "/usr/local/go/bin/go" ]; then
        /usr/local/go/bin/go version
        /usr/local/go/bin/go build -o node-metrics-exporter.new
    else
        go version
        go build -o node-metrics-exporter.new
    fi

    # Check if build was successful
    if [ ! -f "node-metrics-exporter.new" ]; then
        print_message "Failed to build new version. Current directory: $(pwd)" "$RED"
        ls -la
        cd - > /dev/null
        rm -rf "$TEMP_DIR"
        return 1
    fi

    # Get new version
    NEW_VERSION=$(./node-metrics-exporter.new -version 2>/dev/null)

    if [ $CURRENT_VERSION_STATUS -ne 0 ] || [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
        if [ $CURRENT_VERSION_STATUS -ne 0 ]; then
            print_message "Update needed: Current version is outdated" "$GREEN"
            return 0
        else
            print_message "Update available: $CURRENT_VERSION -> $NEW_VERSION" "$GREEN"
            return 0
        fi
    else
        print_message "No updates available" "$GREEN"
        cd - > /dev/null
        rm -rf "$TEMP_DIR"
        return 1
    fi
}

# Function to update the script
update_script() {
    print_message "Updating script..." "$YELLOW"

    # Install new version
    mv node-metrics-exporter.new /usr/local/bin/node-metrics-exporter || {
        print_message "Failed to move new version to /usr/local/bin" "$RED"
        exit 1
    }

    # Cleanup
    cd - > /dev/null
    rm -rf "$TEMP_DIR"

    # Restart the service
    print_message "Restarting service..." "$YELLOW"
    systemctl restart node-metrics-exporter

    print_message "Update completed successfully!" "$GREEN"
}

# Main execution
check_root
check_git

# Change to script directory
cd "$(dirname "$0")" || exit 1

if check_updates; then
    update_script
fi