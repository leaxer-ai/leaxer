import { useState, useMemo, useCallback } from 'react';
import { Cpu, MemoryStick, Gauge, RotateCw, Trash2, Terminal } from 'lucide-react';
import { cn } from '@/lib/utils';
import { apiFetch } from '@/lib/fetch';
import { useHardwareChannel } from '@/hooks/useHardwareChannel';
import { useQueueStore } from '@/stores/queueStore';
import { useSettingsStore } from '@/stores/settingsStore';
import { useLogStore } from '@/stores/logStore';
import { RestartConfirmDialog } from './RestartConfirmDialog';
import { CleanupConfirmDialog } from './CleanupConfirmDialog';
import { createLogger } from '@/lib/logger';
import './HardwareMonitor.css';

const log = createLogger('HardwareMonitor');

interface SparklineProps {
  data: number[];
  width?: number;
  height?: number;
  className?: string;
}

function Sparkline({ data, width = 40, height = 16, className }: SparklineProps) {
  const path = useMemo(() => {
    if (data.length === 0) return '';

    const points = data.slice(-30);
    if (points.length === 0) return '';

    const max = 100;
    const min = 0;
    const range = max - min || 1;

    const xStep = width / Math.max(points.length - 1, 1);

    const pathPoints = points.map((value, index) => {
      const x = index * xStep;
      const y = height - ((value - min) / range) * height;
      return `${x},${y}`;
    });

    return `M${pathPoints.join(' L')}`;
  }, [data, width, height]);

  const areaPath = useMemo(() => {
    if (data.length === 0) return '';

    const points = data.slice(-30);
    if (points.length === 0) return '';

    const max = 100;
    const min = 0;
    const range = max - min || 1;

    const xStep = width / Math.max(points.length - 1, 1);

    const pathPoints = points.map((value, index) => {
      const x = index * xStep;
      const y = height - ((value - min) / range) * height;
      return `${x},${y}`;
    });

    return `M0,${height} L${pathPoints.join(' L')} L${width},${height} Z`;
  }, [data, width, height]);

  return (
    <svg
      width={width}
      height={height}
      className={cn('sparkline', className)}
      viewBox={`0 0 ${width} ${height}`}
    >
      <path
        d={areaPath}
        fill="currentColor"
        opacity={0.1}
      />
      <path
        d={path}
        fill="none"
        stroke="currentColor"
        strokeWidth={1.5}
        strokeLinecap="round"
        strokeLinejoin="round"
        opacity={0.6}
      />
    </svg>
  );
}

interface MetricItemProps {
  label: string;
  value: number;
  history: number[];
  icon: React.ReactNode;
  detail?: string;
}

function MetricItem({ label, value, history, icon, detail }: MetricItemProps) {
  return (
    <div className="flex items-center gap-2 px-2 py-1">
      <div className="flex items-center gap-1.5 min-w-[52px]">
        <span className="text-text-muted">
          {icon}
        </span>
        <span className="text-xs font-medium tabular-nums text-text-secondary">
          {label}
        </span>
      </div>
      <div className="flex items-center gap-2 text-text-muted">
        <Sparkline
          data={history}
          width={32}
          height={14}
        />
        <span className="text-xs font-medium tabular-nums min-w-[32px] text-right text-text">
          {Math.round(value)}%
        </span>
      </div>
      {detail && (
        <span className="text-[11px] tabular-nums text-text-muted opacity-60 ml-1">
          {detail}
        </span>
      )}
    </div>
  );
}

