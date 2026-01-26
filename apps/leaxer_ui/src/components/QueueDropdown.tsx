import { useCallback, useEffect, useRef } from 'react';
import { Trash2 } from 'lucide-react';
import { useQueueStore } from '@/stores/queueStore';

interface QueueDropdownProps {
  onClearQueue: () => void;
}

export function QueueDropdown({ onClearQueue }: QueueDropdownProps) {
  const isOpen = useQueueStore((s) => s.isDrawerOpen);
  const setDrawerOpen = useQueueStore((s) => s.setDrawerOpen);
  const serverPendingCount = useQueueStore((s) => s.serverPendingCount);
  const dropdownRef = useRef<HTMLDivElement>(null);

  const handleClose = useCallback(() => {
    setDrawerOpen(false);
  }, [setDrawerOpen]);

  useEffect(() => {
    if (!isOpen) return;

    const handleClickOutside = (e: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        handleClose();
      }
    };

    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        handleClose();
      }
    };

    // Use 'click' instead of 'mousedown' and add small delay
    const timer = setTimeout(() => {
      document.addEventListener('click', handleClickOutside, true);
      document.addEventListener('keydown', handleEscape);
    }, 100);

    return () => {
      clearTimeout(timer);
      document.removeEventListener('click', handleClickOutside, true);
      document.removeEventListener('keydown', handleEscape);
    };
  }, [isOpen, handleClose]);

  if (!isOpen) return null;

  return (
    <div
      ref={dropdownRef}
      className="fixed top-16 right-4 z-50 min-w-[200px] rounded-xl overflow-hidden backdrop-blur-xl"
      style={{
        background: 'rgba(255, 255, 255, 0.08)',
        boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
      }}
    >
      <div className="flex items-center justify-between px-4 py-3">
        <span
          className="text-[12px]"
          style={{ color: 'var(--color-text-muted)' }}
        >
          <span
            className="text-[18px] font-medium tabular-nums mr-1.5"
            style={{ color: 'var(--color-text)' }}
          >
            {serverPendingCount.toLocaleString()}
          </span>
          {serverPendingCount === 1 ? 'job waiting' : 'jobs waiting'}
        </span>
        {serverPendingCount > 0 && (
          <button
            onClick={onClearQueue}
            className="flex items-center gap-1.5 px-2.5 py-1.5 text-[11px] rounded-lg transition-colors hover:bg-white/10 cursor-pointer ml-4"
            style={{ color: 'var(--color-text-muted)' }}
          >
            <Trash2 className="w-3.5 h-3.5" />
            Clear
          </button>
        )}
      </div>
    </div>
  );
}
