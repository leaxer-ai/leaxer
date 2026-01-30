#!/usr/bin/env bash
# Build the Leaxer desktop application
#
# Usage: ./scripts/build-desktop.sh [OPTIONS]
#
# This script performs the complete desktop build:
#   1. Downloads dependency binaries (optional, skip with --skip-download)
#   2. Builds the Elixir release
#   3. Copies release to Tauri resources
#   4. Verifies all required files
#   5. Builds the Tauri app (optional, skip with --skip-tauri)
#
# Environment variables:
#   GH_TOKEN   - GitHub token for downloading releases
#   MIX_ENV    - Elixir environment (default: prod)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() { echo -e "${CYAN}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step() { echo -e "\n${BOLD}${CYAN}=== $* ===${NC}\n"; }

# Detect script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default configuration
MIX_ENV="${MIX_ENV:-prod}"
SKIP_DOWNLOAD=false
SKIP_TAURI=false
SKIP_FRONTEND=false
TARGET=""

# Detect target platform
detect_target() {
    local os
    os="$(uname -s)"

    case "$os" in
        Darwin)
            if [[ "$(uname -m)" == "arm64" ]]; then
                echo "aarch64-apple-darwin"
            else
                echo "x86_64-apple-darwin"
            fi
            ;;
        Linux)
            echo "x86_64-unknown-linux-gnu"
            ;;
        MINGW*|MSYS*|CYGWIN*|Windows_NT)
            echo "x86_64-pc-windows-msvc"
            ;;
        *)
            log_error "Unsupported OS: $os"
            exit 1
            ;;
    esac
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            TARGET="$2"
            shift 2
            ;;
        --skip-download)
            SKIP_DOWNLOAD=true
            shift
            ;;
        --skip-tauri)
            SKIP_TAURI=true
            shift
            ;;
        --skip-frontend)
            SKIP_FRONTEND=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --target TARGET    Target platform (default: auto-detect)"
            echo "  --skip-download    Skip downloading dependency binaries"
            echo "  --skip-frontend    Skip building frontend (assumes already built)"
            echo "  --skip-tauri       Skip building Tauri app (only build Elixir release)"
            echo ""
            echo "Environment variables:"
            echo "  GH_TOKEN           GitHub token for downloading releases"
            echo "  MIX_ENV            Elixir environment (default: prod)"
            echo ""
            echo "Examples:"
            echo "  $0                              # Full build for current platform"
            echo "  $0 --skip-download              # Build without re-downloading deps"
            echo "  $0 --skip-tauri                 # Only build Elixir release"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Auto-detect target if not specified
if [[ -z "$TARGET" ]]; then
    TARGET=$(detect_target)
fi

# Print build configuration
log_step "Build Configuration"
log_info "Repository root: $REPO_ROOT"
log_info "Target platform: $TARGET"
log_info "MIX_ENV: $MIX_ENV"
log_info "Skip download: $SKIP_DOWNLOAD"
log_info "Skip frontend: $SKIP_FRONTEND"
log_info "Skip Tauri: $SKIP_TAURI"

# Change to repo root
cd "$REPO_ROOT"

# Step 1: Download dependencies
if [[ "$SKIP_DOWNLOAD" != "true" ]]; then
    log_step "Step 1: Downloading Dependencies"

    if [[ -z "${GH_TOKEN:-}" ]] && ! gh auth status &>/dev/null; then
        log_warn "GH_TOKEN not set and gh not authenticated"
        log_warn "Skipping download - assuming binaries are already present"
    else
        "$SCRIPT_DIR/download-deps.sh" --target "$TARGET"
    fi
else
    log_step "Step 1: Skipping Download (--skip-download)"
fi

# Step 2: Verify downloaded dependencies
log_step "Step 2: Verifying Downloaded Dependencies"
"$SCRIPT_DIR/verify-bundle.sh" --target "$TARGET" --dir "$REPO_ROOT/apps/leaxer_core/priv/bin"

# Step 3: Build Elixir release
log_step "Step 3: Building Elixir Release"

log_info "Installing Elixir dependencies..."
mix deps.get --only "$MIX_ENV"

log_info "Compiling..."
MIX_ENV="$MIX_ENV" mix compile

log_info "Building release..."
MIX_ENV="$MIX_ENV" mix release leaxer_core --overwrite

log_success "Elixir release built successfully"

# Step 4: Copy release to Tauri resources
log_step "Step 4: Copying Release to Tauri Resources"

TAURI_RESOURCES="$REPO_ROOT/apps/leaxer_desktop/src-tauri/resources"
RELEASE_DIR="$REPO_ROOT/_build/$MIX_ENV/rel/leaxer_core"

log_info "Removing old resources..."
rm -rf "$TAURI_RESOURCES/leaxer_core"

log_info "Copying fresh release..."
mkdir -p "$TAURI_RESOURCES"
cp -r "$RELEASE_DIR" "$TAURI_RESOURCES/"

log_success "Release copied to Tauri resources"

# Step 5: Verify Tauri bundle
log_step "Step 5: Verifying Tauri Bundle"
"$SCRIPT_DIR/verify-bundle.sh" --target "$TARGET" --tauri

# Step 6: Build frontend
if [[ "$SKIP_FRONTEND" != "true" ]] && [[ "$SKIP_TAURI" != "true" ]]; then
    log_step "Step 6: Building Frontend"

    cd "$REPO_ROOT/apps/leaxer_ui"

    log_info "Installing frontend dependencies..."
    npm ci

    log_info "Building frontend..."
    npm run build

    log_success "Frontend built successfully"
    cd "$REPO_ROOT"
else
    log_step "Step 6: Skipping Frontend Build"
fi

# Step 7: Build Tauri app
if [[ "$SKIP_TAURI" != "true" ]]; then
    log_step "Step 7: Building Tauri App"

    cd "$REPO_ROOT/apps/leaxer_desktop"

    log_info "Installing Tauri CLI..."
    npm ci

    log_info "Building Tauri app..."
    npm run build

    log_success "Tauri app built successfully"

    # List generated artifacts
    log_info ""
    log_info "Generated artifacts:"

    case "$TARGET" in
        *darwin*)
            ls -la src-tauri/target/release/bundle/dmg/*.dmg 2>/dev/null || true
            ls -la src-tauri/target/release/bundle/macos/*.app.tar.gz 2>/dev/null || true
            ;;
        *linux*)
            ls -la src-tauri/target/release/bundle/deb/*.deb 2>/dev/null || true
            ls -la src-tauri/target/release/bundle/appimage/*.AppImage 2>/dev/null || true
            ;;
        *windows*)
            ls -la src-tauri/target/release/bundle/msi/*.msi 2>/dev/null || true
            ls -la src-tauri/target/release/bundle/nsis/*.exe 2>/dev/null || true
            ;;
    esac

    cd "$REPO_ROOT"
else
    log_step "Step 7: Skipping Tauri Build (--skip-tauri)"
fi

# Done
log_step "Build Complete"
log_success "Desktop build finished successfully for $TARGET"
