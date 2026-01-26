import { memo, useState, useEffect, useCallback } from 'react';
import { RefreshCw, Play, Loader2 } from 'lucide-react';
import { cn } from '@/lib/utils';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import type { LlmServerHealthPayload } from '@/hooks/useChatWebSocket';

type ServerStatus = 'idle' | 'loading' | 'ready' | 'stopped' | 'restarting' | 'error';

interface LlmServerControlsProps {
  getLlmServerHealth: () => Promise<LlmServerHealthPayload>;
  restartLlmServer: () => Promise<void>;
  startLlmServer: (model?: string) => Promise<void>;
  selectedModel: string | null;
  connected: boolean;
}

export const LlmServerControls = memo(({
  getLlmServerHealth,
  restartLlmServer,
  startLlmServer,
  selectedModel,
  connected,
}: LlmServerControlsProps) => {
  const [health, setHealth] = useState<LlmServerHealthPayload | null>(null);
  const [isRestarting, setIsRestarting] = useState(false);
  const [isStarting, setIsStarting] = useState(false);

  // Fetch health status on mount and periodically
  useEffect(() => {
    if (!connected) return;

    const fetchHealth = async () => {
      try {
        const healthData = await getLlmServerHealth();
        setHealth(healthData);
      } catch (err) {
        console.error('Failed to get LLM server health:', err);
      }
    };

    fetchHealth();
    const interval = setInterval(fetchHealth, 5000); // Poll every 5 seconds

    return () => clearInterval(interval);
  }, [connected, getLlmServerHealth]);

  // Update health when restart/start completes
  const refreshHealth = useCallback(async () => {
    try {
      const healthData = await getLlmServerHealth();
      setHealth(healthData);
    } catch (err) {
      console.error('Failed to refresh health:', err);
    }
  }, [getLlmServerHealth]);

  const handleRestart = useCallback(async () => {
    if (isRestarting) return;
    setIsRestarting(true);
    try {
      await restartLlmServer();
      // Wait a moment then refresh health
      setTimeout(refreshHealth, 500);
    } catch (err) {
      console.error('Failed to restart LLM server:', err);
    } finally {
      setIsRestarting(false);
    }
  }, [isRestarting, restartLlmServer, refreshHealth]);

  const handleStart = useCallback(async () => {
    if (isStarting || !selectedModel) return;
    setIsStarting(true);
    try {
      await startLlmServer(selectedModel);
      // The server status will update via the llm_server_status event
      // but also refresh after a delay
      setTimeout(refreshHealth, 1000);
    } catch (err) {
      console.error('Failed to start LLM server:', err);
    } finally {
      setIsStarting(false);
    }
  }, [isStarting, selectedModel, startLlmServer, refreshHealth]);

  // Determine display status
  const status: ServerStatus = isRestarting
    ? 'restarting'
    : isStarting
    ? 'loading'
    : (health?.status as ServerStatus) || 'idle';

  const statusInfo = getStatusInfo(status, health?.binary_available ?? true);
  const canStart = status === 'idle' && selectedModel && !isStarting && !isRestarting;
  const canRestart = (status === 'ready' || status === 'loading' || status === 'error') && !isRestarting && !isStarting;

  if (!connected) {
    return null;
  }

  return (
    <TooltipProvider delayDuration={300}>
      <div
        className="flex items-center gap-1 h-[44px] px-3 rounded-full backdrop-blur-xl"
        style={{
          background: 'rgba(255, 255, 255, 0.08)',
          boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
        }}
      >
        {/* Status indicator */}
        <Tooltip>
          <TooltipTrigger asChild>
            <div className="flex items-center gap-1.5 cursor-default">
              <div
                className={cn(
                  'w-2 h-2 rounded-full flex-shrink-0',
                  statusInfo.pulse && 'animate-pulse'
                )}
                style={{ backgroundColor: statusInfo.color }}
              />
              <span
                className="text-[11px] font-medium"
                style={{ color: 'var(--color-text-secondary)' }}
              >
                {statusInfo.label}
              </span>
            </div>
          </TooltipTrigger>
          <TooltipContent side="top">
            <p>{statusInfo.tooltip}</p>
            {health?.model && (
              <p className="text-[10px] opacity-70 mt-0.5">
                Model: {health.model.split('/').pop()}
              </p>
            )}
          </TooltipContent>
        </Tooltip>

        {/* Start button - shown when idle and model selected */}
        {canStart && (
          <Tooltip>
            <TooltipTrigger asChild>
              <button
                onClick={handleStart}
                disabled={isStarting}
                className={cn(
                  'flex items-center justify-center w-7 h-7 rounded-full transition-all duration-200',
                  'hover:bg-white/10 active:bg-white/15',
                  isStarting && 'opacity-50 cursor-not-allowed'
                )}
                style={{ color: 'var(--color-green)' }}
              >
                {isStarting ? (
                  <Loader2 className="w-3.5 h-3.5 animate-spin" />
                ) : (
                  <Play className="w-3.5 h-3.5" />
                )}
              </button>
            </TooltipTrigger>
            <TooltipContent side="top">
              <p>Start LLM Server</p>
            </TooltipContent>
          </Tooltip>
        )}

        {/* Restart button - shown when server is running or in error */}
        {canRestart && (
          <Tooltip>
            <TooltipTrigger asChild>
              <button
                onClick={handleRestart}
                disabled={isRestarting}
                className={cn(
                  'flex items-center justify-center w-7 h-7 rounded-full transition-all duration-200',
                  'hover:bg-white/10 active:bg-white/15',
                  isRestarting && 'opacity-50 cursor-not-allowed'
                )}
                style={{ color: 'var(--color-text-secondary)' }}
              >
                <RefreshCw
                  className={cn(
                    'w-3.5 h-3.5',
                    isRestarting && 'animate-spin'
                  )}
                />
              </button>
            </TooltipTrigger>
            <TooltipContent side="top">
              <p>Restart LLM Server</p>
            </TooltipContent>
          </Tooltip>
        )}
      </div>
    </TooltipProvider>
  );
});

LlmServerControls.displayName = 'LlmServerControls';

interface StatusInfo {
  label: string;
  color: string;
  tooltip: string;
  pulse: boolean;
}

function getStatusInfo(status: ServerStatus, binaryAvailable: boolean): StatusInfo {
  if (!binaryAvailable) {
    return {
      label: 'Missing',
      color: 'var(--color-red)',
      tooltip: 'llama-server binary not found',
      pulse: false,
    };
  }

  switch (status) {
    case 'ready':
      return {
        label: 'Ready',
        color: 'var(--color-green)',
        tooltip: 'LLM server is running and ready',
        pulse: false,
      };
    case 'loading':
      return {
        label: 'Loading',
        color: 'var(--color-yellow)',
        tooltip: 'LLM server is loading model...',
        pulse: true,
      };
    case 'restarting':
      return {
        label: 'Restarting',
        color: 'var(--color-yellow)',
        tooltip: 'LLM server is restarting...',
        pulse: true,
      };
    case 'error':
      return {
        label: 'Error',
        color: 'var(--color-red)',
        tooltip: 'LLM server encountered an error',
        pulse: false,
      };
    case 'stopped':
      return {
        label: 'Stopped',
        color: 'var(--color-text-muted)',
        tooltip: 'LLM server is stopped',
        pulse: false,
      };
    case 'idle':
    default:
      return {
        label: 'Idle',
        color: 'var(--color-text-muted)',
        tooltip: 'LLM server is idle - select a model to start',
        pulse: false,
      };
  }
}
