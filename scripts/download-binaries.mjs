#!/usr/bin/env node
/**
 * Download dependency binaries from GitHub releases.
 * Cross-platform Node.js script for local development.
 *
 * NOTE: For CI/CD, use the bash scripts instead:
 *   - scripts/download-deps.sh
 *   - scripts/build-desktop.sh
 *
 * Usage: node scripts/download-binaries.mjs
 *
 * Reads versions from deps.versions.json
 */

import { execSync } from "child_process";
import { existsSync, mkdirSync, renameSync, readdirSync, chmodSync, readFileSync } from "fs";
import { join, basename } from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const ROOT_DIR = dirname(__dirname);
const BIN_DIR = join(ROOT_DIR, "apps", "leaxer_core", "priv", "bin");
const TEMP_DIR = join(ROOT_DIR, ".tmp-bins");
const DEPS_FILE = join(ROOT_DIR, "deps.versions.json");

// Read dependency versions from deps.versions.json
function loadVersions() {
  if (!existsSync(DEPS_FILE)) {
    console.error(`Error: ${DEPS_FILE} not found`);
    process.exit(1);
  }
  const content = readFileSync(DEPS_FILE, "utf-8");
  return JSON.parse(content);
}

const VERSIONS = loadVersions();

// Detect platform
function detectPlatform() {
  const platform = process.platform;
  const arch = process.arch;

  if (platform === "darwin") {
    return arch === "arm64" ? "aarch64-apple-darwin" : "x86_64-apple-darwin";
  } else if (platform === "linux") {
    return "x86_64-unknown-linux-gnu";
  } else if (platform === "win32") {
    return "x86_64-pc-windows-msvc";
  }
  throw new Error(`Unsupported platform: ${platform}`);
}

// Run gh CLI command
function gh(args, opts = {}) {
  try {
    return execSync(`gh ${args}`, {
      encoding: "utf-8",
      stdio: opts.silent ? "pipe" : "inherit",
      ...opts,
    });
  } catch (e) {
    if (!opts.ignoreError) throw e;
    return null;
  }
}

// Download release assets matching pattern
function downloadRelease(repo, version, pattern, destDir) {
  mkdirSync(destDir, { recursive: true });

  console.log(`  Downloading ${repo}@${version} (${pattern})...`);
  gh(
    `release download ${version} --repo leaxer-ai/${repo} --pattern "${pattern}" --dir "${destDir}" --clobber`,
    { ignoreError: true }
  );
}

// Main
async function main() {
  const platform = detectPlatform();
  const isWindows = platform.includes("windows");
  const ext = isWindows ? ".exe" : "";

  console.log("==========================================");
  console.log("  Downloading Dependency Binaries");
  console.log("==========================================");
  console.log(`Platform: ${platform}\n`);

  mkdirSync(BIN_DIR, { recursive: true });
  mkdirSync(TEMP_DIR, { recursive: true });

  // Clean temp
  for (const f of readdirSync(TEMP_DIR)) {
    try {
      const p = join(TEMP_DIR, f);
      if (existsSync(p)) execSync(isWindows ? `del /f "${p}"` : `rm -f "${p}"`, { stdio: "pipe" });
    } catch {}
  }

  // === leaxer-llama (arch-specific + DLLs on Windows + dylibs on macOS) ===
  console.log("\n=== leaxer-llama ===");
  downloadRelease("leaxer-llama", VERSIONS["leaxer-llama"], `*${platform}*`, TEMP_DIR);
  if (isWindows) {
    // Also download CUDA and ggml DLLs for Windows
    downloadRelease("leaxer-llama", VERSIONS["leaxer-llama"], "*.dll", TEMP_DIR);
  }
  if (platform.includes("darwin")) {
    // Also download dylibs for macOS if available
    downloadRelease("leaxer-llama", VERSIONS["leaxer-llama"], "*.dylib", TEMP_DIR);
  }
  for (const f of readdirSync(TEMP_DIR)) {
    if (f.includes(platform) || (isWindows && f.endsWith(".dll")) || f.endsWith(".dylib")) {
      const src = join(TEMP_DIR, f);
      const dest = join(BIN_DIR, f);
      renameSync(src, dest);
      if (!isWindows) chmodSync(dest, 0o755);
      console.log(`  ✓ ${f}`);
    }
  }

  // === leaxer-stable-diffusion (arch-specific + DLLs on Windows) ===
  console.log("\n=== leaxer-stable-diffusion ===");
  downloadRelease("leaxer-stable-diffusion", VERSIONS["leaxer-stable-diffusion"], `*${platform}*`, TEMP_DIR);
  if (isWindows) {
    // Also download CUDA DLLs for Windows (may overlap with llama, that's OK)
    downloadRelease("leaxer-stable-diffusion", VERSIONS["leaxer-stable-diffusion"], "*.dll", TEMP_DIR);
  }
  for (const f of readdirSync(TEMP_DIR)) {
    if (f.includes(platform) || (isWindows && f.endsWith(".dll"))) {
      const src = join(TEMP_DIR, f);
      const dest = join(BIN_DIR, f);
      renameSync(src, dest);
      if (!isWindows) chmodSync(dest, 0o755);
      console.log(`  ✓ ${f}`);
    }
  }

  // === leaxer-grounding-dino (simple binary) ===
  console.log("\n=== leaxer-grounding-dino ===");
  downloadRelease("leaxer-grounding-dino", VERSIONS["leaxer-grounding-dino"], `*${platform}*`, TEMP_DIR);
  for (const f of readdirSync(TEMP_DIR)) {
    if (f.includes(platform)) {
      const src = join(TEMP_DIR, f);
      const dest = join(BIN_DIR, `leaxer-grounding-dino${ext}`);
      renameSync(src, dest);
      if (!isWindows) chmodSync(dest, 0o755);
      console.log(`  ✓ leaxer-grounding-dino${ext}`);
    }
  }

  // === leaxer-sam (simple binary) ===
  console.log("\n=== leaxer-sam ===");
  downloadRelease("leaxer-sam", VERSIONS["leaxer-sam"], `*${platform}*`, TEMP_DIR);
  for (const f of readdirSync(TEMP_DIR)) {
    if (f.includes(platform)) {
      const src = join(TEMP_DIR, f);
      const dest = join(BIN_DIR, `leaxer-sam${ext}`);
      renameSync(src, dest);
      if (!isWindows) chmodSync(dest, 0o755);
      console.log(`  ✓ leaxer-sam${ext}`);
    }
  }

  // === leaxer-realesrgan (simple binary) ===
  console.log("\n=== leaxer-realesrgan ===");
  downloadRelease("leaxer-realesrgan", VERSIONS["leaxer-realesrgan"], `*${platform}*`, TEMP_DIR);
  for (const f of readdirSync(TEMP_DIR)) {
    if (f.includes(platform)) {
      const src = join(TEMP_DIR, f);
      const dest = join(BIN_DIR, `realesrgan-ncnn-vulkan${ext}`);
      renameSync(src, dest);
      if (!isWindows) chmodSync(dest, 0o755);
      console.log(`  ✓ realesrgan-ncnn-vulkan${ext}`);
    }
  }

  // Cleanup temp
  try {
    execSync(isWindows ? `rmdir /s /q "${TEMP_DIR}"` : `rm -rf "${TEMP_DIR}"`, { stdio: "pipe" });
  } catch {}

  console.log("\n==========================================");
  console.log("  Download Complete!");
  console.log("==========================================");
  console.log(`\nBinaries in: ${BIN_DIR}`);
  console.log(readdirSync(BIN_DIR).join("\n"));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
