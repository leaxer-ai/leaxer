import { useEffect, useRef } from 'react';
import { Trash2 } from 'lucide-react';

interface CleanupConfirmDialogProps {
  isOpen: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}

export function CleanupConfirmDialog({
  isOpen,
  onConfirm,
  onCancel,
}: CleanupConfirmDialogProps) {
  const dialogRef = useRef<HTMLDivElement>(null);

  // Handle escape key
  useEffect(() => {
    if (!isOpen) return;

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        onCancel();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, onCancel]);

  // Focus trap and click outside
  useEffect(() => {
    if (!isOpen) return;

    const handleClickOutside = (e: MouseEvent) => {
      if (dialogRef.current && !dialogRef.current.contains(e.target as Node)) {
        onCancel();
      }
    };

    // Add small delay to prevent immediate trigger
    const timeoutId = setTimeout(() => {
      document.addEventListener('mousedown', handleClickOutside);
    }, 100);

    return () => {
      clearTimeout(timeoutId);
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [isOpen, onCancel]);

  if (!isOpen) return null;

  return (
    <div
      className="fixed inset-0 z-[100] flex items-center justify-center"
      style={{ backgroundColor: 'rgba(0, 0, 0, 0.5)' }}
    >
      <div
        ref={dialogRef}
        className="p-5 rounded-xl shadow-xl max-w-md w-full mx-4"
        style={{
          backgroundColor: 'var(--color-surface-0)',
          boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3)',
        }}
      >
        {/* Icon and Content */}
        <div className="flex items-start gap-3 mb-4">
          <div
            className="flex-shrink-0 w-10 h-10 rounded-full flex items-center justify-center"
            style={{ backgroundColor: 'color-mix(in srgb, var(--color-warning) 15%, transparent)' }}
          >
            <Trash2
              className="w-5 h-5"
              style={{ color: 'var(--color-warning)' }}
            />
          </div>
          <div>
            <h3
              className="text-sm font-semibold mb-1"
              style={{ color: 'var(--color-text)' }}
            >
              System Cleanup
            </h3>
            <p
              className="text-xs mb-2"
              style={{ color: 'var(--color-text-muted)' }}
            >
              This will perform the following cleanup actions:
            </p>
            <ul
              className="text-xs space-y-1 ml-2"
              style={{ color: 'var(--color-text-secondary)' }}
            >
              <li>• Stop SD server (free VRAM)</li>
              <li>• Clean up orphaned processes</li>
              <li>• Clear temporary files</li>
              <li>• Clear cache</li>
            </ul>
          </div>
        </div>

        {/* Actions */}
        <div className="flex gap-2 justify-end">
          <button
            onClick={onCancel}
            className="px-3 py-1.5 text-xs rounded-lg transition-colors cursor-pointer"
            style={{
              color: 'var(--color-text)',
              backgroundColor: 'transparent',
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.backgroundColor = 'var(--color-surface-1)';
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.backgroundColor = 'transparent';
            }}
          >
            Cancel
          </button>
          <button
            onClick={onConfirm}
            className="px-3 py-1.5 text-xs rounded-lg transition-colors cursor-pointer"
            style={{
              color: 'var(--color-crust)',
              backgroundColor: 'var(--color-warning)',
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.opacity = '0.9';
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.opacity = '1';
            }}
          >
            Clean Up
          </button>
        </div>
      </div>
    </div>
  );
}
