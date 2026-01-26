#!/usr/bin/env node
/**
 * Clean build artifacts.
 * Cross-platform Node.js script.
 *
 * Usage: node scripts/clean.mjs [--all]
 *   --all: Also clean node_modules and deps
 */

import { rmSync, existsSync } from "fs";
import { join } from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const ROOT_DIR = dirname(__dirname);

const includeAll = process.argv.includes("--all");

// Directories to always clean
const BUILD_DIRS = [
  "_build",
  ".tmp-bins",
  "apps/leaxer_ui/dist",
  "apps/leaxer_desktop/src-tauri/target",
  "apps/leaxer_desktop/src-tauri/resources/leaxer_core",
];

// Directories to clean only with --all flag
const ALL_DIRS = [
  "deps",
  "node_modules",
  "apps/leaxer_ui/node_modules",
  "apps/leaxer_desktop/node_modules",
];

function clean(dirs) {
  for (const dir of dirs) {
    const fullPath = join(ROOT_DIR, dir);
    if (existsSync(fullPath)) {
      console.log(`Removing ${dir}...`);
      try {
        rmSync(fullPath, { recursive: true, force: true });
        console.log(`  ✓ ${dir}`);
      } catch (e) {
        console.error(`  ✗ Failed to remove ${dir}: ${e.message}`);
      }
    }
  }
}

console.log("==========================================");
console.log("  Cleaning Build Artifacts");
console.log("==========================================\n");

clean(BUILD_DIRS);

if (includeAll) {
  console.log("\nCleaning dependencies (--all)...\n");
  clean(ALL_DIRS);
}

console.log("\n==========================================");
console.log("  Clean Complete!");
console.log("==========================================");

if (!includeAll) {
  console.log("\nTip: Use 'npm run clean -- --all' to also clean node_modules and deps");
}
