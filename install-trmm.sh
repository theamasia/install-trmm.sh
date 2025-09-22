#!/bin/bash

#############################################
# Tactical RMM Linux Agent Quick Install Script
# For Ubuntu Server
# Version: 1.0
#############################################

set -e  # Exit on error

# CONFIGURATION - MODIFY THESE VALUES
MESH_URL=""           # Your Mesh Central URL (optional - leave blank if not using)
MESH_ID=""            # Your Mesh Agent ID (optional - leave blank if not using)
API_URL="https://api.ainnrmm.us"            # Your Tactical RMM API URL
CLIENT_ID="1"          # Client ID (numeric)
SITE_ID="5"            # Site ID (numeric)
AGENT_TYPE="server"   # Agent type: server or workstation
AUTH_KEY="b068d07e2934818d77f68f99d311eb52febd65cebea0ebbe56aebff7f40e2768"           # Your auth key from Tactical RMM

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_error() {
    echo -e "${RED}[!]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[*]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "This script must be run as root"
    exit 1
fi

# Check Ubuntu version
if ! grep -q "Ubuntu" /etc/os-release; then
    print_warning "This script is designed for Ubuntu. Detected: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

print_status "Starting Tactical RMM Agent Installation for Ubuntu Server"

# Check required variables
if [ -z "$API_URL" ] || [ -z "$CLIENT_ID" ] || [ -z "$SITE_ID" ] || [ -z "$AUTH_KEY" ]; then
    print_error "Please configure all required variables at the top of this script:"
    echo "  - API_URL"
    echo "  - CLIENT_ID" 
    echo "  - SITE_ID"
    echo "  - AUTH_KEY"
    echo ""
    echo "You can find these values in your Tactical RMM dashboard:"
    echo "1. Go to Agents > Install Agent"
    echo "2. Select your client and site"
    echo "3. Choose Linux and copy the installation values"
    exit 1
fi

# Update system
print_status "Updating package lists..."
apt-get update -qq

# Install dependencies
print_status "Installing dependencies..."
apt-get install -y -qq curl wget sudo net-tools grep sed

# Detect system architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        AGENT_ARCH="amd64"
        ;;
    aarch64|arm64)
        AGENT_ARCH="arm64"
        ;;
    armv7l)
        AGENT_ARCH="armv7"
        ;;
    *)
        print_error "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac
print_status "Detected architecture: $ARCH ($AGENT_ARCH)"

# Create temp directory
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

# Download and install Mesh Agent if URL provided
if [ ! -z "$MESH_URL" ] && [ ! -z "$MESH_ID" ]; then
    print_status "Installing Mesh Agent..."
    
    MESH_INSTALLER="meshinstall.sh"
    wget -q "${MESH_URL}/meshagents?id=${MESH_ID}&installflags=2&meshinstall=6" -O "$MESH_INSTALLER"
    
    if [ -f "$MESH_INSTALLER" ]; then
        chmod +x "$MESH_INSTALLER"
        ./"$MESH_INSTALLER" || print_warning "Mesh Agent installation had issues, continuing..."
    else
        print_warning "Could not download Mesh Agent installer, skipping..."
    fi
else
    print_warning "Mesh Agent URL/ID not configured, skipping Mesh Agent installation"
fi

# Download Tactical RMM agent
print_status "Downloading Tactical RMM agent..."

# Get the latest release URL - try multiple methods
print_status "Fetching latest release information..."