export function HardwareMonitor() {
  const { connected, stats } = useHardwareChannel();
  const [isExpanded, setIsExpanded] = useState(false);
  const [showRestartDialog, setShowRestartDialog] = useState(false);
  const [showCleanupDialog, setShowCleanupDialog] = useState(false);
  const [isCleaningUp, setIsCleaningUp] = useState(false);

  const isServerRestarting = useQueueStore((s) => s.isServerRestarting);
  const setServerRestarting = useQueueStore((s) => s.setServerRestarting);
  const clearJobs = useQueueStore((s) => s.clearJobs);
  const getApiBaseUrl = useSettingsStore((s) => s.getApiBaseUrl);
  const isLogViewerOpen = useLogStore((s) => s.isOpen);
  const toggleLogViewer = useLogStore((s) => s.toggleOpen);

  const hasGpu = stats.gpu_name !== null || stats.gpu_percent > 0;

  const formatMemory = (used: number, total: number) => {
    return `${used.toFixed(1)}/${total.toFixed(0)}G`;
  };

  const handleRestartClick = useCallback(() => {
    if (isServerRestarting) return;
    setShowRestartDialog(true);
  }, [isServerRestarting]);

  const handleRestartConfirm = useCallback(async () => {
    setShowRestartDialog(false);
    setServerRestarting(true);
    clearJobs();

    try {
      const apiBaseUrl = getApiBaseUrl();
      await apiFetch(`${apiBaseUrl}/api/system/restart`, { method: 'POST' });
    } catch {
      log.debug('Server restart initiated');
    }
  }, [getApiBaseUrl, setServerRestarting, clearJobs]);

  const handleRestartCancel = useCallback(() => {
    setShowRestartDialog(false);
  }, []);

  const handleCleanupClick = useCallback(() => {
    if (isCleaningUp) return;
    setShowCleanupDialog(true);
  }, [isCleaningUp]);

  const handleCleanupConfirm = useCallback(async () => {
    setShowCleanupDialog(false);
    setIsCleaningUp(true);

    try {
      const apiBaseUrl = getApiBaseUrl();
      await apiFetch(`${apiBaseUrl}/api/system/cleanup`, { method: 'POST' });
      log.debug('System cleanup completed');
    } catch {
      log.debug('System cleanup initiated');
    } finally {
      setIsCleaningUp(false);
    }
  }, [getApiBaseUrl]);

  const handleCleanupCancel = useCallback(() => {
    setShowCleanupDialog(false);
  }, []);

  if (!connected) {
    return (
      <>
        <div className="hardware-monitor fixed bottom-4 right-4 z-50 flex items-center gap-2">
          <div
            className="flex items-center h-[44px] rounded-full backdrop-blur-xl px-4"
            style={{
              background: 'rgba(255, 255, 255, 0.08)',
              boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
            }}
          >
            <span className="text-[10px] text-text-muted">
              Connecting...
            </span>
          </div>

          {/* Button group: Cleanup, Restart, Logs */}
          <div
            className="flex items-center h-[44px] rounded-full backdrop-blur-xl overflow-hidden"
            style={{
              background: 'rgba(255, 255, 255, 0.08)',
              boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
            }}
          >
            {/* Cleanup button */}
            <button
              onClick={handleCleanupClick}
              disabled={isCleaningUp}
              className="flex items-center justify-center w-[44px] h-[44px] transition-all duration-150 active:scale-95 cursor-pointer disabled:cursor-not-allowed hover:bg-white/5"
              title="System cleanup (free VRAM, clear cache)"
            >
              <Trash2
                className={cn('w-4 h-4 text-text-secondary', isCleaningUp && 'animate-pulse')}
              />
            </button>

            {/* Separator */}
            <div className="w-px h-5 bg-text-muted/20" />

            {/* Restart button */}
            <button
              onClick={handleRestartClick}
              disabled={isServerRestarting}
              className="flex items-center justify-center w-[44px] h-[44px] transition-all duration-150 active:scale-95 cursor-pointer disabled:cursor-not-allowed hover:bg-white/5"
              title="Restart server"
            >
              <RotateCw
                className={cn('w-4 h-4 text-text-secondary', isServerRestarting && 'animate-spin')}
              />
            </button>

            {/* Separator */}
            <div className="w-px h-5 bg-text-muted/20" />

            {/* Logs toggle button */}
            <button
              onClick={toggleLogViewer}
              className={cn(
                'flex items-center justify-center w-[44px] h-[44px] transition-all duration-150 active:scale-95 cursor-pointer',
                isLogViewerOpen && 'bg-white/10'
              )}
              title={isLogViewerOpen ? 'Hide server logs' : 'Show server logs'}
            >
              <Terminal
                className={cn(
                  'w-4 h-4',
                  isLogViewerOpen ? 'text-accent' : 'text-text-secondary'
                )}
              />
            </button>
          </div>
        </div>

        <RestartConfirmDialog
          isOpen={showRestartDialog}
          onConfirm={handleRestartConfirm}
          onCancel={handleRestartCancel}
        />
        <CleanupConfirmDialog
          isOpen={showCleanupDialog}
          onConfirm={handleCleanupConfirm}
          onCancel={handleCleanupCancel}
        />
      </>
    );
  }

  return (
    <>
      <div className="hardware-monitor fixed bottom-4 right-4 z-50 flex items-center gap-2">
        <div
          className={cn(
            "flex items-center h-[44px] rounded-full backdrop-blur-xl overflow-hidden transition-all duration-200",
            isExpanded && "hardware-monitor-expanded"
          )}
          style={{
            background: 'rgba(255, 255, 255, 0.08)',
            boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
          }}
          onMouseEnter={() => setIsExpanded(true)}
          onMouseLeave={() => setIsExpanded(false)}
        >
        {/* Compact view */}
        <div className={cn(
          "compact-view flex items-center gap-3 px-4 transition-opacity duration-200",
          isExpanded && "opacity-0 absolute pointer-events-none"
        )}>
          {/* CPU */}
          <div className="flex items-center gap-2 text-text-muted">
            <Cpu className="w-3.5 h-3.5" />
            <Sparkline
              data={stats.history.cpu}
              width={28}
              height={12}
            />
            <span className="text-xs font-medium tabular-nums text-text-secondary">
              {Math.round(stats.cpu_percent)}%
            </span>
          </div>

          {/* Separator */}
          <div className="w-px h-5 bg-text-muted/20" />

          {/* Memory */}
          <div className="flex items-center gap-2 text-text-muted">
            <MemoryStick className="w-3.5 h-3.5" />
            <Sparkline
              data={stats.history.memory}
              width={28}
              height={12}
            />
            <span className="text-xs font-medium tabular-nums text-text-secondary">
              {Math.round(stats.memory_percent)}%
            </span>
          </div>

          {/* GPU (if available) */}
          {hasGpu && (
            <>
              <div className="w-px h-5 bg-text-muted/20" />
              <div className="flex items-center gap-2 text-text-muted">
                <Gauge className="w-3.5 h-3.5" />
                <Sparkline
                  data={stats.history.gpu}
                  width={28}
                  height={12}
                />
                <span className="text-xs font-medium tabular-nums text-text-secondary">
                  {Math.round(stats.gpu_percent)}%
                </span>
                <Sparkline
                  data={stats.history.vram}
                  width={28}
                  height={12}
                />
                <span className="text-xs font-medium tabular-nums text-text-secondary">
                  {Math.round(stats.vram_percent)}%
                </span>
              </div>
            </>
          )}
        </div>

        {/* Expanded view */}
        <div className={cn(
          "expanded-view flex items-center px-3 transition-opacity duration-200",
          !isExpanded && "opacity-0 absolute pointer-events-none"
        )}>
          <MetricItem
            label="CPU"
            value={stats.cpu_percent}
            history={stats.history.cpu}
            icon={<Cpu className="w-3.5 h-3.5" />}
          />

          <div className="w-px h-6 bg-text-muted/20 mx-1" />

          <MetricItem
            label="MEM"
            value={stats.memory_percent}
            history={stats.history.memory}
            icon={<MemoryStick className="w-3.5 h-3.5" />}
            detail={formatMemory(stats.memory_used_gb, stats.memory_total_gb)}
          />

          {hasGpu && (
            <>
              <div className="w-px h-6 bg-text-muted/20 mx-1" />

              <div className="flex items-center gap-2 px-2 py-1">
                <div className="flex items-center gap-1.5">
                  <span className="text-text-muted">
                    <Gauge className="w-3.5 h-3.5" />
                  </span>
                  <span className="text-xs font-medium tabular-nums text-text-secondary">
                    GPU
                  </span>
                </div>
                <div className="flex items-center gap-2 text-text-muted">
                  <Sparkline
                    data={stats.history.gpu}
                    width={32}
                    height={14}
                  />
                  <span className="text-xs font-medium tabular-nums text-text">
                    {Math.round(stats.gpu_percent)}%
                  </span>
                </div>
                <div className="flex items-center gap-2 text-text-muted">
                  <Sparkline
                    data={stats.history.vram}
                    width={32}
                    height={14}
                  />
                  <span className="text-xs font-medium tabular-nums text-text">
                    {Math.round(stats.vram_percent)}%
                  </span>
                  <span className="text-[11px] tabular-nums text-text-muted opacity-60">
                    {formatMemory(stats.vram_used_gb, stats.vram_total_gb)}
                  </span>
                </div>
              </div>
            </>
          )}
        </div>
      </div>

        {/* Button group: Cleanup, Restart, Logs */}
        <div
          className="flex items-center h-[44px] rounded-full backdrop-blur-xl overflow-hidden"
          style={{
            background: 'rgba(255, 255, 255, 0.08)',
            boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
          }}
        >
          {/* Cleanup button */}
          <button
            onClick={handleCleanupClick}
            disabled={isCleaningUp}
            className="flex items-center justify-center w-[44px] h-[44px] transition-all duration-150 active:scale-95 cursor-pointer disabled:cursor-not-allowed hover:bg-white/5"
            title="System cleanup (free VRAM, clear cache)"
          >
            <Trash2
              className={cn('w-4 h-4 text-text-secondary', isCleaningUp && 'animate-pulse')}
            />
          </button>

          {/* Separator */}
          <div className="w-px h-5 bg-text-muted/20" />

          {/* Restart button */}
          <button
            onClick={handleRestartClick}
            disabled={isServerRestarting}
            className="flex items-center justify-center w-[44px] h-[44px] transition-all duration-150 active:scale-95 cursor-pointer disabled:cursor-not-allowed hover:bg-white/5"
            title="Restart server"
          >
            <RotateCw
              className={cn('w-4 h-4 text-text-secondary', isServerRestarting && 'animate-spin')}
            />
          </button>

          {/* Separator */}
          <div className="w-px h-5 bg-text-muted/20" />

          {/* Logs toggle button */}
          <button
            onClick={toggleLogViewer}
            className={cn(
              'flex items-center justify-center w-[44px] h-[44px] transition-all duration-150 active:scale-95 cursor-pointer',
              isLogViewerOpen && 'bg-white/10'
            )}
            title={isLogViewerOpen ? 'Hide server logs' : 'Show server logs'}
          >
            <Terminal
              className={cn(
                'w-4 h-4',
                isLogViewerOpen ? 'text-accent' : 'text-text-secondary'
              )}
            />
          </button>
        </div>
      </div>

      <RestartConfirmDialog
        isOpen={showRestartDialog}
        onConfirm={handleRestartConfirm}
        onCancel={handleRestartCancel}
      />
      <CleanupConfirmDialog
        isOpen={showCleanupDialog}
        onConfirm={handleCleanupConfirm}
        onCancel={handleCleanupCancel}
      />
    </>
  );
}
