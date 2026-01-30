# Build the Leaxer desktop application (Windows PowerShell)
#
# Usage: .\scripts\build-desktop.ps1 [OPTIONS]
#
# This script performs the complete desktop build:
#   1. Downloads dependency binaries (optional, skip with -SkipDownload)
#   2. Builds the Elixir release
#   3. Copies release to Tauri resources
#   4. Verifies all required files
#   5. Builds the Tauri app (optional, skip with -SkipTauri)
#
# Environment variables:
#   GH_TOKEN   - GitHub token for downloading releases
#   MIX_ENV    - Elixir environment (default: prod)

param(
    [switch]$SkipDownload,
    [switch]$SkipTauri,
    [switch]$SkipFrontend,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# Configuration
$Target = "x86_64-pc-windows-msvc"
$Ext = ".exe"
$MixEnv = if ($env:MIX_ENV) { $env:MIX_ENV } else { "prod" }

# Detect script directory and repo root
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

# Paths
$BinDir = Join-Path $RepoRoot "apps\leaxer_core\priv\bin"
$DepsFile = Join-Path $RepoRoot "deps.versions.json"
$TauriResources = Join-Path $RepoRoot "apps\leaxer_desktop\src-tauri\resources"
$ReleaseDir = Join-Path $RepoRoot "_build\$MixEnv\rel\leaxer_core"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

if ($Help) {
    Write-Host "Usage: .\scripts\build-desktop.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -SkipDownload    Skip downloading dependency binaries"
    Write-Host "  -SkipFrontend    Skip building frontend (assumes already built)"
    Write-Host "  -SkipTauri       Skip building Tauri app (only build Elixir release)"
    Write-Host "  -Help            Show this help message"
    Write-Host ""
    Write-Host "Environment variables:"
    Write-Host "  GH_TOKEN         GitHub token for downloading releases"
    Write-Host "  MIX_ENV          Elixir environment (default: prod)"
    exit 0
}

# Print build configuration
Write-Step "Build Configuration"
Write-Info "Repository root: $RepoRoot"
Write-Info "Target platform: $Target"
Write-Info "MIX_ENV: $MixEnv"
Write-Info "Skip download: $SkipDownload"
Write-Info "Skip frontend: $SkipFrontend"
Write-Info "Skip Tauri: $SkipTauri"

# Change to repo root
Set-Location $RepoRoot

# ============================================================================
# Step 1: Download dependencies
# ============================================================================
if (-not $SkipDownload) {
    Write-Step "Step 1: Downloading Dependencies"

    # Check for gh CLI
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Error "GitHub CLI (gh) is required but not installed"
        Write-Error "Install from: https://cli.github.com/"
        exit 1
    }

    # Check for jq
    if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
        Write-Error "jq is required but not installed"
        Write-Error "Install from: https://stedolan.github.io/jq/download/"
        exit 1
    }

    # Read versions
    if (-not (Test-Path $DepsFile)) {
        Write-Error "deps.versions.json not found at $DepsFile"
        exit 1
    }

    $LlamaVer = jq -r '.["leaxer-llama"]' $DepsFile
    $SdVer = jq -r '.["leaxer-stable-diffusion"]' $DepsFile
    $GdinoVer = jq -r '.["leaxer-grounding-dino"]' $DepsFile
    $SamVer = jq -r '.["leaxer-sam"]' $DepsFile
    $EsrganVer = jq -r '.["leaxer-realesrgan"]' $DepsFile

    Write-Info "leaxer-llama: $LlamaVer"
    Write-Info "leaxer-stable-diffusion: $SdVer"
    Write-Info "leaxer-grounding-dino: $GdinoVer"
    Write-Info "leaxer-sam: $SamVer"
    Write-Info "leaxer-realesrgan: $EsrganVer"

    # Create bin directory
    if (-not (Test-Path $BinDir)) {
        New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    }

    # Download function
    function Download-Asset {
        param(
            [string]$Repo,
            [string]$Version,
            [string]$Pattern,
            [string]$DestName,
            [bool]$Required = $true
        )

        Write-Info "Downloading $DestName from $Repo@$Version..."

        $TmpDir = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_ }

        try {
            gh release download $Version --repo "leaxer-ai/$Repo" --pattern $Pattern --dir $TmpDir --clobber 2>$null
            $Downloaded = Get-ChildItem $TmpDir | Select-Object -First 1

            if ($Downloaded) {
                Copy-Item $Downloaded.FullName (Join-Path $BinDir $DestName) -Force
                $Size = [math]::Round($Downloaded.Length / 1MB, 2)
                Write-Success "  -> $DestName ($Size MB)"
            }
        }
        catch {
            if ($Required) {
                Write-Error "  Failed to download $Pattern from $Repo@$Version"
            }
            else {
                Write-Warning "  Optional: $Pattern not found (skipped)"
            }
        }
        finally {
            Remove-Item $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Download llama binaries
    Write-Host ""
    Write-Info "=== Downloading llama binaries ==="
    Download-Asset "leaxer-llama" $LlamaVer "llama-cli-$Target$Ext" "llama-cli-$Target$Ext"
    Download-Asset "leaxer-llama" $LlamaVer "llama-server-$Target$Ext" "llama-server-$Target$Ext"
    Download-Asset "leaxer-llama" $LlamaVer "llama-cli-$Target-cuda$Ext" "llama-cli-$Target-cuda$Ext" $false
    Download-Asset "leaxer-llama" $LlamaVer "llama-server-$Target-cuda$Ext" "llama-server-$Target-cuda$Ext" $false

    # Download Windows DLLs
    Write-Host ""
    Write-Info "=== Downloading Windows DLLs ==="
    Download-Asset "leaxer-llama" $LlamaVer "llama.dll" "llama.dll"
    Download-Asset "leaxer-llama" $LlamaVer "ggml.dll" "ggml.dll"
    Download-Asset "leaxer-llama" $LlamaVer "ggml-base.dll" "ggml-base.dll"
    Download-Asset "leaxer-llama" $LlamaVer "ggml-cpu.dll" "ggml-cpu.dll"
    Download-Asset "leaxer-llama" $LlamaVer "ggml-cuda.dll" "ggml-cuda.dll" $false
    Download-Asset "leaxer-llama" $LlamaVer "cublas64_12.dll" "cublas64_12.dll" $false
    Download-Asset "leaxer-llama" $LlamaVer "cublasLt64_12.dll" "cublasLt64_12.dll" $false
    Download-Asset "leaxer-llama" $LlamaVer "cudart64_12.dll" "cudart64_12.dll" $false
    Download-Asset "leaxer-llama" $LlamaVer "mtmd.dll" "mtmd.dll" $false

    # Download stable-diffusion
    Write-Host ""
    Write-Info "=== Downloading stable-diffusion binaries ==="
    Download-Asset "leaxer-stable-diffusion" $SdVer "sd-$Target$Ext" "sd-$Target$Ext"
    Download-Asset "leaxer-stable-diffusion" $SdVer "sd-server-$Target$Ext" "sd-server-$Target$Ext" $false
    Download-Asset "leaxer-stable-diffusion" $SdVer "sd-$Target-cuda$Ext" "sd-$Target-cuda$Ext" $false
    Download-Asset "leaxer-stable-diffusion" $SdVer "sd-server-$Target-cuda$Ext" "sd-server-$Target-cuda$Ext" $false

    # Download other binaries
    Write-Host ""
    Write-Info "=== Downloading other binaries ==="
    Download-Asset "leaxer-grounding-dino" $GdinoVer "leaxer-grounding-dino-$Target$Ext" "leaxer-grounding-dino$Ext"
    Download-Asset "leaxer-sam" $SamVer "leaxer-sam-$Target$Ext" "leaxer-sam$Ext"
    Download-Asset "leaxer-realesrgan" $EsrganVer "realesrgan-ncnn-vulkan-$Target$Ext" "realesrgan-ncnn-vulkan$Ext"
}
else {
    Write-Step "Step 1: Skipping Download (-SkipDownload)"
}

