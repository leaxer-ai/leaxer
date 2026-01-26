import { useEffect, useRef, useState, useCallback } from 'react';
import { Socket, Channel } from 'phoenix';
import type { ExecutionProgress, ExecutionComplete, ExecutionError, StepProgress, NodeExecutionOutput } from '../types/graph';
import type { LogEntry, LogBatch, LogChannelJoinResponse } from '../types/logs';
import type { QueueUpdatedPayload, JobCompletedPayload, JobErrorPayload, WorkflowSnapshot } from '../types/queue';
import { createLogger } from '../lib/logger';

const log = createLogger('WebSocket');

interface ExecutionResumed {
  is_executing: boolean;
  current_node: string | null;
  current_index: number;
  total_nodes: number;
  step_progress: {
    current_step: number;
    total_steps: number;
    percentage: number;
  } | null;
}

export interface NodeOutputPayload {
  job_id: string;
  node_id: string;
  output: NodeExecutionOutput;
}

interface UseWebSocketOptions {
  url?: string;
  onProgress?: (data: ExecutionProgress) => void;
  onStepProgress?: (data: StepProgress) => void;
  onComplete?: (data: ExecutionComplete) => void;
  onError?: (data: ExecutionError) => void;
  onAbort?: () => void;
  onResumed?: (data: ExecutionResumed) => void;
  onLogBatch?: (logs: LogEntry[]) => void;
  // Connection callbacks
  onConnected?: () => void;
  onDisconnected?: () => void;
  // Queue callbacks
  onQueueUpdated?: (data: QueueUpdatedPayload) => void;
  onJobCompleted?: (data: JobCompletedPayload) => void;
  onJobError?: (data: JobErrorPayload) => void;
  // Real-time node output
  onNodeOutput?: (data: NodeOutputPayload) => void;
}

