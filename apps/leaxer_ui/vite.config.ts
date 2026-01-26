import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import path from 'path'
import fs from 'fs'
import os from 'os'

// Get the Leaxer user data directory based on OS
function getLeaxerUserDir(): string {
  const customDir = process.env.LEAXER_USER_DIR
  if (customDir) return customDir

  const platform = os.platform()
  const homeDir = os.homedir()

  if (platform === 'win32') {
    return path.join(homeDir, 'Documents', 'Leaxer')
  } else if (platform === 'darwin') {
    return path.join(homeDir, 'Documents', 'Leaxer')
  } else {
    // Linux - use XDG spec
    const xdgData = process.env.XDG_DATA_HOME || path.join(homeDir, '.local', 'share')
    return path.join(xdgData, 'Leaxer')
  }
}

// Check if network exposure is enabled in config.json
function isNetworkExposureEnabled(): boolean {
  try {
    const configPath = path.join(getLeaxerUserDir(), 'config.json')
    const content = fs.readFileSync(configPath, 'utf-8')
    const config = JSON.parse(content)
    return config.network_exposure_enabled === true
  } catch {
    return false
  }
}

const networkExposureEnabled = isNetworkExposureEnabled()

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    // Bind to 0.0.0.0 when network exposure is enabled in config.json
    host: networkExposureEnabled ? '0.0.0.0' : 'localhost',
    port: 8888,
    strictPort: true,
    proxy: {
      '/api': {
        target: 'http://localhost:4000',
        changeOrigin: true,
      },
    },
  },
  preview: {
    host: networkExposureEnabled ? '0.0.0.0' : 'localhost',
    port: 8888,
  },
})