# ============================================================================
# Step 2: Verify downloaded dependencies
# ============================================================================
Write-Step "Step 2: Verifying Downloaded Dependencies"

$CriticalFiles = @(
    "llama-server-$Target$Ext",
    "llama-cli-$Target$Ext",
    "sd-$Target$Ext",
    "leaxer-grounding-dino$Ext",
    "leaxer-sam$Ext",
    "realesrgan-ncnn-vulkan$Ext",
    "llama.dll",
    "ggml.dll",
    "ggml-base.dll",
    "ggml-cpu.dll"
)

$VerifyErrors = 0
foreach ($File in $CriticalFiles) {
    $Path = Join-Path $BinDir $File
    if (Test-Path $Path) {
        $Size = [math]::Round((Get-Item $Path).Length / 1MB, 2)
        Write-Success "$File ($Size MB)"
    }
    else {
        Write-Error "$File - MISSING (REQUIRED)"
        $VerifyErrors++
    }
}

if ($VerifyErrors -gt 0) {
    Write-Error "Verification failed: $VerifyErrors required file(s) missing"
    exit 1
}

Write-Success "All critical files present"

# ============================================================================
# Step 3: Build Elixir release
# ============================================================================
Write-Step "Step 3: Building Elixir Release"

Write-Info "Installing Elixir dependencies..."
mix deps.get --only $MixEnv

