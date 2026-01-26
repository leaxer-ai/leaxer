import { memo, useMemo, useState, useEffect } from 'react';
import { Handle, Position, NodeResizer, type NodeProps } from '@xyflow/react';
import { useSettingsStore } from '../../stores/settingsStore';
import { useGraphStore } from '../../stores/graphStore';
import { getTypeColor } from './BaseNode';
import { cn } from '@/lib/utils';

const HEADER_HEIGHT = 36;
const HANDLE_SIZE = 10;
const MIN_WIDTH = 200;
const MIN_HEIGHT = 150;

export const PreviewImageNode = memo(({ id, data, selected }: NodeProps) => {
  const getApiBaseUrl = useSettingsStore((s) => s.getApiBaseUrl);
  const currentNode = useGraphStore((s) => s.currentNode);
  const executingNodes = useGraphStore((s) => s.executingNodes);
  const [imageError, setImageError] = useState(false);

  // Check if this node is currently executing (includes minimum display time)
  const isExecuting = currentNode === id || !!executingNodes[id];

  const previewPath = data._preview as string | undefined;
  const displayTitle = (data._title as string) || 'Preview Image';

  // Construct full URL if preview is a relative path
  const preview = useMemo(() => {
    if (!previewPath) return undefined;
    if (previewPath.startsWith('http://') || previewPath.startsWith('https://')) {
      return previewPath;
    }
    if (previewPath.startsWith('/')) {
      return `${getApiBaseUrl()}${previewPath}`;
    }
    return previewPath;
  }, [previewPath, getApiBaseUrl]);

  // Reset error state when preview URL changes
  useEffect(() => {
    setImageError(false);
  }, [preview]);

  const handleImageError = () => {
    setImageError(true);
  };

  // Show empty state if no preview or if image failed to load
  const showEmptyState = !preview || imageError;

  return (
    <>
      <NodeResizer
        minWidth={MIN_WIDTH}
        minHeight={MIN_HEIGHT}
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
        className={cn(
          'relative rounded-xl w-full h-full',
          isExecuting && 'executing-glow'
        )}
        style={{ minWidth: MIN_WIDTH, minHeight: MIN_HEIGHT }}
      >
      <div
        className="w-full h-full rounded-xl overflow-hidden flex flex-col"
        style={{
          background: isExecuting
            ? 'var(--color-surface-0)'
            : 'color-mix(in srgb, var(--color-surface-0) 90%, transparent)',
          ...(!isExecuting && {
            boxShadow: selected
              ? '0 2px 8px rgba(0, 0, 0, 0.15), inset 0 1px 0 rgba(255, 255, 255, 0.06), inset 0 0 0 2px var(--color-accent)'
              : '0 2px 8px rgba(0, 0, 0, 0.15), inset 0 1px 0 rgba(255, 255, 255, 0.06)',
            backdropFilter: 'blur(12px)',
            WebkitBackdropFilter: 'blur(12px)',
          }),
        }}
      >
        {/* Header */}
        <div
          className="px-3 flex items-center"
          style={{
            height: HEADER_HEIGHT,
            borderBottom: '1px solid rgba(255, 255, 255, 0.06)',
          }}
        >
          <span
            className="text-xs font-semibold truncate"
            style={{ color: 'var(--color-text)' }}
          >
            {displayTitle}
          </span>
        </div>

        {/* Image content area */}
        <div className="p-2 flex-1 min-h-0">
          {showEmptyState ? (
            <div
              className="rounded flex items-center justify-center text-xs w-full h-full"
              style={{
                border: '2px dashed var(--color-overlay-0)',
                backgroundColor: 'color-mix(in srgb, var(--color-crust) 30%, transparent)',
                color: 'var(--color-text-muted)',
              }}
            >
              No image
            </div>
          ) : (
            <img
              src={preview}
              alt="Preview"
              onError={handleImageError}
              className="rounded"
              style={{
                width: '100%',
                height: '100%',
                objectFit: 'contain',
                border: '1px solid var(--color-overlay-0)',
                backgroundColor: 'var(--color-crust)',
              }}
            />
          )}
        </div>
      </div>
      </div>

      {/* Input Handle */}
      <Handle
        type="target"
        position={Position.Left}
        id="image"
        data-handletype="IMAGE"
        style={{
          background: getTypeColor('IMAGE'),
          width: HANDLE_SIZE,
          height: HANDLE_SIZE,
          border: 'none',
          top: HEADER_HEIGHT / 2,
          zIndex: 10,
        }}
      />
    </>
  );
});

PreviewImageNode.displayName = 'PreviewImageNode';
