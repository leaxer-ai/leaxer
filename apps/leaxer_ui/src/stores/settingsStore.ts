import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import {
  type SoundName,
  DEFAULT_SOUNDS,
  updateSoundSettings,
  setVolume,
  setSoundsEnabled,
} from '@/lib/sounds';

const STORAGE_KEY = 'leaxer-settings';
const DEFAULT_THEME = 'leaxer-dark';

// Compute backend types per platform
export type MacBackend = 'auto' | 'metal' | 'cpu';
export type WindowsBackend = 'auto' | 'cuda' | 'directml' | 'cpu';
export type LinuxBackend = 'auto' | 'cuda' | 'vulkan' | 'cpu';
export type ComputeBackend = MacBackend | WindowsBackend | LinuxBackend;

// Detect platform
export const detectPlatform = (): 'mac' | 'windows' | 'linux' => {
  const platform = navigator.platform.toLowerCase();
  if (platform.includes('mac')) return 'mac';
  if (platform.includes('win')) return 'windows';
  return 'linux';
};

// Get available backends for the current platform
export const getAvailableBackends = (): { value: ComputeBackend; label: string; description: string }[] => {
  const platform = detectPlatform();

  switch (platform) {
    case 'mac':
      return [
        { value: 'cpu', label: 'CPU Only', description: 'Reliable, works on all Macs (slower)' },
        { value: 'metal', label: 'Metal (GPU)', description: 'Fast GPU acceleration (may have issues on M4)' },
        { value: 'auto', label: 'Auto', description: 'Automatically select best available' },
      ];
    case 'windows':
      return [
        { value: 'auto', label: 'Auto', description: 'Automatically detect CUDA or DirectML' },
        { value: 'cuda', label: 'CUDA (NVIDIA)', description: 'Best for NVIDIA GPUs' },
        { value: 'directml', label: 'DirectML', description: 'Works with AMD/Intel GPUs' },
        { value: 'cpu', label: 'CPU Only', description: 'Fallback, works everywhere (slower)' },
      ];
    case 'linux':
      return [
        { value: 'auto', label: 'Auto', description: 'Automatically detect CUDA or Vulkan' },
        { value: 'cuda', label: 'CUDA (NVIDIA)', description: 'Best for NVIDIA GPUs' },
        { value: 'vulkan', label: 'Vulkan', description: 'Works with AMD/Intel GPUs' },
        { value: 'cpu', label: 'CPU Only', description: 'Fallback, works everywhere (slower)' },
      ];
  }
};

// Get default backend for platform
const getDefaultBackend = (): ComputeBackend => {
  const platform = detectPlatform();
  // Default to CPU on Mac due to Metal issues, auto on others
  return platform === 'mac' ? 'cpu' : 'auto';
};

// Apply theme to document
const applyTheme = (theme: string) => {
  document.documentElement.setAttribute('data-theme', theme);
};

// Read theme from localStorage synchronously to avoid flash of wrong theme
const getStoredTheme = (): string => {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored) {
      const parsed = JSON.parse(stored);
      if (parsed.state?.theme) {
        return parsed.state.theme;
      }
    }
  } catch {
    // Ignore parse errors, use default
  }
  return DEFAULT_THEME;
};

// Apply stored theme immediately before React renders
const initialTheme = getStoredTheme();
applyTheme(initialTheme);

// Get the default backend URL based on current hostname
// This allows LAN access to work automatically
const getDefaultBackendUrl = (): string => {
  // In Tauri, use localhost
  if (window.location.hostname === 'tauri.localhost' || window.location.protocol === 'tauri:') {
    return 'ws://localhost:4000/socket';
  }
  // Use the same hostname the page is being accessed from
  const hostname = window.location.hostname;
  return `ws://${hostname}:4000/socket`;
};

// Get stored backend URL or compute default
const getStoredBackendUrl = (): string => {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored) {
      const parsed = JSON.parse(stored);
      if (parsed.state?.backendUrl) {
        return parsed.state.backendUrl;
      }
    }
  } catch {
    // Ignore parse errors, use default
  }
  return getDefaultBackendUrl();
};

