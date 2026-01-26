import { useEffect, useRef, useState, useCallback, memo } from 'react';
import { X, Trash2, ArrowDown, ChevronDown, Terminal, GripVertical, Copy, Check } from 'lucide-react';
import { useVirtualizer } from '@tanstack/react-virtual';
import { cn } from '@/lib/utils';
import {
  useLogStore,
  useFilteredLogs,
  type LogFilter,
  MAX_LOGS_OPTIONS,
  type MaxLogsOption,
  MIN_SIZE,
  MAX_SIZE,
} from '../stores/logStore';
import type { LogEntry, LogLevel } from '../types/logs';

const LOG_LEVEL_STYLES: Record<LogLevel, { bg: string; text: string }> = {
  debug: {
    bg: 'var(--color-surface-1)',
    text: 'var(--color-text-muted)',
  },
  info: {
    bg: 'color-mix(in srgb, var(--color-info) 15%, transparent)',
    text: 'var(--color-info)',
  },
  warning: {
    bg: 'color-mix(in srgb, var(--color-warning) 15%, transparent)',
    text: 'var(--color-warning)',
  },
  error: {
    bg: 'color-mix(in srgb, var(--color-error) 15%, transparent)',
    text: 'var(--color-error)',
  },
};

const LOG_LEVEL_LABELS: Record<LogLevel, string> = {
  debug: 'DBG',
  info: 'INF',
  warning: 'WRN',
  error: 'ERR',
};

const FILTER_OPTIONS: { value: LogFilter; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'debug', label: 'Debug' },
  { value: 'info', label: 'Info' },
  { value: 'warning', label: 'Warn' },
  { value: 'error', label: 'Error' },
];

const ROW_HEIGHT = 26;

