import { memo, useState, useRef, useEffect, useLayoutEffect, type ReactNode, type KeyboardEvent } from 'react';
import { Handle, Position, NodeResizer } from '@xyflow/react';
import { cn } from '@/lib/utils';
import { useGraphStore } from '@/stores/graphStore';
import {
  DATA_TYPE_CSS_VARS,
  DATA_TYPE_COLORS,
  getTypeColor,
  getHandleColor,
  type DataType,
} from '@/lib/dataTypes';

// Re-export for backwards compatibility
// eslint-disable-next-line react-refresh/only-export-components
export { DATA_TYPE_CSS_VARS, DATA_TYPE_COLORS, getTypeColor, getHandleColor };
export type { DataType };

export interface HandleConfig {
  id: string;
  type: 'source' | 'target';
  position: Position;
  label: string;
  dataType?: DataType;
}

interface BaseNodeProps {
  nodeId?: string;
  title: string;
  customTitle?: string;
  onTitleChange?: (newTitle: string) => void;
  children?: ReactNode;
  handles?: HandleConfig[];
  selected?: boolean;
  executing?: boolean;
  hasError?: boolean;
  errorMessage?: string;
  bypassed?: boolean;
}

const HANDLE_ROW_HEIGHT = 22;
const HEADER_HEIGHT = 36;
const HANDLE_SIZE = 10;

