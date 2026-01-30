# Leaxer Build Scripts

This directory contains unified build scripts used for both local development and CI/CD.

## Quick Start

### Full Desktop Build (Recommended)

```bash
# Unix/macOS/Linux (or Git Bash on Windows)
./scripts/build-desktop.sh

# Windows PowerShell
.\scripts\build-desktop.ps1
```

### Individual Steps

```bash
# 1. Download dependencies only
./scripts/download-deps.sh

# 2. Verify downloaded files
./scripts/verify-bundle.sh

# 3. Full build with options
./scripts/build-desktop.sh --skip-download  # Skip re-downloading deps
./scripts/build-desktop.sh --skip-tauri     # Only build Elixir release
```

## Scripts

| Script | Description |
|--------|-------------|
| `download-deps.sh` | Downloads all dependency binaries from GitHub releases |
| `verify-bundle.sh` | Verifies all required files are present |
| `build-desktop.sh` | Full desktop build (download, build, verify, package) |
| `build-desktop.ps1` | Windows PowerShell version of build-desktop.sh |
| `download-binaries.mjs` | Node.js alternative for downloading (local dev only) |

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `GH_TOKEN` | GitHub token for downloading from private repos | Yes (or `gh auth login`) |
| `MIX_ENV` | Elixir environment (default: `prod`) | No |

## Dependency Versions

All dependency versions are managed in `deps.versions.json` at the repo root:

```json
{
  "leaxer-llama": "v0.1.0",
  "leaxer-stable-diffusion": "v0.1.0",
  "leaxer-grounding-dino": "v0.1.0",
  "leaxer-sam": "v0.1.0",
  "leaxer-realesrgan": "v0.1.0"
}
```

## Windows DLL Requirements

For Windows builds, the following DLLs are required:

### Critical (Required)
- `llama.dll` - Core llama.cpp library
- `ggml.dll` - GGML tensor library
- `ggml-base.dll` - GGML base operations
- `ggml-cpu.dll` - GGML CPU backend

### CUDA Support (Optional, ~600MB)
- `ggml-cuda.dll` - GGML CUDA backend
- `cublas64_12.dll` - CUDA BLAS library
- `cublasLt64_12.dll` - CUDA BLAS Lt library
- `cudart64_12.dll` - CUDA runtime

## CI/CD

The GitHub Actions workflow (`.github/workflows/release.yml`) uses these same scripts:

```yaml
- name: Download dependency binaries
  run: ./scripts/download-deps.sh --target "${{ matrix.target }}"

- name: Verify downloaded dependencies
  run: ./scripts/verify-bundle.sh --target "${{ matrix.target }}"

- name: Verify Tauri bundle
  run: ./scripts/verify-bundle.sh --target "${{ matrix.target }}" --tauri
```

## Troubleshooting

### DLL Not Found Errors (Windows)

If you see `STATUS_DLL_NOT_FOUND` errors:

1. Run verification: `./scripts/verify-bundle.sh`
2. Check that all critical DLLs are present
3. Ensure DLLs are in the same directory as the executable

### Download Failures

1. Ensure `gh` CLI is installed and authenticated
2. Check that `GH_TOKEN` is set or run `gh auth login`
3. Verify release versions in `deps.versions.json` exist

### Build Failures

1. Run with verbose output: `MIX_ENV=prod mix release --verbose`
2. Check Elixir/OTP versions match CI (Elixir 1.18, OTP 27)
3. Ensure all dependencies are fetched: `mix deps.get`
