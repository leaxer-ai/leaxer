import { useCallback, useRef, useState, useEffect } from 'react';
import { Play, Square, ChevronUp, ChevronDown, List } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useQueueStore } from '@/stores/queueStore';
import './QueuePill.css';

interface QueuePillProps {
  connected: boolean;
  isExecuting: boolean;
  isStopping: boolean;
  onQueue: (count: number) => void;
  onStop: () => void;
  onStopAll: () => void;
  onOpenDrawer: () => void;
}

export function QueuePill({
  connected,
  isExecuting,
  isStopping,
  onQueue,
  onStop,
  onStopAll,
  onOpenDrawer,
}: QueuePillProps) {
  const queueCount = useQueueStore((s) => s.queueCount);
  const setQueueCount = useQueueStore((s) => s.setQueueCount);
  const incrementQueueCount = useQueueStore((s) => s.incrementQueueCount);
  const decrementQueueCount = useQueueStore((s) => s.decrementQueueCount);
  const pendingCount = useQueueStore((s) => s.pendingCount());
  const runningJob = useQueueStore((s) => s.runningJob());
  const isServerRestarting = useQueueStore((s) => s.isServerRestarting);

  const [isEditing, setIsEditing] = useState(false);
  const [editValue, setEditValue] = useState(String(queueCount));
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!isEditing) {
      setEditValue(String(queueCount));
    }
  }, [queueCount, isEditing]);

  const handleQueue = useCallback(() => {
    if (connected && !isServerRestarting) {
      onQueue(queueCount);
    }
  }, [onQueue, queueCount, connected, isServerRestarting]);

  const handleCountClick = useCallback(() => {
    setIsEditing(true);
    setEditValue(String(queueCount));
    setTimeout(() => inputRef.current?.select(), 0);
  }, [queueCount]);

  const handleCountBlur = useCallback(() => {
    setIsEditing(false);
    const value = parseInt(editValue, 10);
    if (!isNaN(value) && value >= 1) {
      setQueueCount(value);
    } else {
      setEditValue(String(queueCount));
    }
  }, [editValue, setQueueCount, queueCount]);

  const handleCountChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      setEditValue(e.target.value);
    },
    []
  );

  const handleCountKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === 'Enter') {
        const value = parseInt(editValue, 10);
        if (!isNaN(value) && value >= 1) {
          setQueueCount(value);
          setIsEditing(false);
          handleQueue();
        }
      } else if (e.key === 'Escape') {
        setIsEditing(false);
        setEditValue(String(queueCount));
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        const newVal = Math.max(1, parseInt(editValue || '1', 10) + 1);
        setEditValue(String(newVal));
        setQueueCount(newVal);
      } else if (e.key === 'ArrowDown') {
        e.preventDefault();
        const newVal = Math.max(1, parseInt(editValue || '1', 10) - 1);
        setEditValue(String(newVal));
        setQueueCount(newVal);
      }
    },
    [editValue, handleQueue, setQueueCount, queueCount]
  );

  const totalPending = pendingCount + (runningJob ? 1 : 0);

  // Disable queue when not connected or server is restarting
  const isQueueDisabled = !connected || isServerRestarting;

  return (
    <div className="flex items-center gap-2">
      {/* Stop buttons - only shows when executing */}
      {isExecuting && (
        <div
          className="flex items-center h-[44px] rounded-full backdrop-blur-xl overflow-hidden"
          style={{
            background: 'rgba(255, 107, 107, 0.8)',
            boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.2)',
          }}
        >
          {/* Stop current job */}
          <button
            onClick={onStop}
            disabled={isStopping}
            className={cn(
              "flex items-center gap-2 px-4 h-full text-[13px] font-medium transition-all duration-150",
              isStopping ? "opacity-70 cursor-not-allowed" : "active:scale-95 cursor-pointer hover:bg-white/10"
            )}
            style={{ color: 'rgba(255, 255, 255, 0.95)' }}
            title={isStopping ? "Stopping..." : "Stop current job"}
          >
            <Square className="w-3.5 h-3.5 fill-current" />
            <span>{isStopping ? 'Stopping...' : 'Stop'}</span>
          </button>

          {/* Stop all - only show when there are pending jobs */}
          {totalPending > 1 && (
            <>
              <div className="w-px h-6 bg-white/20" />
              <button
                onClick={onStopAll}
                disabled={isStopping}
                className={cn(
                  "flex items-center gap-1.5 px-3 h-full text-[11px] font-medium transition-all duration-150",
                  isStopping ? "opacity-70 cursor-not-allowed" : "active:scale-95 cursor-pointer hover:bg-white/10"
                )}
                style={{ color: 'rgba(255, 255, 255, 0.8)' }}
                title={isStopping ? "Stopping..." : "Stop current and clear queue"}
              >
                <span>All</span>
              </button>
            </>
          )}
        </div>
      )}

      {/* Main queue pill */}
      <div
        className="queue-pill flex items-center h-[44px] rounded-full backdrop-blur-xl overflow-hidden"
        style={{
          background: 'rgba(255, 255, 255, 0.08)',
          boxShadow:
            '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
        }}
      >
        {/* Queue indicator button - shows pending count, opens drawer */}
        {totalPending > 0 && (
          <button
            onClick={onOpenDrawer}
            className="queue-indicator flex items-center gap-1.5 px-3 h-full text-[12px] font-medium transition-colors hover:bg-white/10 cursor-pointer"
            style={{ color: 'var(--color-text-secondary)' }}
            title="View queue"
          >
            <List className="w-3.5 h-3.5" />
            <span className="tabular-nums">{totalPending}</span>
          </button>
        )}

        {/* Queue count stepper - always enabled */}
        <div className="flex items-center h-full">
          {/* Decrement button */}
          <button
            onClick={decrementQueueCount}
            disabled={queueCount <= 1}
            className={cn(
              'flex items-center justify-center w-8 h-full transition-colors cursor-pointer',
              queueCount <= 1
                ? 'opacity-30 cursor-not-allowed'
                : 'hover:bg-white/10'
            )}
            style={{ color: 'var(--color-text-secondary)' }}
            title="Decrease queue count"
          >
            <ChevronDown className="w-3.5 h-3.5" />
          </button>

          {/* Count display/input */}
          <div className="flex items-center justify-center min-w-[32px] h-full">
            {isEditing ? (
              <input
                ref={inputRef}
                type="text"
                inputMode="numeric"
                pattern="[0-9]*"
                value={editValue}
                onChange={handleCountChange}
                onBlur={handleCountBlur}
                onKeyDown={handleCountKeyDown}
                className="w-10 h-6 text-center text-[13px] font-medium bg-white/10 rounded border-none outline-none"
                style={{ color: 'var(--color-text)' }}
                autoFocus
              />
            ) : (
              <button
                onClick={handleCountClick}
                className="text-[13px] font-medium tabular-nums cursor-pointer px-2 py-1 rounded transition-colors hover:bg-white/10"
                style={{ color: 'var(--color-text)' }}
                title="Click to edit queue count"
              >
                {queueCount}
              </button>
            )}
          </div>

          {/* Increment button */}
          <button
            onClick={incrementQueueCount}
            className="flex items-center justify-center w-8 h-full transition-colors cursor-pointer hover:bg-white/10"
            style={{ color: 'var(--color-text-secondary)' }}
            title="Increase queue count"
          >
            <ChevronUp className="w-3.5 h-3.5" />
          </button>
        </div>


        {/* Queue button - always available */}
        <button
          onClick={handleQueue}
          disabled={isQueueDisabled}
          className={cn(
            'flex items-center gap-2 px-4 h-full text-[13px] font-medium transition-all duration-150 active:scale-95 cursor-pointer rounded-r-full',
            isQueueDisabled && 'opacity-50 !cursor-not-allowed'
          )}
          style={{
            background: 'var(--color-accent)',
            color: 'var(--color-crust)',
          }}
        >
          <Play className="w-3.5 h-3.5 fill-current" />
          <span>{isServerRestarting ? 'Restarting...' : isExecuting ? 'Add' : 'Run'}</span>
          {!isExecuting && !isServerRestarting && (
            <kbd
              className="ml-1 px-1.5 py-0.5 text-[10px] rounded"
              style={{ backgroundColor: 'rgba(0, 0, 0, 0.2)' }}
            >
              ⇧↵
            </kbd>
          )}
        </button>
      </div>
    </div>
  );
}