export const BaseNode = memo(({
  nodeId,
  title,
  customTitle,
  onTitleChange,
  children,
  handles = [],
  selected,
  executing: executingProp,
  hasError,
  errorMessage,
  bypassed,
}: BaseNodeProps) => {
  const inputs = handles.filter(h => h.type === 'target');
  const outputs = handles.filter(h => h.type === 'source');

  // Auto-detect execution state from store if nodeId is provided
  const currentNode = useGraphStore((s) => s.currentNode);
  const executingNodes = useGraphStore((s) => s.executingNodes);

  // Use prop if provided, otherwise derive from store
  // Check both currentNode and executingNodes for minimum display time
  const executing = executingProp ?? (nodeId ? (currentNode === nodeId || !!executingNodes[nodeId]) : false);

  const [isEditing, setIsEditing] = useState(false);
  const [editValue, setEditValue] = useState(customTitle || title);
  const [childrenHeight, setChildrenHeight] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const childrenRef = useRef<HTMLDivElement>(null);

  // Check if this node should enter rename mode
  const renamingNodeId = useGraphStore((s) => s.renamingNodeId);
  const setRenamingNodeId = useGraphStore((s) => s.setRenamingNodeId);

  const displayTitle = customTitle || title;

  // Trigger edit mode when this node is set as renaming
  useEffect(() => {
    if (nodeId && renamingNodeId === nodeId && onTitleChange) {
      setEditValue(displayTitle);
      setIsEditing(true);
      setRenamingNodeId(null); // Clear the renaming state
    }
  }, [nodeId, renamingNodeId, displayTitle, onTitleChange, setRenamingNodeId]);

  // Measure children section height after layout
  useLayoutEffect(() => {
    if (childrenRef.current) {
      setChildrenHeight(childrenRef.current.offsetHeight);
    }
  }, [children]);

  useEffect(() => {
    if (isEditing && inputRef.current) {
      inputRef.current.focus();
      inputRef.current.select();
    }
  }, [isEditing]);

  const handleDoubleClick = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (onTitleChange) {
      setEditValue(displayTitle);
      setIsEditing(true);
    }
  };

  const handleSave = () => {
    const trimmed = editValue.trim();
    if (trimmed && onTitleChange) {
      onTitleChange(trimmed);
    }
    setIsEditing(false);
  };

  const handleCancel = () => {
    setEditValue(displayTitle);
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

  // Calculate handle positions (from top)
  // Return the row center - React Flow's CSS applies transform: translate(-50%, -50%)
  // which automatically centers the handle on this point
  const getInputHandleTop = (index: number) => {
    return HEADER_HEIGHT + (index * HANDLE_ROW_HEIGHT) + (HANDLE_ROW_HEIGHT / 2);
  };

  const getOutputHandleTop = (index: number) => {
    const inputsHeight = inputs.length * HANDLE_ROW_HEIGHT;
    return HEADER_HEIGHT + inputsHeight + childrenHeight + (index * HANDLE_ROW_HEIGHT) + (HANDLE_ROW_HEIGHT / 2);
  };

  return (
    <>
      <NodeResizer
        minWidth={300}
        isVisible={true}
        shouldResize={(_event, params) => {
          // Only allow horizontal resizing (left/right edges)
          return params.direction[1] === 0;
        }}
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
        className={cn(
          'relative rounded-xl w-full',
          executing && 'executing-glow'
        )}
        style={{
          minWidth: 300,
          opacity: bypassed ? 0.5 : 1,
        }}
      >
      <div
        className="rounded-xl w-full overflow-hidden"
        style={{
          // Use opaque background when executing to hide rainbow gradient underneath
          background: executing
            ? 'var(--color-surface-0)'
            : 'color-mix(in srgb, var(--color-surface-0) 90%, transparent)',
          // Only apply boxShadow when not executing (CSS animation handles executing state)
          ...(!executing && {
            boxShadow: hasError
              ? '0 2px 8px rgba(0, 0, 0, 0.15), inset 0 1px 0 rgba(255, 255, 255, 0.06), 0 0 12px rgba(248, 113, 113, 0.3)'
              : selected
                ? '0 2px 8px rgba(0, 0, 0, 0.15), inset 0 1px 0 rgba(255, 255, 255, 0.06), inset 0 0 0 2px var(--color-accent)'
                : '0 2px 8px rgba(0, 0, 0, 0.15), inset 0 1px 0 rgba(255, 255, 255, 0.06)',
            backdropFilter: 'blur(12px)',
            WebkitBackdropFilter: 'blur(12px)',
          }),
          border: hasError
            ? '2px solid var(--color-error)'
            : '1.5px solid transparent',
        } as React.CSSProperties}
        title={hasError ? errorMessage : undefined}
      >
        {/* Error badge */}
        {hasError && (
          <div
            className="absolute -top-2 -right-2 w-5 h-5 rounded-full flex items-center justify-center z-20"
            style={{
              backgroundColor: 'var(--color-error)',
              boxShadow: '0 2px 4px rgba(0, 0, 0, 0.2)',
            }}
            title={errorMessage}
          >
            <svg
              className="w-3 h-3"
              style={{ color: 'var(--color-crust)' }}
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="3"
            >
              <path d="M12 9v2m0 4h.01" />
            </svg>
          </div>
        )}
        {/* Bypass badge */}
        {bypassed && (
          <div
            className="absolute -top-2 -right-2 w-5 h-5 rounded-full flex items-center justify-center z-20"
            style={{
              backgroundColor: 'var(--color-warning)',
              boxShadow: '0 2px 4px rgba(0, 0, 0, 0.2)',
            }}
            title="Bypassed - data passes through without processing"
          >
            <svg
              className="w-3 h-3"
              style={{ color: 'var(--color-crust)' }}
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2.5"
            >
              <path strokeLinecap="round" strokeLinejoin="round" d="M13.5 4.5L21 12m0 0l-7.5 7.5M21 12H3" />
            </svg>
          </div>
        )}
        {/* Diagonal stripes overlay for bypassed nodes */}
        {bypassed && (
          <div
            className="absolute inset-0 rounded-xl pointer-events-none z-10"
            style={{
              backgroundImage: 'repeating-linear-gradient(45deg, transparent, transparent 8px, rgba(255, 200, 50, 0.08) 8px, rgba(255, 200, 50, 0.08) 16px)',
            }}
          />
        )}
      {/* Header */}
      <div
        className="px-3 flex items-center gap-2"
        style={{
          height: HEADER_HEIGHT,
          borderBottom: '1px solid rgba(255, 255, 255, 0.06)',
        }}
      >
        {executing && (
          <span
            className="w-2 h-2 rounded-full animate-pulse flex-shrink-0"
            style={{ backgroundColor: 'var(--color-warning)' }}
          />
        )}
        {isEditing ? (
          <input
            ref={inputRef}
            type="text"
            value={editValue}
            onChange={(e) => setEditValue(e.target.value)}
            onBlur={handleSave}
            onKeyDown={handleKeyDown}
            className="text-xs font-semibold px-1.5 h-5 rounded outline-none ring-1 flex-1 nodrag"
            style={{
              backgroundColor: 'var(--color-surface-2)',
              color: 'var(--color-text)',
              '--tw-ring-color': 'var(--color-overlay-0)',
            } as React.CSSProperties}
          />
        ) : (
          <span
            className={cn(
              "text-xs font-semibold truncate h-5 flex items-center",
              onTitleChange && "cursor-text"
            )}
            style={{ color: 'var(--color-text)' }}
            onDoubleClick={handleDoubleClick}
            title={onTitleChange ? "Double-click to rename" : undefined}
          >
            {displayTitle}
          </span>
        )}
      </div>

      {/* Inputs */}
      {inputs.length > 0 && (
        <div
          style={{
            borderBottom: '1px solid rgba(255, 255, 255, 0.04)',
          }}
        >
          {inputs.map((handle) => (
            <div
              key={handle.id}
              className="flex items-center px-2 transition-colors hover:bg-[var(--color-surface-1)]/30"
              style={{ height: HANDLE_ROW_HEIGHT }}
            >
              <span className="text-[11px]" style={{ color: 'var(--color-text-muted)' }}>
                {handle.label}
              </span>
            </div>
          ))}
        </div>
      )}

      {/* Content/Parameters */}
      {children && (
        <div
          ref={childrenRef}
          className="p-3 w-full overflow-hidden"
          style={{
            borderBottom: '1px solid rgba(255, 255, 255, 0.04)',
          }}
        >
          <div className="w-full max-w-full" style={{ overflowWrap: 'break-word', wordBreak: 'break-word' }}>
            {children}
          </div>
        </div>
      )}

      {/* Outputs */}
      {outputs.length > 0 && (
        <div>
          {outputs.map((handle) => (
            <div
              key={handle.id}
              className="flex items-center justify-end px-2 transition-colors hover:bg-[var(--color-surface-1)]/30"
              style={{ height: HANDLE_ROW_HEIGHT }}
            >
              <span className="text-[11px]" style={{ color: 'var(--color-text-muted)' }}>
                {handle.label}
              </span>
            </div>
          ))}
        </div>
      )}

    </div>
    </div>

      {/* Input Handles - outside overflow-hidden container */}
      {inputs.map((handle, index) => (
        <Handle
          key={`${handle.id}-${handle.type}`}
          type={handle.type}
          position={Position.Left}
          id={handle.id}
          data-handletype={handle.dataType}
          style={{
            background: getTypeColor(handle.dataType),
            width: HANDLE_SIZE,
            height: HANDLE_SIZE,
            border: 'none',
            top: getInputHandleTop(index),
            zIndex: 10,
          }}
          className="transition-transform hover:scale-125"
        />
      ))}

      {/* Output Handles - outside overflow-hidden container */}
      {outputs.map((handle, index) => (
        <Handle
          key={`${handle.id}-${handle.type}`}
          type={handle.type}
          position={Position.Right}
          id={handle.id}
          data-handletype={handle.dataType}
          style={{
            background: getTypeColor(handle.dataType),
            width: HANDLE_SIZE,
            height: HANDLE_SIZE,
            border: 'none',
            top: getOutputHandleTop(index),
            zIndex: 10,
          }}
          className="transition-transform hover:scale-125"
        />
      ))}
    </>
  );
});

BaseNode.displayName = 'BaseNode';