Write-Info "Compiling..."
$env:MIX_ENV = $MixEnv
mix compile

Write-Info "Building release..."
mix release leaxer_core --overwrite

Write-Success "Elixir release built successfully"

# ============================================================================
# Step 4: Copy release to Tauri resources
# ============================================================================
Write-Step "Step 4: Copying Release to Tauri Resources"

Write-Info "Removing old resources..."
if (Test-Path "$TauriResources\leaxer_core") {
    Remove-Item "$TauriResources\leaxer_core" -Recurse -Force
}

Write-Info "Copying fresh release..."
if (-not (Test-Path $TauriResources)) {
    New-Item -ItemType Directory -Path $TauriResources -Force | Out-Null
}
Copy-Item $ReleaseDir "$TauriResources\leaxer_core" -Recurse

Write-Success "Release copied to Tauri resources"

# ============================================================================
# Step 5: Verify Tauri bundle
# ============================================================================
Write-Step "Step 5: Verifying Tauri Bundle"

$TauriBinDir = "$TauriResources\leaxer_core\lib\leaxer_core-0.1.0\priv\bin"

if (-not (Test-Path $TauriBinDir)) {
    Write-Error "Tauri bin directory not found: $TauriBinDir"
    exit 1
}

$TauriVerifyErrors = 0
foreach ($File in $CriticalFiles) {
    $Path = Join-Path $TauriBinDir $File
    if (Test-Path $Path) {
        $Size = [math]::Round((Get-Item $Path).Length / 1MB, 2)
        Write-Success "$File ($Size MB)"
    }
    else {
        Write-Error "$File - MISSING"
        $TauriVerifyErrors++
    }
}

if ($TauriVerifyErrors -gt 0) {
    Write-Error "Tauri bundle verification failed: $TauriVerifyErrors file(s) missing"
    exit 1
}

Write-Success "Tauri bundle verified successfully"

# Calculate total size
$TotalSize = (Get-ChildItem $TauriBinDir | Measure-Object -Property Length -Sum).Sum / 1MB
Write-Info "Total bundle size: $([math]::Round($TotalSize, 2)) MB"

# ============================================================================
# Step 6: Build frontend
# ============================================================================
if (-not $SkipFrontend -and -not $SkipTauri) {
    Write-Step "Step 6: Building Frontend"

    Set-Location (Join-Path $RepoRoot "apps\leaxer_ui")

    Write-Info "Installing frontend dependencies..."
    npm ci

    Write-Info "Building frontend..."
    npm run build

    Write-Success "Frontend built successfully"
    Set-Location $RepoRoot
}
else {
    Write-Step "Step 6: Skipping Frontend Build"
}

# ============================================================================
# Step 7: Build Tauri app
# ============================================================================
if (-not $SkipTauri) {
    Write-Step "Step 7: Building Tauri App"

    Set-Location (Join-Path $RepoRoot "apps\leaxer_desktop")

    Write-Info "Installing Tauri CLI..."
    npm ci

    Write-Info "Building Tauri app..."
    npm run build

    Write-Success "Tauri app built successfully"

    Write-Host ""
    Write-Info "Generated artifacts:"
    Get-ChildItem "src-tauri\target\release\bundle\msi\*.msi" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "  $($_.FullName)" -ForegroundColor Gray
    }
    Get-ChildItem "src-tauri\target\release\bundle\nsis\*.exe" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "  $($_.FullName)" -ForegroundColor Gray
    }

    Set-Location $RepoRoot
}
else {
    Write-Step "Step 7: Skipping Tauri Build (-SkipTauri)"
}

# ============================================================================
# Done
# ============================================================================
Write-Step "Build Complete"
Write-Success "Desktop build finished successfully for $Target"
