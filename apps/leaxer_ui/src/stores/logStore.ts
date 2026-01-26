import { useMemo } from 'react';
import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import type { LogEntry, LogLevel } from '../types/logs';

const STORAGE_KEY = 'leaxer-log-viewer';

export type LogFilter = LogLevel | 'all';

export const MAX_LOGS_OPTIONS = [100, 250, 500, 1000, 2000] as const;
export type MaxLogsOption = (typeof MAX_LOGS_OPTIONS)[number];

const DEFAULT_SIZE = { width: 600, height: 400 };
const MIN_SIZE = { width: 400, height: 200 };
const MAX_SIZE = { width: 1200, height: 800 };

interface LogState {
  // Log data
  logs: LogEntry[];

  // UI state
  isOpen: boolean;
  autoScroll: boolean;
  filter: LogFilter;
  maxLogs: MaxLogsOption;

  // Window state
  size: { width: number; height: number };
  position: { x: number; y: number } | null;

  // Actions
  addLogs: (newLogs: LogEntry[]) => void;
  clearLogs: () => void;
  toggleOpen: () => void;
  setOpen: (open: boolean) => void;
  setAutoScroll: (enabled: boolean) => void;
  setFilter: (filter: LogFilter) => void;
  setMaxLogs: (maxLogs: MaxLogsOption) => void;
  setSize: (size: { width: number; height: number }) => void;
  setPosition: (position: { x: number; y: number }) => void;
}

export const useLogStore = create<LogState>()(
  persist(
    (set) => ({
      // Log data (not persisted)
      logs: [],

      // UI state (persisted)
      isOpen: false,
      autoScroll: true,
      filter: 'all',
      maxLogs: 500,

      // Window state (persisted)
      size: DEFAULT_SIZE,
      position: null,

      addLogs: (newLogs) =>
        set((state) => ({
          logs: [...state.logs, ...newLogs].slice(-state.maxLogs),
        })),

      clearLogs: () => set({ logs: [] }),

      toggleOpen: () => set((state) => ({ isOpen: !state.isOpen })),

      setOpen: (isOpen) => set({ isOpen }),

      setAutoScroll: (autoScroll) => set({ autoScroll }),

      setFilter: (filter) => set({ filter }),

      setMaxLogs: (maxLogs) => set((state) => ({
        maxLogs,
        // Trim existing logs if new limit is smaller
        logs: state.logs.slice(-maxLogs),
      })),

      setSize: (size) => set({
        size: {
          width: Math.max(MIN_SIZE.width, Math.min(MAX_SIZE.width, size.width)),
          height: Math.max(MIN_SIZE.height, Math.min(MAX_SIZE.height, size.height)),
        }
      }),

      setPosition: (position) => set({ position }),
    }),
    {
      name: STORAGE_KEY,
      // Only persist UI preferences, not logs
      partialize: (state) => ({
        isOpen: state.isOpen,
        autoScroll: state.autoScroll,
        filter: state.filter,
        maxLogs: state.maxLogs,
        size: state.size,
        position: state.position,
      }),
    }
  )
);

// Selector for filtered logs with memoization
export const useFilteredLogs = () => {
  const logs = useLogStore((s) => s.logs);
  const filter = useLogStore((s) => s.filter);

  return useMemo(() => {
    if (filter === 'all') return logs;
    return logs.filter((log) => log.level === filter);
  }, [logs, filter]);
};

// Export constants for use in components
export { MIN_SIZE, MAX_SIZE, DEFAULT_SIZE };