# Method 1: Try with correct pattern for rmmagent releases
LATEST_RELEASE=$(curl -s https://api.github.com/repos/amidaware/rmmagent/releases/latest | grep -o "https://github.com/amidaware/rmmagent/releases/download/[^\"]*linux-${AGENT_ARCH}\.tar\.gz" | head -1)

# Method 2: If that fails, try alternative pattern
if [ -z "$LATEST_RELEASE" ]; then
    print_warning "Trying alternative download pattern..."
    LATEST_RELEASE=$(curl -s https://api.github.com/repos/amidaware/rmmagent/releases/latest | grep -o "https://[^\"]*rmmagent[^\"]*linux[^\"]*${AGENT_ARCH}[^\"]*\.tar\.gz" | head -1)
fi

# Method 3: If still failing, try direct URL construction with latest version
if [ -z "$LATEST_RELEASE" ]; then
    print_warning "Attempting to construct download URL..."
    # Get the latest version tag
    LATEST_VERSION=$(curl -s https://api.github.com/repos/amidaware/rmmagent/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)
    if [ ! -z "$LATEST_VERSION" ]; then
        LATEST_RELEASE="https://github.com/amidaware/rmmagent/releases/download/${LATEST_VERSION}/rmmagent-linux-${AGENT_ARCH}.tar.gz"
        print_status "Constructed URL with version ${LATEST_VERSION}"
    fi
fi

# Method 4: If all API methods fail, use a known working version
if [ -z "$LATEST_RELEASE" ]; then
    print_warning "GitHub API might be rate-limited or changed. Using fallback version..."
    FALLBACK_VERSION="v2.7.0"  # Update this periodically
    LATEST_RELEASE="https://github.com/amidaware/rmmagent/releases/download/${FALLBACK_VERSION}/rmmagent-linux-${AGENT_ARCH}.tar.gz"
    print_warning "Using fallback version ${FALLBACK_VERSION}"
fi

if [ -z "$LATEST_RELEASE" ]; then
    print_error "Could not determine download URL for architecture: $AGENT_ARCH"
    print_error "Please check: https://github.com/amidaware/rmmagent/releases"
    print_error "You can manually download and install the agent if needed."
    exit 1
fi

print_status "Downloading from: $LATEST_RELEASE"
if ! wget -q "$LATEST_RELEASE" -O rmmagent.tar.gz; then
    print_error "Failed to download agent from $LATEST_RELEASE"
    print_error "Please check your internet connection and try again."
    exit 1
fi

# Verify the download
if [ ! -f rmmagent.tar.gz ] || [ ! -s rmmagent.tar.gz ]; then
    print_error "Downloaded file is empty or missing"
    exit 1
fi

# Extract agent
print_status "Extracting agent..."
tar -xzf rmmagent.tar.gz

# Install agent
print_status "Installing Tactical RMM agent..."

# Build installation command
INSTALL_CMD="./rmmagent -m install -api \"${API_URL}\" -client-id ${CLIENT_ID} -site-id ${SITE_ID} -agent-type ${AGENT_TYPE} -auth \"${AUTH_KEY}\""

# Add mesh node ID if available
if [ -f /opt/meshcentral/meshagent ] && [ ! -z "$MESH_ID" ]; then
    # Try to get mesh node ID
    MESH_NODE_ID=$(/opt/meshcentral/meshagent -nodeid 2>/dev/null | grep -oP 'node//[^"]+' || true)
    if [ ! -z "$MESH_NODE_ID" ]; then
        INSTALL_CMD="${INSTALL_CMD} -mesh-node-id \"${MESH_NODE_ID}\""
        print_status "Found Mesh Node ID: ${MESH_NODE_ID}"
    fi
fi

print_status "Running installation..."
eval $INSTALL_CMD

# Check if service is running
sleep 3
if systemctl is-active --quiet tacticalagent; then
    print_status "Tactical RMM agent is running successfully!"
    
    # Show service status
    print_status "Service status:"
    systemctl status tacticalagent --no-pager | head -10
else
    print_error "Tactical RMM agent service is not running!"
    print_status "Checking service status..."
    systemctl status tacticalagent --no-pager
    
    print_status "Checking logs..."
    journalctl -u tacticalagent --no-pager | tail -20
fi

# Cleanup
print_status "Cleaning up temporary files..."
cd /
rm -rf "$TMP_DIR"

# Enable agent on boot
print_status "Enabling agent to start on boot..."
systemctl enable tacticalagent

# Final checks
print_status "Installation completed!"
echo ""
echo "========================================="
echo "Installation Summary:"
echo "========================================="
echo "API URL: ${API_URL}"
echo "Client ID: ${CLIENT_ID}"
echo "Site ID: ${SITE_ID}"
echo "Agent Type: ${AGENT_TYPE}"
echo "Architecture: ${AGENT_ARCH}"
echo ""

# Check agent info
if command -v /usr/local/bin/rmmagent &> /dev/null; then
    print_status "Agent version:"
    /usr/local/bin/rmmagent -version
fi

echo ""
echo "To check agent status: systemctl status tacticalagent"
echo "To view agent logs: journalctl -u tacticalagent -f"
echo ""

# Optional: Show network connectivity check
print_status "Checking connectivity to API..."
if curl -s -o /dev/null -w "%{http_code}" "${API_URL}/api/v3/ping/" | grep -q "200\|401"; then
    print_status "API server is reachable"
else
    print_warning "Could not reach API server. Please check your firewall rules."
fi

print_status "Script completed successfully!"
