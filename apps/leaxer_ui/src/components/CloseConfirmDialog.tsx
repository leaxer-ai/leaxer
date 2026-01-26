import { useCallback, useEffect, useRef } from 'react';

interface CloseConfirmDialogProps {
  isOpen: boolean;
  workflowName: string;
  onSave: () => void;
  onDontSave: () => void;
  onCancel: () => void;
}

export function CloseConfirmDialog({
  isOpen,
  workflowName,
  onSave,
  onDontSave,
  onCancel,
}: CloseConfirmDialogProps) {
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

  const handleSave = useCallback(() => {
    onSave();
  }, [onSave]);

  const handleDontSave = useCallback(() => {
    onDontSave();
  }, [onDontSave]);

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
        {/* Warning Icon */}
        <div className="flex items-start gap-3 mb-4">
          <div
            className="flex-shrink-0 w-10 h-10 rounded-full flex items-center justify-center"
            style={{ backgroundColor: 'rgba(var(--color-warning-rgb, 251, 191, 36), 0.15)' }}
          >
            <svg
              className="w-5 h-5"
              style={{ color: 'var(--color-warning)' }}
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
            >
              <path d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
          </div>
          <div>
            <h3
              className="text-sm font-semibold mb-1"
              style={{ color: 'var(--color-text)' }}
            >
              Unsaved Changes
            </h3>
            <p
              className="text-xs"
              style={{ color: 'var(--color-text-muted)' }}
            >
              Do you want to save changes to "{workflowName}" before closing?
            </p>
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
            onClick={handleDontSave}
            className="px-3 py-1.5 text-xs rounded-lg transition-colors cursor-pointer"
            style={{
              color: 'var(--color-error)',
              backgroundColor: 'rgba(var(--color-error-rgb, 248, 113, 113), 0.1)',
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.backgroundColor = 'rgba(var(--color-error-rgb, 248, 113, 113), 0.2)';
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.backgroundColor = 'rgba(var(--color-error-rgb, 248, 113, 113), 0.1)';
            }}
          >
            Don't Save
          </button>
          <button
            onClick={handleSave}
            className="px-3 py-1.5 text-xs rounded-lg transition-colors cursor-pointer"
            style={{
              color: 'var(--color-crust)',
              backgroundColor: 'var(--color-accent)',
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.opacity = '0.9';
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.opacity = '1';
            }}
          >
            Save
          </button>
        </div>
      </div>
    </div>
  );
}
