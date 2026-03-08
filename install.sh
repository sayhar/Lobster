#!/bin/bash
#===============================================================================
# Lobster Bootstrap Installer
#
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/SiderealPress/lobster/main/install.sh)
#        bash install.sh --non-interactive   # Skip all interactive prompts
#
# This script sets up a complete Lobster installation on a fresh VM:
# - Installs system dependencies (Ubuntu/Debian or Amazon Linux 2023/Fedora)
# - Clones the repo (if needed)
# - Walks through configuration
# - Sets up Python environment
# - Registers MCP servers with Claude
# - Installs and starts systemd services
#===============================================================================

set -e

# Suppress needrestart interactive prompts during unattended installs
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Logging functions
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
step() { echo -e "\n${CYAN}${BOLD}▶ $1${NC}"; }

# Parse install mode from arguments
DEV_MODE=false
NON_INTERACTIVE=false
for arg in "$@"; do
    case "$arg" in
        --dev) DEV_MODE=true ;;
        --non-interactive|--skip-config) NON_INTERACTIVE=true ;;
    esac
done

# Configuration - can be overridden by environment variables or config file
REPO_URL="${LOBSTER_REPO_URL:-https://github.com/SiderealPress/lobster.git}"
REPO_BRANCH="${LOBSTER_BRANCH:-main}"
INSTALL_DIR="${LOBSTER_INSTALL_DIR:-$HOME/lobster}"
WORKSPACE_DIR="${LOBSTER_WORKSPACE:-$HOME/lobster-workspace}"
PROJECTS_DIR="${LOBSTER_PROJECTS:-$WORKSPACE_DIR/projects}"
MESSAGES_DIR="${LOBSTER_MESSAGES:-$HOME/messages}"
GITHUB_REPO="SiderealPress/lobster"
GITHUB_API="https://api.github.com/repos/$GITHUB_REPO"
WORK_DIR="$WORKSPACE_DIR"

# Try to detect if we're in an existing Lobster installation
if [ -f "$INSTALL_DIR/.lobster-installed" ]; then
    EXISTING_INSTALL=true
else
    EXISTING_INSTALL=false
fi

# Cleanup on exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "Installation failed with exit code $exit_code"
        error "Check /var/log/lobster-install.log for details"
    fi
    exit $exit_code
}
trap cleanup EXIT

# Log all output to file
exec > >(tee /var/log/lobster-install.log)
exec 2>&1

# Logging header
{
    echo "================================================================================"
    echo "Lobster Installation Log"
    echo "Start time: $(date)"
    echo "Repository: $REPO_URL"
    echo "Branch: $REPO_BRANCH"
    echo "Install dir: $INSTALL_DIR"
    echo "================================================================================"
} | head -20

# Check if we're running with enough privileges for apt/yum
if ! command -v sudo &> /dev/null; then
    error "sudo is required but not installed"
    exit 1
fi

# Detect OS and package manager
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
    elif [ -f /etc/redhat-release ]; then
        OS_ID="rhel"
        OS_VERSION=$(cat /etc/redhat-release | grep -oP '\d+' | head -1)
    else
        error "Unable to detect OS"
        exit 1
    fi

    # Map to package manager
    case "$OS_ID" in
        ubuntu|debian)
            PKG_MANAGER="apt"
            ;;
        amzn)
            PKG_MANAGER="dnf"
            ;;
        fedora|rhel|centos)
            PKG_MANAGER="dnf"
            ;;
        *)
            error "Unsupported OS: $OS_ID"
            exit 1
            ;;
    esac

    info "Detected OS: $OS_ID $OS_VERSION"
    info "Package manager: $PKG_MANAGER"
}

detect_os

#===============================================================================
# Git and Repo Setup
#===============================================================================

step "Checking git installation..."
if ! command -v git &> /dev/null; then
    error "Git is not installed"
    exit 1
fi
success "Git is installed"

# Check if we need to clone the repo
if [ ! -d "$INSTALL_DIR/.git" ]; then
    step "Cloning Lobster repository..."
    mkdir -p "$INSTALL_DIR"
    git clone -b "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR"
    success "Repository cloned to $INSTALL_DIR"
else
    step "Repository already exists, updating..."
    cd "$INSTALL_DIR"
    git fetch origin
    git checkout "$REPO_BRANCH"
    git pull origin "$REPO_BRANCH"
    success "Repository updated"
fi

cd "$INSTALL_DIR"

#===============================================================================
# Configuration
#===============================================================================

step "Setting up configuration..."

