import { create } from 'zustand';
import { persist } from 'zustand/middleware';

export interface RecentFile {
  path: string;
  name: string;
  openedAt: string; // ISO 8601
}

const MAX_RECENT_FILES = 10;

interface RecentFilesState {
  files: RecentFile[];

  // Actions
  addRecentFile: (path: string, name: string) => void;
  removeRecentFile: (path: string) => void;
  clearRecentFiles: () => void;
  getRecentFiles: () => RecentFile[];
}

export const useRecentFilesStore = create<RecentFilesState>()(
  persist(
    (set, get) => ({
      files: [],

      addRecentFile: (path, name) => {
        set((state) => {
          // Remove existing entry with same path
          const filtered = state.files.filter((f) => f.path !== path);

          // Add new entry at the beginning
          const newFile: RecentFile = {
            path,
            name,
            openedAt: new Date().toISOString(),
          };

          const newFiles = [newFile, ...filtered].slice(0, MAX_RECENT_FILES);

          return { files: newFiles };
        });
      },

      removeRecentFile: (path) => {
        set((state) => ({
          files: state.files.filter((f) => f.path !== path),
        }));
      },

      clearRecentFiles: () => {
        set({ files: [] });
      },

      getRecentFiles: () => get().files,
    }),
    {
      name: 'leaxer-recent-files',
    }
  )
);
