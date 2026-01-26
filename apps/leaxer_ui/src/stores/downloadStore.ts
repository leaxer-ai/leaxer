import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import { apiFetch } from '@/lib/fetch';

const STORAGE_KEY = 'leaxer-downloads';

// Extract filename (without extension) from a download URL
function extractFilenameFromUrl(url: string): string {
  try {
    const pathname = new URL(url).pathname;
    const filename = pathname.split('/').pop() || '';
    // Remove extension and decode URI
    const decoded = decodeURIComponent(filename);
    const lastDot = decoded.lastIndexOf('.');
    return lastDot > 0 ? decoded.substring(0, lastDot) : decoded;
  } catch {
    return '';
  }
}

export interface RegistryModel {
  id: string;
  name: string;
  description: string;
  size_bytes: number;
  size_human: string;
  format: string;
  license: string;
  commercial_use: boolean;
  recommended?: boolean;
  tags: string[];
  download_url: string;
  homepage: string;
  note?: string;
  compatible_with?: string[];
  control_type?: string;
  parameters?: string;
  quantization?: string;
  min_ram_gb?: number;
  scale_factor?: number;
  // Computed field: filename without extension extracted from download_url
  _filename?: string;
}

export interface RegistryCategory {
  category: string;
  models: RegistryModel[];
}

export type DownloadStatus = 'pending' | 'downloading' | 'complete' | 'failed' | 'cancelled';

export interface ActiveDownload {
  download_id: string;
  model_id: string;
  model_name: string;
  filename: string;
  status: DownloadStatus;
  percentage: number;
  bytes_downloaded: number;
  total_bytes: number;
  speed_bps: number;
  error?: string;
  target_path?: string;
  duration_seconds?: number;
}

interface DownloadState {
  // UI state
  isModalOpen: boolean;
  selectedCategory: string;
  searchTerm: string;

  // Registry data
  registryModels: Record<string, RegistryModel[]>;
  registryLoading: boolean;
  registryError: string | null;

  // Download tracking (keyed by download_id)
  activeDownloads: Record<string, ActiveDownload>;
  installedModels: Set<string>;

  // Actions
  setModalOpen: (open: boolean) => void;
  openModal: () => void;
  openModalToCategory: (category: string) => void;
  closeModal: () => void;
  setSelectedCategory: (category: string) => void;
  setSearchTerm: (term: string) => void;

  // Registry actions
  fetchRegistry: () => Promise<void>;
  setRegistryModels: (models: Record<string, RegistryModel[]>) => void;
  setRegistryLoading: (loading: boolean) => void;
  setRegistryError: (error: string | null) => void;

  // Download actions
  updateDownload: (downloadId: string, data: Partial<ActiveDownload>) => void;
  setDownload: (downloadId: string, download: ActiveDownload) => void;
  removeDownload: (downloadId: string) => void;
  clearCompletedDownloads: () => void;
  getDownloadByModelId: (modelId: string) => ActiveDownload | undefined;
  isModelDownloading: (modelId: string) => boolean;

  // Installed models
  checkInstalled: () => Promise<void>;
  setInstalledModels: (models: Set<string>) => void;
}