# Create workspace directory
mkdir -p "$WORKSPACE_DIR"
mkdir -p "$PROJECTS_DIR"
mkdir -p "$MESSAGES_DIR"

# Source existing config if available
CONFIG_FILE="$INSTALL_DIR/.env.local"
if [ -f "$CONFIG_FILE" ]; then
    info "Found existing config at $CONFIG_FILE"
    # Only source if NOT in non-interactive mode
    if [ "$NON_INTERACTIVE" = "false" ]; then
        read -p "Use existing config? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            source "$CONFIG_FILE"
            info "Loaded config from $CONFIG_FILE"
        fi
    else
        source "$CONFIG_FILE"
        info "Loaded config from $CONFIG_FILE (non-interactive mode)"
    fi
fi

# Interactive configuration
configure_lobster() {
    if [ "$NON_INTERACTIVE" = "true" ]; then
        info "Skipping interactive configuration (non-interactive mode)"
        return
    fi

    local should_configure=true

    # Check if we have basic config already
    if [ ! -z "$GITHUB_TOKEN" ] && [ ! -z "$TELEGRAM_BOT_TOKEN" ]; then
        read -p "Config already set. Reconfigure? (y/n) " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && should_configure=false
    fi

    if [ "$should_configure" = "true" ]; then
        # Prompt for Telegram bot token
        if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
            echo
            echo "Enter your Telegram bot token (from @BotFather):"
            read -r TELEGRAM_BOT_TOKEN
            # Validate token format (should be digits:letters)
            if ! [[ "$TELEGRAM_BOT_TOKEN" =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
                warn "Telegram token doesn't look right. Continuing anyway..."
            fi
        fi

        # Prompt for GitHub token
        if [ -z "$GITHUB_TOKEN" ]; then
            echo
            echo "Enter your GitHub personal access token:"
            echo "(create at https://github.com/settings/tokens with repo,gist scopes)"
            read -sr GITHUB_TOKEN
            echo
        fi

        # Prompt for workspace directory
        if [ -z "$LOBSTER_WORKSPACE" ]; then
            echo
            read -p "Workspace directory [$WORKSPACE_DIR]: " input
            [ ! -z "$input" ] && WORKSPACE_DIR="$input"
        fi

        # Save config
        {
            echo "export TELEGRAM_BOT_TOKEN='$TELEGRAM_BOT_TOKEN'"
            echo "export GITHUB_TOKEN='$GITHUB_TOKEN'"
            echo "export LOBSTER_WORKSPACE='$WORKSPACE_DIR'"
            echo "export LOBSTER_PROJECTS='$PROJECTS_DIR'"
            echo "export LOBSTER_MESSAGES='$MESSAGES_DIR'"
        } > "$CONFIG_FILE"
        success "Configuration saved to $CONFIG_FILE"
    fi
}

configure_lobster

# Load config
if [ -f "$CONFIG_FILE" ]; then
    export GITHUB_TOKEN
    export TELEGRAM_BOT_TOKEN
    export WORKSPACE_DIR
    export PROJECTS_DIR
    export MESSAGES_DIR
fi

#===============================================================================
# Install System Dependencies
#===============================================================================

step "Installing system dependencies..."

if [ "$PKG_MANAGER" = "apt" ]; then
    sudo apt-get update -qq
    sudo apt-get upgrade -y -qq

    PACKAGES=(
        curl
        wget
        git
        jq
        python3
        python3-pip
        python3-venv
        cron
        at
        expect
        tmux
        build-essential
        cmake
        ffmpeg
        ripgrep
        fd-find
        bat
        fzf
    )

    for pkg in "${PACKAGES[@]}"; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            info "Installing $pkg..."
            sudo apt-get install -y -qq "$pkg" || warn "Failed to install $pkg"
        else
            success "$pkg already installed"
        fi
    done

elif [ "$PKG_MANAGER" = "dnf" ]; then
    # Amazon Linux 2023 / Fedora / RHEL
    sudo dnf update -y -q
    sudo dnf groupinstall "Development Tools" -y -q || true

    PACKAGES=(
        curl
        wget
        git
        jq
        python3
        python3-pip
        python3-venv
        cronie
        at
        expect
        tmux
        cmake
        ffmpeg
        ripgrep
        fd-find
        bat
        fzf
    )

    for pkg in "${PACKAGES[@]}"; do
        if ! rpm -q "$pkg" &>/dev/null; then
            info "Installing $pkg..."
            sudo dnf install -y -q "$pkg" || warn "Failed to install $pkg"
        else
            success "$pkg already installed"
        fi
    done
else
    error "Unsupported package manager: $PKG_MANAGER"
    exit 1
fi

success "System dependencies installed"

#===============================================================================
# Python Virtual Environment Setup
#===============================================================================

step "Setting up Python virtual environment..."

if [ ! -d "$INSTALL_DIR/.venv" ]; then
    info "Creating virtual environment at $INSTALL_DIR/.venv..."
    python3 -m venv "$INSTALL_DIR/.venv"
else
    info "Virtual environment already exists"
fi

# Source the venv
source "$INSTALL_DIR/.venv/bin/activate"

# Upgrade pip
pip install --upgrade pip setuptools wheel --quiet

# Try to use uv if available, otherwise use pip
if command -v uv &> /dev/null; then
    info "Using uv for dependency installation"
    INSTALL_CMD="uv pip install"
else
    info "Using pip for dependency installation"
    INSTALL_CMD="pip install"
fi

# Install Python dependencies
if [ -f "$INSTALL_DIR/pyproject.toml" ]; then
    info "Installing Python dependencies from pyproject.toml..."
    cd "$INSTALL_DIR"
    $INSTALL_CMD -e . --quiet || error "Failed to install dependencies"
else
    info "No pyproject.toml found, skipping Python dependency installation"
fi

success "Python environment ready"

#===============================================================================
# Activate venv for subsequent steps
#===============================================================================

source "$INSTALL_DIR/.venv/bin/activate"

#===============================================================================
# MCP Configuration
#===============================================================================

step "Configuring MCP servers..."

# Check for Claude config
CLAUDE_CONFIG="$HOME/.claude/settings.json"
if [ ! -f "$CLAUDE_CONFIG" ]; then
    warn "Claude settings not found at $CLAUDE_CONFIG"
    warn "You'll need to add MCP servers manually after installation"
    warn "See https://github.com/SiderealPress/lobster#mcp-setup"
else
    info "Claude settings found at $CLAUDE_CONFIG"
    # Note: MCP server registration is handled by scripts/setup-mcp.sh
fi

#===============================================================================
# Create necessary directories and markers
#===============================================================================

step "Creating system directories..."
mkdir -p "$INSTALL_DIR/logs"
mkdir -p "$WORKSPACE_DIR"
mkdir -p "$PROJECTS_DIR"
mkdir -p "$MESSAGES_DIR"
mkdir -p "$INSTALL_DIR/.state"

success "Directories created"

#===============================================================================
# Systemd Service Installation
#===============================================================================

step "Installing systemd services..."

# Only create services if not in dev mode
if [ "$DEV_MODE" = "false" ]; then
    # Ensure systemd user dir exists
    mkdir -p ~/.config/systemd/user

    # Install lobster-main service
    if [ -f "$INSTALL_DIR/systemd/lobster-main.service" ]; then
        info "Installing lobster-main service..."
        envsubst < "$INSTALL_DIR/systemd/lobster-main.service" > /tmp/lobster-main.service
        cp /tmp/lobster-main.service ~/.config/systemd/user/
        systemctl --user daemon-reload
        success "lobster-main service installed"
    fi

    # Enable and start lobster-main if it exists
    if [ -f ~/.config/systemd/user/lobster-main.service ]; then
        info "Starting lobster-main service..."
        systemctl --user enable lobster-main.service
        systemctl --user restart lobster-main.service
        success "lobster-main service started"
    fi
else
    info "Dev mode: skipping systemd service installation"
fi

#===============================================================================
# Final Status
#===============================================================================

step "Installation complete!"

success "Lobster has been installed at $INSTALL_DIR"
success "Workspace directory: $WORKSPACE_DIR"
success "Log file: /var/log/lobster-install.log"

# Summary
echo ""
echo "Next steps:"
echo "1. Edit configuration: $CONFIG_FILE"
echo "2. Set up MCP servers: See docs/mcp-setup.md"
if [ "$DEV_MODE" = "false" ]; then
    echo "3. Check service status: systemctl --user status lobster-main"
else
    echo "3. Start manually in dev mode: cd $INSTALL_DIR && bash scripts/lobster.sh"
fi

# Create a marker file to indicate successful installation
touch "$INSTALL_DIR/.lobster-installed"

# Suggest MCP setup if Claude config not found
if [ ! -f "$CLAUDE_CONFIG" ]; then
    echo ""
    warn "Claude settings not configured. Run:"
    echo "  bash $INSTALL_DIR/scripts/setup-mcp.sh"
fi