export type EdgeType = 'bezier' | 'straight' | 'step' | 'smoothstep';

// Network info from backend
export interface NetworkInfo {
  network_exposure_enabled: boolean;
  local_ips: string[];
  current_binding: string;
  backend_port: number;
  frontend_port: number;
}

interface SettingsState {
  // Connection
  backendUrl: string;
  setBackendUrl: (url: string) => void;
  getApiBaseUrl: () => string;
  getBackendWsUrl: () => string;

  // Compute
  computeBackend: ComputeBackend;
  setComputeBackend: (backend: ComputeBackend) => void;

  // Editor
  showGrid: boolean;
  setShowGrid: (show: boolean) => void;
  snapToGrid: boolean;
  setSnapToGrid: (snap: boolean) => void;
  gridSize: number;
  setGridSize: (size: number) => void;
  edgeType: EdgeType;
  setEdgeType: (type: EdgeType) => void;
  showMinimap: boolean;
  setShowMinimap: (show: boolean) => void;

  // Appearance
  theme: string;
  setTheme: (theme: string) => void;

  // Sounds
  soundsEnabled: boolean;
  setSoundsEnabled: (enabled: boolean) => void;
  soundVolume: number;
  setSoundVolume: (volume: number) => void;
  soundStart: SoundName;
  setSoundStart: (sound: SoundName) => void;
  soundComplete: SoundName;
  setSoundComplete: (sound: SoundName) => void;
  soundError: SoundName;
  setSoundError: (sound: SoundName) => void;
  soundStop: SoundName;
  setSoundStop: (sound: SoundName) => void;
  soundSuccess: SoundName;
  setSoundSuccess: (sound: SoundName) => void;
  soundReturn: SoundName;
  setSoundReturn: (sound: SoundName) => void;

  // System / Autosave
  autosaveEnabled: boolean;
  setAutosaveEnabled: (enabled: boolean) => void;
  autosaveInterval: number; // in seconds
  setAutosaveInterval: (interval: number) => void;

  // Queue / Model Caching
  modelCachingStrategy: 'auto' | 'cli-mode' | 'server-mode';
  setModelCachingStrategy: (strategy: 'auto' | 'cli-mode' | 'server-mode') => void;

  // Window
  useFramelessWindow: boolean;
  setUseFramelessWindow: (enabled: boolean) => void;

  // Network (server-side settings, not persisted locally)
  networkExposureEnabled: boolean;
  networkRestartRequired: boolean;
  networkInfo: NetworkInfo | null;
  setNetworkExposureEnabled: (enabled: boolean) => Promise<void>;
  fetchNetworkInfo: () => Promise<void>;
  clearNetworkRestartRequired: () => void;
}