export const useDownloadStore = create<DownloadState>()(
  persist(
    (set, get) => ({
      // UI state
      isModalOpen: false,
      selectedCategory: 'checkpoints',
      searchTerm: '',

      // Registry data
      registryModels: {},
      registryLoading: false,
      registryError: null,

      // Download tracking
      activeDownloads: {},
      installedModels: new Set(),

      setModalOpen: (isModalOpen) => set({ isModalOpen }),

      openModal: () => {
        set({ isModalOpen: true });
        get().fetchRegistry();
        get().checkInstalled();
      },

      openModalToCategory: (category) => {
        set({ isModalOpen: true, selectedCategory: category });
        get().fetchRegistry();
        get().checkInstalled();
      },

      closeModal: () => set({ isModalOpen: false }),

      setSelectedCategory: (selectedCategory) => set({ selectedCategory }),

      setSearchTerm: (searchTerm) => set({ searchTerm }),

      fetchRegistry: async () => {
        const { setRegistryLoading, setRegistryError, setRegistryModels } = get();

        setRegistryLoading(true);
        setRegistryError(null);

        try {
          const response = await apiFetch('/api/registry/models');
          if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
          }

          const data = await response.json();

          // API returns { registry: {...}, category: null, generated_at: ... }
          const registry = data.registry || data;

          const categorizedModels: Record<string, RegistryModel[]> = {};
          const categories = ['checkpoints', 'loras', 'vaes', 'controlnets', 'llms', 'text_encoders', 'upscalers'];

          for (const category of categories) {
            if (registry[category] && Array.isArray(registry[category])) {
              // Add computed _filename field for matching with installed models
              categorizedModels[category] = registry[category].map((model: RegistryModel) => ({
                ...model,
                _filename: extractFilenameFromUrl(model.download_url),
              }));
            }
          }

          setRegistryModels(categorizedModels);
        } catch (error) {
          console.error('Failed to fetch registry:', error);
          setRegistryError(error instanceof Error ? error.message : 'Unknown error');
        } finally {
          setRegistryLoading(false);
        }
      },

      setRegistryModels: (registryModels) => set({ registryModels }),

      setRegistryLoading: (registryLoading) => set({ registryLoading }),

      setRegistryError: (registryError) => set({ registryError }),

      updateDownload: (downloadId, data) => {
        set((state) => {
          const existing = state.activeDownloads[downloadId];
          if (!existing) return state;

          return {
            activeDownloads: {
              ...state.activeDownloads,
              [downloadId]: { ...existing, ...data },
            },
          };
        });
      },

      setDownload: (downloadId, download) => {
        set((state) => ({
          activeDownloads: {
            ...state.activeDownloads,
            [downloadId]: download,
          },
        }));
      },

      removeDownload: (downloadId) => {
        set((state) => {
          const { [downloadId]: _removed, ...rest } = state.activeDownloads;
          return { activeDownloads: rest };
        });
      },

      clearCompletedDownloads: () => {
        set((state) => {
          const activeOnly: Record<string, ActiveDownload> = {};
          for (const [id, dl] of Object.entries(state.activeDownloads)) {
            if (dl.status === 'downloading' || dl.status === 'pending') {
              activeOnly[id] = dl;
            }
          }
          return { activeDownloads: activeOnly };
        });
      },

      getDownloadByModelId: (modelId) => {
        const { activeDownloads } = get();
        return Object.values(activeDownloads).find((dl) => dl.model_id === modelId);
      },

      isModelDownloading: (modelId) => {
        const dl = get().getDownloadByModelId(modelId);
        return dl ? dl.status === 'downloading' || dl.status === 'pending' : false;
      },

      checkInstalled: async () => {
        try {
          const categories = ['checkpoints', 'loras', 'vaes', 'controlnets', 'llms', 'text_encoders', 'upscalers'];
          const installedSet = new Set<string>();

          for (const category of categories) {
            try {
              const apiPath = category === 'text_encoders' ? 'text-encoders' : category;
              const response = await apiFetch(`/api/models/${apiPath}`);
              if (response.ok) {
                const data = await response.json();
                if (data.models && Array.isArray(data.models)) {
                  data.models.forEach((model: { name?: string }) => {
                    if (model.name) {
                      installedSet.add(model.name);
                    }
                  });
                }
              }
            } catch (error) {
              console.warn(`Failed to check installed models for ${category}:`, error);
            }
          }

          set({ installedModels: installedSet });
        } catch (error) {
          console.error('Failed to check installed models:', error);
        }
      },

      setInstalledModels: (installedModels) => set({ installedModels }),
    }),
    {
      name: STORAGE_KEY,
      partialize: (state) => ({
        selectedCategory: state.selectedCategory,
      }),
    }
  )
);
