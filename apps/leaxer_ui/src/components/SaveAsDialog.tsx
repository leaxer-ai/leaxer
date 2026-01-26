import { useCallback, useEffect, useRef, useState } from 'react';

interface SaveAsDialogProps {
  isOpen: boolean;
  defaultName: string;
  onSave: (name: string) => void;
  onCancel: () => void;
}

export function SaveAsDialog({
  isOpen,
  defaultName,
  onSave,
  onCancel,
}: SaveAsDialogProps) {
  const dialogRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const [name, setName] = useState(defaultName);

  // Reset name when dialog opens
  useEffect(() => {
    if (isOpen) {
      setName(defaultName);
      // Focus input after a short delay
      setTimeout(() => {
        inputRef.current?.focus();
        inputRef.current?.select();
      }, 50);
    }
  }, [isOpen, defaultName]);

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

  // Click outside to close
  useEffect(() => {
    if (!isOpen) return;

    const handleClickOutside = (e: MouseEvent) => {
      if (dialogRef.current && !dialogRef.current.contains(e.target as Node)) {
        onCancel();
      }
    };

    const timeoutId = setTimeout(() => {
      document.addEventListener('mousedown', handleClickOutside);
    }, 100);

    return () => {
      clearTimeout(timeoutId);
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [isOpen, onCancel]);

  const handleSubmit = useCallback(
    (e: React.FormEvent) => {
      e.preventDefault();
      const trimmedName = name.trim();
      if (trimmedName) {
        onSave(trimmedName);
      }
    },
    [name, onSave]
  );

  if (!isOpen) return null;

  return (
    <div
      className="fixed inset-0 z-[100] flex items-center justify-center"
      style={{ backgroundColor: 'rgba(0, 0, 0, 0.5)' }}
    >
      <div
        ref={dialogRef}
        className="p-5 rounded-xl shadow-xl max-w-sm w-full mx-4"
        style={{
          backgroundColor: 'var(--color-surface-0)',
          boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3)',
        }}
      >
        <form onSubmit={handleSubmit}>
          {/* Header */}
          <h3
            className="text-sm font-semibold mb-4"
            style={{ color: 'var(--color-text)' }}
          >
            Save Workflow As
          </h3>

          {/* Input */}
          <div className="mb-4">
            <label
              htmlFor="workflow-name"
              className="block text-xs mb-1.5"
              style={{ color: 'var(--color-text-muted)' }}
            >
              Name
            </label>
            <input
              ref={inputRef}
              id="workflow-name"
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Enter workflow name"
              className="w-full px-3 py-2 text-sm rounded-lg outline-none transition-colors"
              style={{
                backgroundColor: 'var(--color-surface-1)',
                color: 'var(--color-text)',
                border: '1px solid var(--color-overlay-0)',
              }}
              onFocus={(e) => {
                e.currentTarget.style.borderColor = 'var(--color-accent)';
              }}
              onBlur={(e) => {
                e.currentTarget.style.borderColor = 'var(--color-overlay-0)';
              }}
            />
          </div>

          {/* Actions */}
          <div className="flex gap-2 justify-end">
            <button
              type="button"
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
              type="submit"
              disabled={!name.trim()}
              className="px-3 py-1.5 text-xs rounded-lg transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
              style={{
                color: 'var(--color-crust)',
                backgroundColor: 'var(--color-accent)',
              }}
              onMouseEnter={(e) => {
                if (!e.currentTarget.disabled) {
                  e.currentTarget.style.opacity = '0.9';
                }
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.opacity = '1';
              }}
            >
              Save
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