export const useSettingsStore = create<SettingsState>()(
  persist(
    (set, get) => ({
      // Connection
      backendUrl: getStoredBackendUrl(),
      setBackendUrl: (backendUrl) => set({ backendUrl }),
      getApiBaseUrl: () => {
        const wsUrl = get().backendUrl;
        // Convert ws://host:port/socket to http://host:port
        let baseUrl = wsUrl.replace(/\/socket$/, '').replace(/^ws/, 'http');

        // If the stored URL uses localhost but we're accessing from a different host,
        // dynamically substitute the current hostname (for LAN access)
        try {
          const url = new URL(baseUrl);
          const currentHost = window.location.hostname;

          // Only substitute if:
          // 1. The stored URL is localhost/127.0.0.1
          // 2. We're not in Tauri
          // 3. The current hostname is different (e.g., a LAN IP)
          const isLocalhost = url.hostname === 'localhost' || url.hostname === '127.0.0.1';
          const isTauri = currentHost === 'tauri.localhost' || window.location.protocol === 'tauri:';
          const isDifferentHost = currentHost !== 'localhost' && currentHost !== '127.0.0.1';

          if (isLocalhost && !isTauri && isDifferentHost) {
            url.hostname = currentHost;
            baseUrl = url.toString().replace(/\/$/, ''); // Remove trailing slash
          }
        } catch {
          // If URL parsing fails, return as-is
        }

        return baseUrl;
      },
      getBackendWsUrl: () => {
        const wsUrl = get().backendUrl;

        // If the stored URL uses localhost but we're accessing from a different host,
        // dynamically substitute the current hostname (for LAN access)
        try {
          const url = new URL(wsUrl.replace(/^ws/, 'http')); // Parse as http for URL API
          const currentHost = window.location.hostname;

          const isLocalhost = url.hostname === 'localhost' || url.hostname === '127.0.0.1';
          const isTauri = currentHost === 'tauri.localhost' || window.location.protocol === 'tauri:';
          const isDifferentHost = currentHost !== 'localhost' && currentHost !== '127.0.0.1';

          if (isLocalhost && !isTauri && isDifferentHost) {
            url.hostname = currentHost;
            // Convert back to ws://
            return url.toString().replace(/^http/, 'ws').replace(/\/$/, '');
          }
        } catch {
          // If URL parsing fails, return as-is
        }

        return wsUrl;
      },

      // Compute
      computeBackend: getDefaultBackend(),
      setComputeBackend: (computeBackend) => set({ computeBackend }),

      // Editor
      showGrid: true,
      setShowGrid: (showGrid) => set({ showGrid }),
      snapToGrid: true,
      setSnapToGrid: (snapToGrid) => set({ snapToGrid }),
      gridSize: 10,
      setGridSize: (gridSize) => set({ gridSize }),
      edgeType: 'smoothstep',
      setEdgeType: (edgeType) => set({ edgeType }),
      showMinimap: true,
      setShowMinimap: (showMinimap) => set({ showMinimap }),

      // Appearance
      theme: initialTheme,
      setTheme: (theme) => {
        applyTheme(theme);
        set({ theme });
      },

      // Sounds
      soundsEnabled: true,
      setSoundsEnabled: (soundsEnabled) => {
        setSoundsEnabled(soundsEnabled);
        set({ soundsEnabled });
      },
      soundVolume: 0.5,
      setSoundVolume: (soundVolume) => {
        setVolume(soundVolume);
        set({ soundVolume });
      },
      soundStart: DEFAULT_SOUNDS.start,
      setSoundStart: (soundStart) => {
        set({ soundStart });
        const state = get();
        updateSoundSettings({
          start: soundStart,
          complete: state.soundComplete,
          error: state.soundError,
          stop: state.soundStop,
          success: state.soundSuccess,
          return: state.soundReturn,
        });
      },
      soundComplete: DEFAULT_SOUNDS.complete,
      setSoundComplete: (soundComplete) => {
        set({ soundComplete });
        const state = get();
        updateSoundSettings({
          start: state.soundStart,
          complete: soundComplete,
          error: state.soundError,
          stop: state.soundStop,
          success: state.soundSuccess,
          return: state.soundReturn,
        });
      },
      soundError: DEFAULT_SOUNDS.error,
      setSoundError: (soundError) => {
        set({ soundError });
        const state = get();
        updateSoundSettings({
          start: state.soundStart,
          complete: state.soundComplete,
          error: soundError,
          stop: state.soundStop,
          success: state.soundSuccess,
          return: state.soundReturn,
        });
      },
      soundStop: DEFAULT_SOUNDS.stop,
      setSoundStop: (soundStop) => {
        set({ soundStop });
        const state = get();
        updateSoundSettings({
          start: state.soundStart,
          complete: state.soundComplete,
          error: state.soundError,
          stop: soundStop,
          success: state.soundSuccess,
          return: state.soundReturn,
        });
      },
      soundSuccess: DEFAULT_SOUNDS.success,
      setSoundSuccess: (soundSuccess) => {
        set({ soundSuccess });
        const state = get();
        updateSoundSettings({
          start: state.soundStart,
          complete: state.soundComplete,
          error: state.soundError,
          stop: state.soundStop,
          success: soundSuccess,
          return: state.soundReturn,
        });
      },
      soundReturn: DEFAULT_SOUNDS.return,
      setSoundReturn: (soundReturn) => {
        set({ soundReturn });
        const state = get();
        updateSoundSettings({
          start: state.soundStart,
          complete: state.soundComplete,
          error: state.soundError,
          stop: state.soundStop,
          success: state.soundSuccess,
          return: soundReturn,
        });
      },

      // System / Autosave
      autosaveEnabled: false, // Disabled by default
      setAutosaveEnabled: (autosaveEnabled) => set({ autosaveEnabled }),
      autosaveInterval: 60, // Default 1 minute (in seconds)
      setAutosaveInterval: (autosaveInterval) => set({ autosaveInterval }),

      // Queue / Model Caching
      modelCachingStrategy: 'auto',
      setModelCachingStrategy: (modelCachingStrategy) => set({ modelCachingStrategy }),

      // Window
      useFramelessWindow: true, // Default to frameless for cohesive look
      setUseFramelessWindow: (useFramelessWindow) => set({ useFramelessWindow }),

      // Network (server-side settings)
      networkExposureEnabled: false,
      networkRestartRequired: false,
      networkInfo: null,

      setNetworkExposureEnabled: async (enabled: boolean) => {
        try {
          const apiBaseUrl = get().getApiBaseUrl();
          const response = await fetch(`${apiBaseUrl}/api/settings`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ network_exposure_enabled: enabled }),
          });

          if (!response.ok) {
            throw new Error(`Failed to update setting: ${response.statusText}`);
          }

          const data = await response.json();
          set({
            networkExposureEnabled: enabled,
            networkRestartRequired: data.restart_required || false,
          });
        } catch (error) {
          console.error('Failed to update network exposure setting:', error);
          throw error;
        }
      },

      fetchNetworkInfo: async () => {
        try {
          const apiBaseUrl = get().getApiBaseUrl();
          const response = await fetch(`${apiBaseUrl}/api/settings/network-info`);

          if (!response.ok) {
            throw new Error(`Failed to fetch network info: ${response.statusText}`);
          }

          const data: NetworkInfo = await response.json();
          set({
            networkInfo: data,
            networkExposureEnabled: data.network_exposure_enabled,
          });
        } catch (error) {
          console.error('Failed to fetch network info:', error);
        }
      },

      clearNetworkRestartRequired: () => set({ networkRestartRequired: false }),
    }),
    {
      name: STORAGE_KEY,
      // Exclude server-side settings from localStorage persistence
      partialize: (state) => ({
        backendUrl: state.backendUrl,
        computeBackend: state.computeBackend,
        showGrid: state.showGrid,
        snapToGrid: state.snapToGrid,
        gridSize: state.gridSize,
        edgeType: state.edgeType,
        showMinimap: state.showMinimap,
        theme: state.theme,
        soundsEnabled: state.soundsEnabled,
        soundVolume: state.soundVolume,
        soundStart: state.soundStart,
        soundComplete: state.soundComplete,
        soundError: state.soundError,
        soundStop: state.soundStop,
        soundSuccess: state.soundSuccess,
        soundReturn: state.soundReturn,
        autosaveEnabled: state.autosaveEnabled,
        autosaveInterval: state.autosaveInterval,
        modelCachingStrategy: state.modelCachingStrategy,
        useFramelessWindow: state.useFramelessWindow,
        // Network settings are NOT persisted - they come from backend
      }),
      onRehydrateStorage: () => (state) => {
        // Sync sound settings with sound library after rehydration
        if (state) {
          setSoundsEnabled(state.soundsEnabled);
          setVolume(state.soundVolume);
          updateSoundSettings({
            start: state.soundStart,
            complete: state.soundComplete,
            error: state.soundError,
            stop: state.soundStop,
            success: state.soundSuccess,
            return: state.soundReturn,
          });
        }
      },
    }
  )
);
