import { memo, useState, useRef, useEffect, useCallback } from 'react';
import { NodeResizer, type NodeProps } from '@xyflow/react';
import { useGraphStore } from '@/stores/graphStore';

// Preset colors for groups - exported for use in context menu
// eslint-disable-next-line react-refresh/only-export-components
export const GROUP_COLORS = [
  { name: 'Default', value: 'rgba(49, 50, 68, 0.6)' },
  { name: 'Red', value: 'rgba(210, 77, 87, 0.25)' },
  { name: 'Orange', value: 'rgba(250, 179, 135, 0.25)' },
  { name: 'Yellow', value: 'rgba(249, 226, 175, 0.25)' },
  { name: 'Green', value: 'rgba(166, 218, 149, 0.25)' },
  { name: 'Teal', value: 'rgba(139, 213, 202, 0.25)' },
  { name: 'Blue', value: 'rgba(137, 180, 250, 0.25)' },
  { name: 'Purple', value: 'rgba(203, 166, 247, 0.25)' },
  { name: 'Pink', value: 'rgba(245, 194, 231, 0.25)' },
];

interface GroupNodeData {
  label?: string;
  _title?: string;
  color?: string;
  width?: number;
  height?: number;
}

export const GroupNode = memo(({ id, data, selected }: NodeProps) => {
  const nodeData = data as GroupNodeData;
  const updateNodeData = useGraphStore((s) => s.updateNodeData);

  const [isEditing, setIsEditing] = useState(false);
  const [editValue, setEditValue] = useState(nodeData._title || nodeData.label || 'Group');
  const inputRef = useRef<HTMLInputElement>(null);

  // Check if this node should enter rename mode
  const renamingNodeId = useGraphStore((s) => s.renamingNodeId);
  const setRenamingNodeId = useGraphStore((s) => s.setRenamingNodeId);

  const displayTitle = nodeData._title || nodeData.label || 'Group';
  const bgColor = nodeData.color || GROUP_COLORS[0].value;

  // Trigger edit mode when this node is set as renaming
  useEffect(() => {
    if (renamingNodeId === id) {
      setEditValue(displayTitle);
      setIsEditing(true);
      setRenamingNodeId(null);
    }
  }, [id, renamingNodeId, displayTitle, setRenamingNodeId]);

  useEffect(() => {
    if (isEditing && inputRef.current) {
      inputRef.current.focus();
      inputRef.current.select();
    }
  }, [isEditing]);

  const handleDoubleClick = useCallback((e: React.MouseEvent) => {
    e.stopPropagation();
    setEditValue(displayTitle);
    setIsEditing(true);
  }, [displayTitle]);

  const handleSave = useCallback(() => {
    const trimmed = editValue.trim();
    if (trimmed) {
      updateNodeData(id, { _title: trimmed });
    }
    setIsEditing(false);
  }, [editValue, id, updateNodeData]);

  const handleCancel = useCallback(() => {
    setEditValue(displayTitle);
    setIsEditing(false);
  }, [displayTitle]);

  const handleKeyDown = useCallback((e: React.KeyboardEvent<HTMLInputElement>) => {
    e.stopPropagation();
    if (e.key === 'Enter') {
      handleSave();
    } else if (e.key === 'Escape') {
      handleCancel();
    }
  }, [handleSave, handleCancel]);

  return (
    <>
      <NodeResizer
        minWidth={200}
        minHeight={150}
        isVisible={true}
        lineStyle={{
          borderColor: 'transparent',
          borderWidth: 6,
        }}
        handleStyle={{
          width: 14,
          height: 14,
          backgroundColor: 'transparent',
          border: 'none',
        }}
      />
      <div
        className="w-full h-full rounded-xl"
        style={{
          backgroundColor: bgColor,
          border: selected ? '1.5px solid var(--color-accent)' : '1.5px solid transparent',
        }}
      >
        {/* Header with title */}
        <div className="absolute top-0 left-0 right-0 px-3 py-1.5">
          {isEditing ? (
            <input
              ref={inputRef}
              type="text"
              value={editValue}
              onChange={(e) => setEditValue(e.target.value)}
              onBlur={handleSave}
              onKeyDown={handleKeyDown}
              className="text-[11px] font-medium uppercase tracking-wider px-1 h-5 rounded outline-none ring-1 nodrag"
              style={{
                backgroundColor: 'var(--color-surface-2)',
                color: 'var(--color-text)',
                '--tw-ring-color': 'var(--color-overlay-0)',
                minWidth: 60,
              } as React.CSSProperties}
            />
          ) : (
            <span
              className="text-[11px] font-medium uppercase tracking-wider cursor-text"
              style={{ color: 'var(--color-text-muted)' }}
              onDoubleClick={handleDoubleClick}
              title="Double-click to rename"
            >
              {displayTitle}
            </span>
          )}
        </div>
      </div>
    </>
  );
});

GroupNode.displayName = 'GroupNode';

export default GroupNode;
