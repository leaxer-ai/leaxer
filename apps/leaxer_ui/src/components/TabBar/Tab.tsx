import { memo, useState, useRef, useEffect, type KeyboardEvent, type DragEvent } from 'react';
import { cn } from '@/lib/utils';

interface TabProps {
  id: string;
  name: string;
  isActive: boolean;
  isDirty: boolean;
  index: number;
  onActivate: () => void;
  onClose: () => void;
  onRename: (newName: string) => void;
  onDragStart: (e: DragEvent, index: number) => void;
  onDragOver: (e: DragEvent, index: number) => void;
  onDragEnd: () => void;
  isDragTarget: boolean;
}

export const Tab = memo(function Tab({
  name,
  isActive,
  isDirty,
  index,
  onActivate,
  onClose,
  onRename,
  onDragStart,
  onDragOver,
  onDragEnd,
  isDragTarget,
}: TabProps) {
  const [isEditing, setIsEditing] = useState(false);
  const [editValue, setEditValue] = useState(name);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (isEditing && inputRef.current) {
      inputRef.current.focus();
      inputRef.current.select();
    }
  }, [isEditing]);

  useEffect(() => {
    setEditValue(name);
  }, [name]);

  const handleDoubleClick = (e: React.MouseEvent) => {
    e.stopPropagation();
    setIsEditing(true);
    setEditValue(name);
  };

  const handleSave = () => {
    const trimmed = editValue.trim();
    if (trimmed && trimmed !== name) {
      onRename(trimmed);
    } else {
      setEditValue(name);
    }
    setIsEditing(false);
  };

  const handleCancel = () => {
    setEditValue(name);
    setIsEditing(false);
  };

  const handleKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    e.stopPropagation();
    if (e.key === 'Enter') {
      handleSave();
    } else if (e.key === 'Escape') {
      handleCancel();
    }
  };

  const handleCloseClick = (e: React.MouseEvent) => {
    e.stopPropagation();
    onClose();
  };

  const handleDragStart = (e: DragEvent<HTMLDivElement>) => {
    e.dataTransfer.effectAllowed = 'move';
    e.dataTransfer.setData('text/plain', index.toString());
    onDragStart(e, index);
  };

  const handleDragOver = (e: DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
    onDragOver(e, index);
  };

  return (
    <div
      className={cn(
        'tab-chip',
        isActive && 'active',
        isDragTarget && 'drag-target'
      )}
      onClick={onActivate}
      onDoubleClick={handleDoubleClick}
      draggable={!isEditing}
      onDragStart={handleDragStart}
      onDragOver={handleDragOver}
      onDragEnd={onDragEnd}
    >
      {/* Dirty indicator */}
      {isDirty && <span className="tab-dirty-indicator" title="Unsaved changes" />}

      {/* Tab name / edit input */}
      {isEditing ? (
        <input
          ref={inputRef}
          type="text"
          value={editValue}
          onChange={(e) => setEditValue(e.target.value)}
          onBlur={handleSave}
          onKeyDown={handleKeyDown}
          className="tab-chip-input"
          onClick={(e) => e.stopPropagation()}
        />
      ) : (
        <span className="tab-chip-name" title={name}>
          {name}
        </span>
      )}

      {/* Close button */}
      <button
        className="tab-close-button"
        onClick={handleCloseClick}
        title="Close tab"
      >
        <svg
          className="w-3 h-3"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
        >
          <path d="M18 6L6 18M6 6l12 12" />
        </svg>
      </button>
    </div>
  );
});
