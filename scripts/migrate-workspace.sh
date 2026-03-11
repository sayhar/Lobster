#!/bin/bash
#===============================================================================
# Lobster Workspace Migration Script
#
# Migrates the workspace from the old external layout (~/lobster-workspace/ as a
# standalone directory outside the repo) to the new layout
# (~/lobster/lobster-workspace/ inside the repo, gitignored), and creates a
# backward-compatibility symlink at ~/lobster-workspace so existing scripts,
# env vars, and MCP servers continue working without changes.
#
# Safe to run multiple times (idempotent). Run this after `git pull` if you
# pulled the issue-114-workspace-merge changes and have an existing install.
#
# Usage:
#   bash scripts/migrate-workspace.sh [--dry-run] [--yes]
#
# Options:
#   --dry-run   Show what would happen without making any changes
#   --yes       Non-interactive: proceed without confirmation prompt
#
# Exit codes:
#   0 - Success (migrated, or already in correct state)
#   1 - Error occurred
#===============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
step()    { echo -e "\n${CYAN}${BOLD}▶ $1${NC}"; }
die()     { error "$1"; exit 1; }

DRY_RUN=false
YES=false

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --yes)     YES=true ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--yes]"
            echo ""
            echo "Migrates ~/lobster-workspace/ → ~/lobster/workspace/ and"
            echo "creates a backward-compatibility symlink at the old path."
            echo ""
            echo "Options:"
            echo "  --dry-run   Show what would happen without making changes"
            echo "  --yes       Proceed without interactive confirmation"
            exit 0
            ;;
        *)
            die "Unknown option: $arg (try --help)"
            ;;
    esac
done

#-------------------------------------------------------------------------------
# Determine paths
#-------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(dirname "$SCRIPT_DIR")"

OLD_WORKSPACE="$HOME/lobster-workspace"
NEW_WORKSPACE="$INSTALL_DIR/lobster-workspace"

echo -e "${BLUE}${BOLD}"
echo "═══════════════════════════════════════════════════════════════"
echo "            LOBSTER WORKSPACE MIGRATION"
echo "═══════════════════════════════════════════════════════════════"
echo -e "${NC}"
echo "  Old path: $OLD_WORKSPACE"
echo "  New path: $NEW_WORKSPACE"
echo ""

if $DRY_RUN; then
    warn "DRY RUN MODE — no changes will be made"
    echo ""
fi

#-------------------------------------------------------------------------------
# Detect current state
#-------------------------------------------------------------------------------

step "Detecting current layout..."

if [ -L "$OLD_WORKSPACE" ]; then
    # Already a symlink — check where it points
    target=$(readlink "$OLD_WORKSPACE")
    info "  $OLD_WORKSPACE is already a symlink → $target"

    if [ "$target" = "$NEW_WORKSPACE" ]; then
        success "Workspace is already in the correct layout."
        success "No migration needed."
        exit 0
    else
        warn "  Symlink points to $target, not $NEW_WORKSPACE"
        warn "  Will update symlink to point to $NEW_WORKSPACE"
    fi
elif [ -d "$OLD_WORKSPACE" ]; then
    info "  Found real directory at $OLD_WORKSPACE"

    # Count contents
    item_count=$(find "$OLD_WORKSPACE" -maxdepth 1 -mindepth 1 | wc -l)
    info "  Contains $item_count items"

    if [ -d "$NEW_WORKSPACE" ]; then
        new_count=$(find "$NEW_WORKSPACE" -maxdepth 1 -mindepth 1 | wc -l)
        info "  New workspace already exists at $NEW_WORKSPACE ($new_count items)"
    fi
else
    info "  No existing workspace at $OLD_WORKSPACE (fresh install)"
fi

#-------------------------------------------------------------------------------
# Show plan
#-------------------------------------------------------------------------------

step "Migration plan..."

if [ -d "$OLD_WORKSPACE" ] && [ ! -L "$OLD_WORKSPACE" ]; then
    BACKUP_NAME="${OLD_WORKSPACE}.bak-$(date +%Y%m%d%H%M%S)"
    echo "  1. Create $NEW_WORKSPACE (if not exists)"
    echo "  2. Copy contents of $OLD_WORKSPACE → $NEW_WORKSPACE"
    echo "  3. Rename $OLD_WORKSPACE → $BACKUP_NAME"
    echo "  4. Create symlink: $OLD_WORKSPACE → $NEW_WORKSPACE"
    echo ""
    echo "  Rollback:"
    echo "    rm $OLD_WORKSPACE && mv $BACKUP_NAME $OLD_WORKSPACE"
elif [ -L "$OLD_WORKSPACE" ]; then
    echo "  1. Remove old symlink at $OLD_WORKSPACE"
    echo "  2. Create symlink: $OLD_WORKSPACE → $NEW_WORKSPACE"
else
    echo "  1. Create $NEW_WORKSPACE"
    echo "  2. Create symlink: $OLD_WORKSPACE → $NEW_WORKSPACE"
fi

#-------------------------------------------------------------------------------
# Confirm
#-------------------------------------------------------------------------------

if ! $DRY_RUN && ! $YES; then
    echo ""
    read -r -p "Proceed with migration? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Migration cancelled."
        exit 0
    fi
fi

#-------------------------------------------------------------------------------
# Execute
#-------------------------------------------------------------------------------

step "Running migration..."

# Ensure the new workspace directory exists inside the repo
if ! $DRY_RUN; then
    mkdir -p "$NEW_WORKSPACE"
