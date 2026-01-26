/**
 * Queue system types for Leaxer
 */

import type { NodeExecutionOutput } from './graph';

export type JobStatus = 'pending' | 'running' | 'completed' | 'error' | 'cancelled';

export interface WorkflowSnapshot {
  nodes: Record<string, {
    id: string;
    type: string;
    data: Record<string, unknown>;
  }>;
  edges: {
    source: string;
    sourceHandle: string;
    target: string;
    targetHandle: string;
  }[];
  compute_backend: string;
  model_caching_strategy: 'auto' | 'cli-mode' | 'server-mode';
}

export interface JobProgress {
  currentIndex: number;
  totalNodes: number;
  percentage: number;
  currentNode: string | null;
  nodeProgress: {
    currentStep: number | null;
    totalSteps: number | null;
    percentage: number;
  } | null;
}

export interface QueuedJob {
  id: string;
  status: JobStatus;
  created_at: number;
  started_at: number | null;
  completed_at: number | null;
  error: string | null;
  progress?: JobProgress | null;
}

export interface QueueState {
  jobs: QueuedJob[];
  is_processing: boolean;
  current_job_id: string | null;
  pending_count: number;
  total_count: number;
}

// WebSocket event payloads
export interface QueueJobsPayload {
  jobs: WorkflowSnapshot[];
}

export interface CancelJobPayload {
  job_id: string;
}

export type QueueUpdatedPayload = QueueState;

export interface JobCompletedPayload {
  job_id: string;
  outputs: Record<string, NodeExecutionOutput>;
}

export interface JobErrorPayload {
  job_id: string;
  error: string;
}
