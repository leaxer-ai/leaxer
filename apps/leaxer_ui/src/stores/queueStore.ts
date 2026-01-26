import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import type { QueuedJob, JobProgress } from '../types/queue';

interface QueueStoreState {
  // Queue state (from server)
  jobs: QueuedJob[];
  isProcessing: boolean;
  currentJobId: string | null;
  serverPendingCount: number;  // Actual pending count from server
  serverTotalCount: number;    // Actual total count from server

  // UI state
  queueCount: number;
  isDrawerOpen: boolean;
  isServerRestarting: boolean;

  // Actions
  setQueueCount: (count: number) => void;
  incrementQueueCount: () => void;
  decrementQueueCount: () => void;
  setDrawerOpen: (open: boolean) => void;
  toggleDrawer: () => void;
  setServerRestarting: (restarting: boolean) => void;
  clearJobs: () => void;

  // Queue state actions (called from WebSocket events)
  setQueueState: (state: {
    jobs?: QueuedJob[];
    is_processing?: boolean;
    current_job_id?: string | null;
    pending_count?: number;
    total_count?: number;
  }) => void;
  updateJobProgress: (jobId: string, progress: JobProgress) => void;

  // Computed getters
  pendingCount: () => number;
  runningJob: () => QueuedJob | null;
  activeJobs: () => QueuedJob[];
  completedJobs: () => QueuedJob[];
}

export const useQueueStore = create<QueueStoreState>()(
  persist(
    (set, get) => ({
      // Queue state
      jobs: [],
      isProcessing: false,
      currentJobId: null,
      serverPendingCount: 0,
      serverTotalCount: 0,

      // UI state
      queueCount: 1,
      isDrawerOpen: false,
      isServerRestarting: false,

      // Actions
      setQueueCount: (count) => set({ queueCount: Math.max(1, count) }),

      incrementQueueCount: () =>
        set((state) => ({ queueCount: state.queueCount + 1 })),

      decrementQueueCount: () =>
        set((state) => ({ queueCount: Math.max(1, state.queueCount - 1) })),

      setDrawerOpen: (open) => set({ isDrawerOpen: open }),

      toggleDrawer: () =>
        set((state) => ({ isDrawerOpen: !state.isDrawerOpen })),

      setServerRestarting: (restarting) => set({ isServerRestarting: restarting }),

      clearJobs: () =>
        set({
          jobs: [],
          isProcessing: false,
          currentJobId: null,
          serverPendingCount: 0,
          serverTotalCount: 0,
        }),

      // Queue state actions
      setQueueState: (state) =>
        set((s) => ({
          jobs: state.jobs ?? s.jobs,
          isProcessing: state.is_processing ?? s.isProcessing,
          currentJobId: state.current_job_id ?? s.currentJobId,
          serverPendingCount: state.pending_count ?? s.serverPendingCount,
          serverTotalCount: state.total_count ?? s.serverTotalCount,
        })),

      updateJobProgress: (jobId, progress) =>
        set((state) => ({
          jobs: state.jobs.map((job) =>
            job.id === jobId ? { ...job, progress } : job
          ),
        })),

      // Computed getters - use server count for accuracy
      pendingCount: () => get().serverPendingCount,

      runningJob: () =>
        get().jobs.find((j) => j.status === 'running') ?? null,

      activeJobs: () =>
        get().jobs.filter(
          (j) => j.status === 'pending' || j.status === 'running'
        ),

      completedJobs: () =>
        get().jobs.filter(
          (j) =>
            j.status === 'completed' ||
            j.status === 'error' ||
            j.status === 'cancelled'
        ),
    }),
    {
      name: 'leaxer-queue',
      // Only persist UI preferences, not server state
      partialize: (state) => ({
        queueCount: state.queueCount,
      }),
    }
  )
);