else
    info "  [dry-run] Would create $NEW_WORKSPACE"
fi

if [ -d "$OLD_WORKSPACE" ] && [ ! -L "$OLD_WORKSPACE" ]; then
    # Real directory — copy contents then replace with symlink
    BACKUP_NAME="${OLD_WORKSPACE}.bak-$(date +%Y%m%d%H%M%S)"

    if ! $DRY_RUN; then
        # Copy contents, merging with anything already in new workspace
        # Using cp -a with || true so files that already exist don't abort the copy
        if [ "$(ls -A "$OLD_WORKSPACE" 2>/dev/null)" ]; then
            info "  Copying contents to $NEW_WORKSPACE..."
            cp -a "$OLD_WORKSPACE/." "$NEW_WORKSPACE/" 2>/dev/null || true
            success "  Copied workspace contents"
        else
            info "  Old workspace was empty, nothing to copy"
        fi

        # Backup the old directory
        mv "$OLD_WORKSPACE" "$BACKUP_NAME"
        success "  Renamed old directory to $(basename "$BACKUP_NAME")"

        # Create compatibility symlink
        ln -s "$NEW_WORKSPACE" "$OLD_WORKSPACE"
        success "  Created symlink: $OLD_WORKSPACE → $NEW_WORKSPACE"
    else
        info "  [dry-run] Would copy $OLD_WORKSPACE → $NEW_WORKSPACE"
        info "  [dry-run] Would rename old dir to $BACKUP_NAME"
        info "  [dry-run] Would create symlink: $OLD_WORKSPACE → $NEW_WORKSPACE"
    fi

elif [ -L "$OLD_WORKSPACE" ]; then
    # Existing symlink — update it
    if ! $DRY_RUN; then
        rm "$OLD_WORKSPACE"
        ln -s "$NEW_WORKSPACE" "$OLD_WORKSPACE"
        success "  Updated symlink: $OLD_WORKSPACE → $NEW_WORKSPACE"
    else
        info "  [dry-run] Would update symlink: $OLD_WORKSPACE → $NEW_WORKSPACE"
    fi

else
    # No old workspace — just create symlink
    if ! $DRY_RUN; then
        ln -s "$NEW_WORKSPACE" "$OLD_WORKSPACE"
        success "  Created symlink: $OLD_WORKSPACE → $NEW_WORKSPACE"
    else
        info "  [dry-run] Would create symlink: $OLD_WORKSPACE → $NEW_WORKSPACE"
    fi
fi

#-------------------------------------------------------------------------------
# Update LOBSTER_WORKSPACE in config if needed
#-------------------------------------------------------------------------------

step "Checking config for LOBSTER_WORKSPACE references..."

CONFIG_DIR="${LOBSTER_CONFIG_DIR:-$HOME/lobster-config}"
CONFIG_ENV="$CONFIG_DIR/config.env"

if [ -f "$CONFIG_ENV" ] && grep -q "LOBSTER_WORKSPACE" "$CONFIG_ENV"; then
    current_val=$(grep "^LOBSTER_WORKSPACE=" "$CONFIG_ENV" | cut -d= -f2- | tr -d '"' | head -1)
    if [ "$current_val" = "$OLD_WORKSPACE" ]; then
        if ! $DRY_RUN; then
            # The symlink at OLD_WORKSPACE still resolves correctly, so no change
            # strictly required. But note this for the user.
            info "  LOBSTER_WORKSPACE=$current_val in $CONFIG_ENV"
            info "  This still works via the symlink. No config change required."
        else
            info "  [dry-run] LOBSTER_WORKSPACE=$current_val in $CONFIG_ENV (symlink covers it)"
        fi
    else
        info "  LOBSTER_WORKSPACE is set to $current_val — no change needed"
    fi
else
    info "  LOBSTER_WORKSPACE not explicitly set in config — using default"
fi

#-------------------------------------------------------------------------------
# Verify
#-------------------------------------------------------------------------------

if ! $DRY_RUN; then
    step "Verifying migration..."

    if [ -L "$OLD_WORKSPACE" ] && [ -d "$OLD_WORKSPACE" ]; then
        target=$(readlink "$OLD_WORKSPACE")
        success "  Symlink OK: $OLD_WORKSPACE → $target"
    else
        die "Verification failed: $OLD_WORKSPACE is not a valid symlink"
    fi

    if [ -d "$NEW_WORKSPACE" ]; then
        success "  New workspace exists: $NEW_WORKSPACE"
    else
        die "Verification failed: $NEW_WORKSPACE not found"
    fi
fi

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------

echo ""
echo -e "${GREEN}${BOLD}"
echo "═══════════════════════════════════════════════════════════════"
if $DRY_RUN; then
    echo "            DRY RUN COMPLETE (no changes made)"
else
    echo "            MIGRATION COMPLETE"
fi
echo "═══════════════════════════════════════════════════════════════"
echo -e "${NC}"

if ! $DRY_RUN; then
    echo "  Workspace is now at: $NEW_WORKSPACE"
    echo "  Old path still works: $OLD_WORKSPACE (symlink)"
    echo ""
    echo "  All existing scripts, env vars, and MCP servers that reference"
    echo "  ~/lobster-workspace will continue to work unchanged."
    echo ""
    echo "  Rollback if needed:"
    BACKUP_GLOB="${OLD_WORKSPACE}.bak-*"
    echo "    rm $OLD_WORKSPACE && mv \$(ls -td ${BACKUP_GLOB} | head -1) $OLD_WORKSPACE"
    echo ""
fi
