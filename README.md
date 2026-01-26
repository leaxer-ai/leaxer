# Leaxer AI

An engine for local AI inference, built on Elixir and the BEAM virtual machine.

## Features

### Chat Interface

Conversational interface for language models:

- Real-time streaming responses
- Web search integration for current information
- Document generation from research
- Message branching to compare model outputs
- Session management with chat history
- "Thinking" mode for extended chat context reasoning

### Node Inteface

- Visual node graph editor
- Batch processing with wildcards and directory iteration
- Conditional branching and loop control

## Supported Models

### Diffusion Model Inference

Via stable-diffusion.cpp:

- SD 1.5, SDXL, SD 3.5, FLUX.1, Chroma
- Text-to-image, img2img, inpainting
- LoRA stacking, ControlNet, PhotoMaker
- VAE swapping and TAESD preview
- Video generation (Wan2.1, Wan2.2)

### Language Model Inference

Via llama.cpp:

- GGUF model loading with quantization
- Prompt enhancement and templating
- Configurable generation parameters

### Vision Model Inference

- GroundingDINO for object detection
- Segment Anything (SAM) for mask generation
- RealESRGAN upscaling

## Supported Backends

| Backend   | Platform           | GPU Support        |
|-----------|--------------------|--------------------|
| Metal     | macOS              | Apple Silicon      |
| CUDA      | Linux, Windows     | NVIDIA             |
| DirectML  | Windows            | AMD, Intel, NVIDIA |
| Vulkan    | Cross-platform     | AMD, NVIDIA        |
| CPU       | All                | Fallback           |

## Architecture

- **Backend** (`/apps/leaxer_core`) — Elixir application handling workflow scheduling and process supervision. Communicates with inference engines via Erlang Ports.
- **Frontend** (`/apps/leaxer_ui`) — React application with node graph editor. Connects via Phoenix WebSocket.
- **Desktop** (`/apps/leaxer_desktop`) — Tauri packaging for local deployment.

## Building from Source

### Prerequisites

| Requirement | Version | All Platforms |
|-------------|---------|---------------|
| Node.js | 20+ | Yes |
| Rust | stable | Yes |
| Elixir | 1.18+ | Yes |
| OTP | 27+ | Yes |
| GitHub CLI | latest | Yes |

**Windows:** Visual Studio Build Tools 2019+ with C++ workload, WebView2

**macOS:** Xcode Command Line Tools (`xcode-select --install`)

**Linux (Ubuntu/Debian):**
```bash
sudo apt-get install -y libgtk-3-dev libwebkit2gtk-4.1-dev \
  libappindicator3-dev librsvg2-dev patchelf
```

### Build Steps

```bash
# 1. Clone and enter directory
git clone https://github.com/leaxer-ai/leaxer.git && cd leaxer

# 2. Download pre-built AI binaries
npm run setup

# 3. Build Elixir backend release
mix deps.get --only prod
MIX_ENV=prod mix compile
MIX_ENV=prod mix release leaxer_core --overwrite

# 4. Copy backend to Tauri resources
# Windows (PowerShell):
xcopy /E /I /Y _build\prod\rel\leaxer_core apps\leaxer_desktop\src-tauri\resources\leaxer_core
# macOS/Linux:
cp -r _build/prod/rel/leaxer_core apps/leaxer_desktop/src-tauri/resources/

# 5. Build frontend
cd apps/leaxer_ui && npm ci && npm run build && cd ../..

# 6. Build desktop installer
cd apps/leaxer_desktop && npm ci && npm run build
```

### Build Outputs

| Platform | Installer | Location |
|----------|-----------|----------|
| Windows | MSI | `apps/leaxer_desktop/src-tauri/target/release/bundle/msi/` |
| Windows | EXE (NSIS) | `apps/leaxer_desktop/src-tauri/target/release/bundle/nsis/` |
| macOS | DMG | `apps/leaxer_desktop/src-tauri/target/release/bundle/dmg/` |
| Linux | AppImage | `apps/leaxer_desktop/src-tauri/target/release/bundle/appimage/` |
| Linux | DEB | `apps/leaxer_desktop/src-tauri/target/release/bundle/deb/` |

### Development Mode

```bash
# Terminal 1: Backend
npm run dev:backend

# Terminal 2: Frontend (hot reload)
npm run dev:frontend

# Terminal 3: Desktop app
npm run dev:desktop
```

### Cleaning

```bash
npm run clean          # Clean build artifacts
npm run clean -- --all # Also clean node_modules and deps
```

## License

[Apache 2.0](LICENSE)

## Links

- [Leaxer Repository](https://github.com/leaxer-ai/leaxer)
- [Leaxer Stable Diffusion Repository](https://github.com/leaxer-ai/leaxer-stable-diffusion)
- [Leaxer LLaMA Repository](https://github.com/leaxer-ai/leaxer-llama)
- [Leaxer Grounding DINO Repository](https://github.com/leaxer-ai/leaxer-grounding-dino)
- [Leaxer SAM Reposotory](https://github.com/leaxer-ai/leaxer-sam)
- [Leaxer Real Esrgann Repository](https://github.com/leaxer-ai/leaxer-realesrgan)