export function useWebSocket(options: UseWebSocketOptions = {}) {
  const {
    url = 'ws://localhost:4000/socket',
    onProgress,
    onStepProgress,
    onComplete,
    onError,
    onAbort,
    onLogBatch,
    onConnected,
    onDisconnected,
    onQueueUpdated,
    onJobCompleted,
    onJobError,
    onNodeOutput,
  } = options;

  const socketRef = useRef<Socket | null>(null);
  const channelRef = useRef<Channel | null>(null);
  const logChannelRef = useRef<Channel | null>(null);
  const [connected, setConnected] = useState(false);
  const [models, setModels] = useState<string[]>([]);

  // Store callbacks in refs to avoid reconnecting when they change
  const onProgressRef = useRef(onProgress);
  const onStepProgressRef = useRef(onStepProgress);
  const onCompleteRef = useRef(onComplete);
  const onErrorRef = useRef(onError);
  const onAbortRef = useRef(onAbort);
  const onResumedRef = useRef(options.onResumed);
  const onLogBatchRef = useRef(onLogBatch);
  const onConnectedRef = useRef(onConnected);
  const onDisconnectedRef = useRef(onDisconnected);
  const onQueueUpdatedRef = useRef(onQueueUpdated);
  const onJobCompletedRef = useRef(onJobCompleted);
  const onJobErrorRef = useRef(onJobError);
  const onNodeOutputRef = useRef(onNodeOutput);

  useEffect(() => {
    onProgressRef.current = onProgress;
    onStepProgressRef.current = onStepProgress;
    onCompleteRef.current = onComplete;
    onErrorRef.current = onError;
    onAbortRef.current = onAbort;
    onResumedRef.current = options.onResumed;
    onLogBatchRef.current = onLogBatch;
    onConnectedRef.current = onConnected;
    onDisconnectedRef.current = onDisconnected;
    onQueueUpdatedRef.current = onQueueUpdated;
    onJobCompletedRef.current = onJobCompleted;
    onJobErrorRef.current = onJobError;
    onNodeOutputRef.current = onNodeOutput;
  }, [onProgress, onStepProgress, onComplete, onError, onAbort, options.onResumed, onLogBatch, onConnected, onDisconnected, onQueueUpdated, onJobCompleted, onJobError, onNodeOutput]);

  useEffect(() => {
    // Track intentional page unload (refresh, close, navigate away)
    // Don't show disconnect notification for intentional user actions
    let isIntentionalUnload = false;

    const handleBeforeUnload = () => {
      isIntentionalUnload = true;
    };

    const handlePageHide = () => {
      isIntentionalUnload = true;
    };

    const handleVisibilityChange = () => {
      if (document.visibilityState === 'hidden') {
        // Page is being hidden - likely refresh/close/tab switch
        // We'll reset this if we come back (visibility becomes visible again)
        isIntentionalUnload = true;
      } else if (document.visibilityState === 'visible') {
        // Page is visible again - user switched back to tab, not a refresh
        isIntentionalUnload = false;
      }
    };

    window.addEventListener('beforeunload', handleBeforeUnload);
    window.addEventListener('pagehide', handlePageHide);
    document.addEventListener('visibilitychange', handleVisibilityChange);

    const socket = new Socket(url, {
      // Reconnection settings for better reliability
      reconnectAfterMs: (tries: number) => {
        // Exponential backoff: 1s, 2s, 4s, 8s, then cap at 10s
        return Math.min(1000 * Math.pow(2, tries - 1), 10000);
      },
      // Heartbeat every 30 seconds to keep connection alive
      heartbeatIntervalMs: 30000,
    });
    socket.connect();
    socketRef.current = socket;

    // Track reconnection for auto-recovery
    // @ts-expect-error Phoenix Socket types are incomplete
    socket.onOpen(() => {
      log.debug('Socket opened/reconnected');
    });

    const channel = socket.channel('graph:main', {});
    channelRef.current = channel;

    // Track if we've fired disconnect since last connect to avoid duplicate notifications
    let hasNotifiedDisconnect = false;

    const handleDisconnect = (reason: string) => {
      log.debug(`Channel ${reason}`);
      setConnected(false);
      // Skip notification for intentional page refresh/close
      if (isIntentionalUnload) {
        log.debug('Skipping disconnect notification - intentional page unload');
        return;
      }
      // Only fire disconnect callback once per disconnect cycle
      if (!hasNotifiedDisconnect) {
        hasNotifiedDisconnect = true;
        onDisconnectedRef.current?.();
      }
    };

    // Handle channel close/error for disconnect detection
    channel.onClose(() => handleDisconnect('closed'));
    channel.onError(() => handleDisconnect('error - will auto-reconnect'));

    const joinChannel = () => {
      channel.join()
        .receive('ok', () => {
          log.debug('Joined graph:main channel');
          hasNotifiedDisconnect = false; // Reset for next disconnect cycle
          setConnected(true);
          onConnectedRef.current?.();
          channel.push('list_models', {});
        })
        .receive('error', (resp: unknown) => {
          log.error('Failed to join channel', resp);
        });
    };

    joinChannel();

    // Handle graph/node level progress
    channel.on('execution_progress', (data: ExecutionProgress) => {
      onProgressRef.current?.(data);
    });

    // Handle step-level progress (from ProgressServer)
    channel.on('step_progress', (data: StepProgress) => {
      log.debug('Received step_progress event:', JSON.stringify(data));
      onStepProgressRef.current?.(data);
    });

    channel.on('execution_complete', (data: ExecutionComplete) => {
      log.debug('Received execution_complete:', data);
      onCompleteRef.current?.(data);
    });

    channel.on('execution_error', (data: ExecutionError) => {
      onErrorRef.current?.(data);
    });

    channel.on('execution_aborted', () => {
      onAbortRef.current?.();
    });

    // Handle execution state recovery after browser refresh
    channel.on('execution_resumed', (data: ExecutionResumed) => {
      log.debug('Received execution_resumed:', data);
      onResumedRef.current?.(data);
    });

    // Queue events
    channel.on('queue_updated', (data: QueueUpdatedPayload) => {
      log.debug('Received queue_updated:', data);
      onQueueUpdatedRef.current?.(data);
    });

    channel.on('job_completed', (data: JobCompletedPayload) => {
      log.debug('Received job_completed:', data.job_id);
      onJobCompletedRef.current?.(data);
    });

    channel.on('job_error', (data: JobErrorPayload) => {
      log.debug('Received job_error:', data.job_id, data.error);
      onJobErrorRef.current?.(data);
    });

    // Real-time node output for incremental preview updates
    channel.on('node_output', (data: NodeOutputPayload) => {
      log.debug('Received node_output:', data.node_id);
      onNodeOutputRef.current?.(data);
    });

    // Async models list response (offloaded to avoid blocking channel heartbeat)
    channel.on('models_list', (data: { models: string[] }) => {
      log.debug('Received models_list:', data.models?.length, 'models');
      setModels(data.models);
    });

    // Set up log channel
    const logChannel = socket.channel('logs:viewer', {});
    logChannelRef.current = logChannel;

    logChannel
      .join()
      .receive('ok', (response: LogChannelJoinResponse) => {
        log.debug('Joined logs:viewer channel, recent_logs:', response.recent_logs?.length);
        // Handle initial recent logs
        if (response.recent_logs && response.recent_logs.length > 0) {
          onLogBatchRef.current?.(response.recent_logs);
        }
      })
      .receive('error', (resp) => {
        log.error('Failed to join log channel', resp);
      });

    // Handle log batches
    logChannel.on('log_batch', (data: LogBatch) => {
      log.debug('Received log_batch:', data.logs?.length, 'logs');
      onLogBatchRef.current?.(data.logs);
    });

    return () => {
      // Mark as intentional before cleanup to prevent disconnect notification
      isIntentionalUnload = true;
      window.removeEventListener('beforeunload', handleBeforeUnload);
      window.removeEventListener('pagehide', handlePageHide);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
      channel.leave();
      logChannel.leave();
      socket.disconnect();
    };
  }, [url]);

  const runGraph = useCallback((
    nodes: Record<string, unknown>,
    edges: unknown[],
    computeBackend: string = 'cpu'
  ) => {
    if (!channelRef.current) return;

    return new Promise((resolve, reject) => {
      channelRef.current!
        .push('run_graph', { nodes, edges, compute_backend: computeBackend })
        .receive('ok', resolve)
        .receive('error', reject);
    });
  }, []);

  const abortExecution = useCallback(() => {
    if (!channelRef.current) return;
    channelRef.current.push('abort_execution', {});
  }, []);

  // Queue functions
  const queueJobs = useCallback((jobs: WorkflowSnapshot[]) => {
    if (!channelRef.current) return Promise.reject(new Error('Not connected'));

    return new Promise<{ job_ids: string[] }>((resolve, reject) => {
      channelRef.current!
        .push('queue_jobs', { jobs })
        .receive('ok', resolve)
        .receive('error', reject);
    });
  }, []);

  const cancelJob = useCallback((jobId: string) => {
    if (!channelRef.current) return Promise.reject(new Error('Not connected'));

    return new Promise<{ status: string }>((resolve, reject) => {
      channelRef.current!
        .push('cancel_job', { job_id: jobId })
        .receive('ok', resolve)
        .receive('error', reject);
    });
  }, []);

  const getQueue = useCallback(() => {
    if (!channelRef.current) return Promise.reject(new Error('Not connected'));

    return new Promise((resolve, reject) => {
      channelRef.current!
        .push('get_queue', {})
        .receive('ok', resolve)
        .receive('error', reject);
    });
  }, []);

  const clearQueue = useCallback(() => {
    if (!channelRef.current) return;
    channelRef.current.push('clear_queue', {});
  }, []);

  return {
    connected,
    models,
    runGraph,
    abortExecution,
    queueJobs,
    cancelJob,
    getQueue,
    clearQueue,
  };
}