function formatTimestamp(timestamp: string): string {
  try {
    const date = new Date(timestamp);
    return date.toLocaleTimeString('en-US', {
      hour12: false,
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
  } catch {
    return timestamp.slice(11, 19);
  }
}

interface LogRowProps {
  log: LogEntry;
}

const LogRow = memo(function LogRow({ log }: LogRowProps) {
  const style = LOG_LEVEL_STYLES[log.level];
  return (
    <div
      className="flex items-start gap-2 py-1 px-3"
      style={{ minHeight: ROW_HEIGHT }}
    >
      {/* Timestamp */}
      <span
        className="flex-shrink-0 text-[10px] font-mono tabular-nums opacity-50 mt-0.5"
        style={{ color: 'var(--color-text-muted)' }}
      >
        {formatTimestamp(log.timestamp)}
      </span>
      {/* Level badge */}
      <span
        className="flex-shrink-0 text-[9px] font-semibold rounded px-1.5 py-0.5 uppercase tracking-wide"
        style={{
          backgroundColor: style.bg,
          color: style.text,
        }}
      >
        {LOG_LEVEL_LABELS[log.level]}
      </span>
      {/* Message */}
      <span
        className="flex-1 text-[11px] font-mono break-words whitespace-pre-wrap leading-relaxed"
        style={{ color: 'var(--color-text)' }}
      >
        {log.message}
      </span>
    </div>
  );
});

type ResizeDirection = 'n' | 's' | 'e' | 'w' | 'ne' | 'nw' | 'se' | 'sw' | null;

export function LogViewer() {
  const isOpen = useLogStore((s) => s.isOpen);
  const autoScroll = useLogStore((s) => s.autoScroll);
  const filter = useLogStore((s) => s.filter);
  const maxLogs = useLogStore((s) => s.maxLogs);
  const size = useLogStore((s) => s.size);
  const storedPosition = useLogStore((s) => s.position);
  const toggleOpen = useLogStore((s) => s.toggleOpen);
  const clearLogs = useLogStore((s) => s.clearLogs);
  const setAutoScroll = useLogStore((s) => s.setAutoScroll);
  const setFilter = useLogStore((s) => s.setFilter);
  const setMaxLogs = useLogStore((s) => s.setMaxLogs);
  const setSize = useLogStore((s) => s.setSize);
  const setStoredPosition = useLogStore((s) => s.setPosition);

  const logs = useFilteredLogs();
  const scrollRef = useRef<HTMLDivElement>(null);
  const isUserScrolling = useRef(false);
  const windowRef = useRef<HTMLDivElement>(null);

  // Local position state for smooth dragging
  const [position, setPosition] = useState({ x: 0, y: 0 });
  const [localSize, setLocalSize] = useState(size);
  const [isDragging, setIsDragging] = useState(false);
  const [isResizing, setIsResizing] = useState<ResizeDirection>(null);
  const [copied, setCopied] = useState(false);
  const dragStart = useRef({ x: 0, y: 0 });
  const resizeStart = useRef({ width: 0, height: 0, x: 0, y: 0, posX: 0, posY: 0 });

  // Virtual list for performance with dynamic row measurement
  const virtualizer = useVirtualizer({
    count: logs.length,
    getScrollElement: () => scrollRef.current,
    estimateSize: () => ROW_HEIGHT,
    overscan: 5,
    measureElement: (element) => element.getBoundingClientRect().height,
  });

  // Initialize position on first open
  const hasInitialized = useRef(false);
  useEffect(() => {
    if (isOpen && !hasInitialized.current) {
      if (storedPosition) {
        setPosition(storedPosition);
      } else {
        // Position at bottom-right with padding
        const x = window.innerWidth - size.width - 24;
        const y = window.innerHeight - size.height - 24;
        setPosition({ x: Math.max(24, x), y: Math.max(60, y) });
      }
      setLocalSize(size);
      hasInitialized.current = true;
    }
  }, [isOpen, storedPosition, size]);

  // Handle drag start
  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    if ((e.target as HTMLElement).closest('button, select, input')) return;

    setIsDragging(true);
    dragStart.current = {
      x: e.clientX - position.x,
      y: e.clientY - position.y,
    };
    e.preventDefault();
  }, [position]);

  // Handle resize start
  const handleResizeStart = useCallback((direction: ResizeDirection) => (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsResizing(direction);
    resizeStart.current = {
      width: localSize.width,
      height: localSize.height,
      x: e.clientX,
      y: e.clientY,
      posX: position.x,
      posY: position.y,
    };
  }, [localSize, position]);

  // Handle drag/resize move
  useEffect(() => {
    if (!isDragging && !isResizing) return;

    const handleMouseMove = (e: MouseEvent) => {
      if (isDragging) {
        const newX = e.clientX - dragStart.current.x;
        const newY = e.clientY - dragStart.current.y;

        // Constrain to viewport
        const maxX = window.innerWidth - localSize.width;
        const maxY = window.innerHeight - 50;

        setPosition({
          x: Math.max(0, Math.min(newX, maxX)),
          y: Math.max(0, Math.min(newY, maxY)),
        });
      } else if (isResizing) {
        const deltaX = e.clientX - resizeStart.current.x;
        const deltaY = e.clientY - resizeStart.current.y;

        let newWidth = resizeStart.current.width;
        let newHeight = resizeStart.current.height;
        let newX = resizeStart.current.posX;
        let newY = resizeStart.current.posY;

        // Handle horizontal resize
        if (isResizing.includes('e')) {
          newWidth = Math.max(MIN_SIZE.width, Math.min(MAX_SIZE.width, resizeStart.current.width + deltaX));
        }
        if (isResizing.includes('w')) {
          const possibleWidth = resizeStart.current.width - deltaX;
          if (possibleWidth >= MIN_SIZE.width && possibleWidth <= MAX_SIZE.width) {
            newWidth = possibleWidth;
            newX = resizeStart.current.posX + deltaX;
          }
        }

        // Handle vertical resize
        if (isResizing.includes('s')) {
          newHeight = Math.max(MIN_SIZE.height, Math.min(MAX_SIZE.height, resizeStart.current.height + deltaY));
        }
        if (isResizing.includes('n')) {
          const possibleHeight = resizeStart.current.height - deltaY;
          if (possibleHeight >= MIN_SIZE.height && possibleHeight <= MAX_SIZE.height) {
            newHeight = possibleHeight;
            newY = resizeStart.current.posY + deltaY;
          }
        }

        setLocalSize({ width: newWidth, height: newHeight });
        setPosition({ x: newX, y: newY });
      }
    };

    const handleMouseUp = () => {
      if (isDragging) {
        setStoredPosition(position);
      }
      if (isResizing) {
        setSize(localSize);
        setStoredPosition(position);
      }
      setIsDragging(false);
      setIsResizing(null);
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);

    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isDragging, isResizing, position, localSize, setSize, setStoredPosition]);

  // Auto-scroll effect using virtualizer
  useEffect(() => {
    if (autoScroll && logs.length > 0 && !isUserScrolling.current) {
      virtualizer.scrollToIndex(logs.length - 1, { align: 'end' });
    }
  }, [logs.length, autoScroll, virtualizer]);

  // Handle manual scroll to disable auto-scroll
  const handleScroll = () => {
    if (!scrollRef.current) return;
    const { scrollTop, scrollHeight, clientHeight } = scrollRef.current;
    const isAtBottom = scrollHeight - scrollTop - clientHeight < 50;

    if (!isAtBottom && autoScroll) {
      isUserScrolling.current = true;
      setAutoScroll(false);
      setTimeout(() => {
        isUserScrolling.current = false;
      }, 100);
    } else if (isAtBottom && !autoScroll) {
      setAutoScroll(true);
    }
  };

  const scrollToBottom = () => {
    if (logs.length > 0) {
      virtualizer.scrollToIndex(logs.length - 1, { align: 'end' });
      setAutoScroll(true);
    }
  };

  const copyLogs = useCallback(() => {
    const text = logs
      .map((log) => `[${formatTimestamp(log.timestamp)}] [${LOG_LEVEL_LABELS[log.level]}] ${log.message}`)
      .join('\n');
    navigator.clipboard.writeText(text).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  }, [logs]);

  if (!isOpen) return null;

  const resizeHandleClass = 'absolute opacity-0 hover:opacity-100 transition-opacity z-10';
  const resizeCursor = {
    n: 'cursor-ns-resize',
    s: 'cursor-ns-resize',
    e: 'cursor-ew-resize',
    w: 'cursor-ew-resize',
    ne: 'cursor-nesw-resize',
    nw: 'cursor-nwse-resize',
    se: 'cursor-nwse-resize',
    sw: 'cursor-nesw-resize',
  };

  return (
    <div
      ref={windowRef}
      className={cn(
        'fixed z-50 flex flex-col',
        'rounded-lg overflow-hidden',
        'backdrop-blur-xl',
        (isDragging || isResizing) && 'select-none'
      )}
      style={{
        width: localSize.width,
        height: localSize.height,
        transform: `translate(${position.x}px, ${position.y}px)`,
        willChange: (isDragging || isResizing) ? 'transform, width, height' : 'auto',
        left: 0,
        top: 0,
        backgroundColor: 'var(--color-surface-0)',
        boxShadow: '0 25px 50px -12px rgba(0, 0, 0, 0.5)',
      }}
    >
      {/* Resize handles */}
      {/* Edges */}
      <div
        className={cn(resizeHandleClass, resizeCursor.n, 'top-0 left-2 right-2 h-1')}
        onMouseDown={handleResizeStart('n')}
      />
      <div
        className={cn(resizeHandleClass, resizeCursor.s, 'bottom-0 left-2 right-2 h-1')}
        onMouseDown={handleResizeStart('s')}
      />
      <div
        className={cn(resizeHandleClass, resizeCursor.e, 'top-2 bottom-2 right-0 w-1')}
        onMouseDown={handleResizeStart('e')}
      />
      <div
        className={cn(resizeHandleClass, resizeCursor.w, 'top-2 bottom-2 left-0 w-1')}
        onMouseDown={handleResizeStart('w')}
      />
      {/* Corners */}
      <div
        className={cn(resizeHandleClass, resizeCursor.nw, 'top-0 left-0 w-3 h-3')}
        onMouseDown={handleResizeStart('nw')}
      />
      <div
        className={cn(resizeHandleClass, resizeCursor.ne, 'top-0 right-0 w-3 h-3')}
        onMouseDown={handleResizeStart('ne')}
      />
      <div
        className={cn(resizeHandleClass, resizeCursor.sw, 'bottom-0 left-0 w-3 h-3')}
        onMouseDown={handleResizeStart('sw')}
      />
      <div
        className={cn(resizeHandleClass, resizeCursor.se, 'bottom-0 right-0 w-3 h-3')}
        onMouseDown={handleResizeStart('se')}
      />

      {/* Header */}
      <div
        className={cn(
          'flex items-center justify-between px-3 py-2 flex-shrink-0',
          isDragging ? 'cursor-grabbing' : 'cursor-grab'
        )}
        style={{
          backgroundColor: 'var(--color-surface-0)',
        }}
        onMouseDown={handleMouseDown}
      >
        <div className="flex items-center gap-2">
          <Terminal
            className="w-3.5 h-3.5"
            style={{ color: 'var(--color-accent)' }}
          />
          <span
            className="text-xs font-medium tracking-tight"
            style={{ color: 'var(--color-text)' }}
          >
            Server Logs
          </span>
          <div
            className="flex items-center gap-1 px-1.5 py-0.5 rounded-md"
            style={{ backgroundColor: 'var(--color-surface-1)' }}
          >
            <span
              className="text-[10px] font-medium tabular-nums"
              style={{ color: 'var(--color-text-muted)' }}
            >
              {logs.length}
            </span>
            <span
              className="text-[9px]"
              style={{ color: 'var(--color-text-muted)', opacity: 0.5 }}
            >
              / {maxLogs}
            </span>
          </div>
        </div>

        <div className="flex items-center gap-1">
          {/* Filter dropdown */}
          <div className="relative">
            <select
              value={filter}
              onChange={(e) => setFilter(e.target.value as LogFilter)}
              className={cn(
                'h-6 pl-2 pr-5 text-[10px] rounded',
                'appearance-none cursor-pointer',
                'focus:outline-none',
                'transition-colors'
              )}
              style={{
                backgroundColor: 'var(--color-surface-0)',
                color: 'var(--color-text)',
              }}
            >
              {FILTER_OPTIONS.map((opt) => (
                <option key={opt.value} value={opt.value}>
                  {opt.label}
                </option>
              ))}
            </select>
            <ChevronDown
              className="absolute right-1 top-1/2 -translate-y-1/2 w-3 h-3 pointer-events-none"
              style={{ color: 'var(--color-text-muted)' }}
            />
          </div>

          {/* Max logs dropdown */}
          <div className="relative">
            <select
              value={maxLogs}
              onChange={(e) => setMaxLogs(Number(e.target.value) as MaxLogsOption)}
              className={cn(
                'h-6 pl-2 pr-5 text-[10px] rounded',
                'appearance-none cursor-pointer',
                'focus:outline-none',
                'transition-colors'
              )}
              style={{
                backgroundColor: 'var(--color-surface-0)',
                color: 'var(--color-text)',
              }}
              title="Maximum log lines to keep"
            >
              {MAX_LOGS_OPTIONS.map((opt) => (
                <option key={opt} value={opt}>
                  {opt} lines
                </option>
              ))}
            </select>
            <ChevronDown
              className="absolute right-1 top-1/2 -translate-y-1/2 w-3 h-3 pointer-events-none"
              style={{ color: 'var(--color-text-muted)' }}
            />
          </div>

          {/* Auto-scroll toggle */}
          <button
            onClick={scrollToBottom}
            className="p-1 rounded transition-all hover:bg-white/5"
            style={{
              backgroundColor: autoScroll
                ? 'color-mix(in srgb, var(--color-accent) 20%, transparent)'
                : 'transparent',
            }}
            title={autoScroll ? 'Auto-scroll enabled' : 'Scroll to bottom'}
          >
            <ArrowDown
              className="w-3.5 h-3.5"
              style={{
                color: autoScroll ? 'var(--color-accent)' : 'var(--color-text-muted)',
              }}
            />
          </button>

          {/* Copy button */}
          <button
            onClick={copyLogs}
            className="p-1 rounded transition-colors hover:bg-white/5"
            title="Copy logs"
            disabled={logs.length === 0}
          >
            {copied ? (
              <Check
                className="w-3.5 h-3.5"
                style={{ color: 'var(--color-success)' }}
              />
            ) : (
              <Copy
                className="w-3.5 h-3.5"
                style={{ color: 'var(--color-text-muted)' }}
              />
            )}
          </button>

          {/* Clear button */}
          <button
            onClick={clearLogs}
            className="p-1 rounded transition-colors hover:bg-white/5"
            title="Clear logs"
          >
            <Trash2
              className="w-3.5 h-3.5"
              style={{ color: 'var(--color-text-muted)' }}
            />
          </button>

          {/* Close button */}
          <button
            onClick={toggleOpen}
            className="p-1 rounded transition-colors hover:bg-white/5"
            title="Close (Ctrl+L)"
          >
            <X
              className="w-3.5 h-3.5"
              style={{ color: 'var(--color-text-muted)' }}
            />
          </button>
        </div>
      </div>

      {/* Log content */}
      <div
        ref={scrollRef}
        onScroll={handleScroll}
        className="flex-1 overflow-y-auto overflow-x-hidden"
        style={{ backgroundColor: 'var(--color-surface-0)' }}
      >
        {logs.length === 0 ? (
          <div
            className="flex flex-col items-center justify-center h-full gap-3 p-8"
            style={{ color: 'var(--color-text-muted)' }}
          >
            <Terminal className="w-8 h-8 opacity-30" />
            <div className="text-center">
              <p className="text-xs font-medium">No logs yet</p>
              <p className="text-[10px] opacity-60 mt-1">
                Logs will appear here when the server generates output
              </p>
            </div>
          </div>
        ) : (
          <div
            className="relative w-full"
            style={{ height: `${virtualizer.getTotalSize()}px` }}
          >
            {virtualizer.getVirtualItems().map((virtualItem) => {
              const log = logs[virtualItem.index];
              return (
                <div
                  key={log.id}
                  ref={virtualizer.measureElement}
                  data-index={virtualItem.index}
                  className="absolute left-0 right-0"
                  style={{
                    transform: `translateY(${virtualItem.start}px)`,
                  }}
                >
                  <LogRow log={log} />
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Footer with resize grip indicator */}
      <div
        className="flex items-center justify-between px-3 py-1 flex-shrink-0"
        style={{
          backgroundColor: 'var(--color-surface-0)',
        }}
      >
        <span
          className="text-[9px] tabular-nums"
          style={{ color: 'var(--color-text-muted)', opacity: 0.5 }}
        >
          {localSize.width} × {localSize.height}
        </span>
        <div
          className="flex items-center gap-0.5 opacity-30"
          style={{ color: 'var(--color-text-muted)' }}
        >
          <GripVertical className="w-3 h-3" />
        </div>
      </div>
    </div>
  );
}
