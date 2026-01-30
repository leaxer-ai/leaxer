#!/usr/bin/env bash
# Download dependency binaries and DLLs for leaxer desktop build
#
# Usage: ./scripts/download-deps.sh [--target TARGET]
#
# Environment variables:
#   GH_TOKEN - GitHub token for downloading from private repos (required)
#   TARGET   - Target platform (auto-detected if not specified)
#
# This script downloads all required binaries from leaxer-ai GitHub releases
# and places them in apps/leaxer_core/priv/bin/

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() { echo -e "${CYAN}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Detect script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
BIN_DIR="$REPO_ROOT/apps/leaxer_core/priv/bin"
DEPS_FILE="$REPO_ROOT/deps.versions.json"

# Detect target platform
detect_target() {
    local os arch
    os="$(uname -s)"
    arch="$(uname -m)"

    case "$os" in
        Darwin)
            if [[ "$arch" == "arm64" ]]; then
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

# Get file extension for target
get_ext() {
    local target="$1"
    if [[ "$target" == *"windows"* ]]; then
        echo ".exe"
    else
        echo ""
    fi
}

# Download a release asset from GitHub
download_asset() {
    local repo="$1"
    local version="$2"
    local pattern="$3"
    local dest_name="$4"
    local required="${5:-true}"

    log_info "Downloading $dest_name from $repo@$version..."

    local tmpdir
    tmpdir=$(mktemp -d)

    if gh release download "$version" --repo "leaxer-ai/$repo" \
        --pattern "$pattern" --dir "$tmpdir" --clobber 2>/dev/null; then
        local downloaded
        downloaded=$(find "$tmpdir" -type f | head -1)
        if [[ -n "$downloaded" ]]; then
            cp "$downloaded" "$BIN_DIR/$dest_name"
            chmod +x "$BIN_DIR/$dest_name" 2>/dev/null || true
            log_success "  -> $dest_name ($(du -h "$BIN_DIR/$dest_name" | cut -f1))"
        fi
    else
        if [[ "$required" == "true" ]]; then
            log_error "  Failed to download $pattern from $repo@$version"
        else
            log_warn "  Optional: $pattern not found (skipped)"
        fi
    fi

    rm -rf "$tmpdir"
}

# Download Windows DLLs from llama release
download_windows_dlls() {
    local version="$1"

    log_info ""
    log_info "=== Downloading Windows DLLs ==="

    # Core llama DLLs
    download_asset "leaxer-llama" "$version" "llama.dll" "llama.dll"
    download_asset "leaxer-llama" "$version" "ggml.dll" "ggml.dll"
    download_asset "leaxer-llama" "$version" "ggml-base.dll" "ggml-base.dll"
    download_asset "leaxer-llama" "$version" "ggml-cpu.dll" "ggml-cpu.dll"

    # CUDA DLLs (optional but needed for GPU support)
    download_asset "leaxer-llama" "$version" "ggml-cuda.dll" "ggml-cuda.dll" "false"
    download_asset "leaxer-llama" "$version" "cublas64_12.dll" "cublas64_12.dll" "false"
    download_asset "leaxer-llama" "$version" "cublasLt64_12.dll" "cublasLt64_12.dll" "false"
    download_asset "leaxer-llama" "$version" "cudart64_12.dll" "cudart64_12.dll" "false"

    # Additional DLLs
    download_asset "leaxer-llama" "$version" "mtmd.dll" "mtmd.dll" "false"
}

# Main download function
download_all() {
    local target="$1"
    local ext
    ext=$(get_ext "$target")

    # Read versions from deps.versions.json
    if [[ ! -f "$DEPS_FILE" ]]; then
        log_error "deps.versions.json not found at $DEPS_FILE"
        exit 1
    fi

    local LLAMA_VER SD_VER GDINO_VER SAM_VER ESRGAN_VER
    LLAMA_VER=$(jq -r '.["leaxer-llama"]' "$DEPS_FILE")
    SD_VER=$(jq -r '.["leaxer-stable-diffusion"]' "$DEPS_FILE")
    GDINO_VER=$(jq -r '.["leaxer-grounding-dino"]' "$DEPS_FILE")
    SAM_VER=$(jq -r '.["leaxer-sam"]' "$DEPS_FILE")
    ESRGAN_VER=$(jq -r '.["leaxer-realesrgan"]' "$DEPS_FILE")

    log_info ""
    log_info "=========================================="
    log_info "Dependency versions from deps.versions.json"
    log_info "=========================================="
    log_info "leaxer-llama:            $LLAMA_VER"
    log_info "leaxer-stable-diffusion: $SD_VER"
    log_info "leaxer-grounding-dino:   $GDINO_VER"
    log_info "leaxer-sam:              $SAM_VER"
    log_info "leaxer-realesrgan:       $ESRGAN_VER"
    log_info ""
    log_info "Target platform: $target"
    log_info "Binary directory: $BIN_DIR"
    log_info ""

    # Create bin directory
    mkdir -p "$BIN_DIR"

    # Download llama binaries
    log_info "=== Downloading llama binaries ==="
    download_asset "leaxer-llama" "$LLAMA_VER" "llama-cli-${target}${ext}" "llama-cli-${target}${ext}"
    download_asset "leaxer-llama" "$LLAMA_VER" "llama-server-${target}${ext}" "llama-server-${target}${ext}"

    # GPU variants
    case "$target" in
        x86_64-unknown-linux-gnu|x86_64-pc-windows-msvc)
            download_asset "leaxer-llama" "$LLAMA_VER" "llama-cli-${target}-cuda${ext}" "llama-cli-${target}-cuda${ext}" "false"
            download_asset "leaxer-llama" "$LLAMA_VER" "llama-server-${target}-cuda${ext}" "llama-server-${target}-cuda${ext}" "false"
            ;;
        aarch64-apple-darwin)
            download_asset "leaxer-llama" "$LLAMA_VER" "llama-cli-${target}-metal" "llama-cli-${target}-metal" "false"
            download_asset "leaxer-llama" "$LLAMA_VER" "llama-server-${target}-metal" "llama-server-${target}-metal" "false"
            ;;
    esac

    # Download Windows DLLs
    if [[ "$target" == *"windows"* ]]; then
        download_windows_dlls "$LLAMA_VER"
    fi

    # Download stable-diffusion binaries
    log_info ""
    log_info "=== Downloading stable-diffusion binaries ==="
    download_asset "leaxer-stable-diffusion" "$SD_VER" "sd-${target}${ext}" "sd-${target}${ext}"
    download_asset "leaxer-stable-diffusion" "$SD_VER" "sd-server-${target}${ext}" "sd-server-${target}${ext}" "false"

    case "$target" in
        x86_64-unknown-linux-gnu|x86_64-pc-windows-msvc)
            download_asset "leaxer-stable-diffusion" "$SD_VER" "sd-${target}-cuda${ext}" "sd-${target}-cuda${ext}" "false"
            download_asset "leaxer-stable-diffusion" "$SD_VER" "sd-server-${target}-cuda${ext}" "sd-server-${target}-cuda${ext}" "false"
            ;;
        aarch64-apple-darwin)
            download_asset "leaxer-stable-diffusion" "$SD_VER" "sd-${target}-metal" "sd-${target}-metal" "false"
            download_asset "leaxer-stable-diffusion" "$SD_VER" "sd-server-${target}-metal" "sd-server-${target}-metal" "false"
            ;;
    esac

    # Download other binaries
    log_info ""
    log_info "=== Downloading other binaries ==="
    download_asset "leaxer-grounding-dino" "$GDINO_VER" "leaxer-grounding-dino-${target}${ext}" "leaxer-grounding-dino${ext}"
    download_asset "leaxer-sam" "$SAM_VER" "leaxer-sam-${target}${ext}" "leaxer-sam${ext}"
    download_asset "leaxer-realesrgan" "$ESRGAN_VER" "realesrgan-ncnn-vulkan-${target}${ext}" "realesrgan-ncnn-vulkan${ext}"

    log_info ""
    log_info "=== Download complete ==="
    log_info ""
    log_info "Downloaded files:"
    ls -la "$BIN_DIR/" || true
}

# Parse arguments
TARGET=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            TARGET="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--target TARGET]"
            echo ""
            echo "Options:"
            echo "  --target TARGET  Target platform (default: auto-detect)"
            echo "                   Examples: x86_64-pc-windows-msvc, aarch64-apple-darwin"
            echo ""
            echo "Environment variables:"
            echo "  GH_TOKEN         GitHub token for downloading releases (required)"
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

# Check for required tools
if ! command -v gh &>/dev/null; then
    log_error "GitHub CLI (gh) is required but not installed"
    log_error "Install from: https://cli.github.com/"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    log_error "jq is required but not installed"
    exit 1
fi

# Check for GH_TOKEN
if [[ -z "${GH_TOKEN:-}" ]]; then
    # Try to use gh auth status
    if ! gh auth status &>/dev/null; then
        log_error "GH_TOKEN environment variable not set and gh not authenticated"
        log_error "Either set GH_TOKEN or run: gh auth login"
        exit 1
    fi
fi

# Run download
download_all "$TARGET"
