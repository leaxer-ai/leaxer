import { memo, useMemo, useState, useRef, useCallback, useEffect } from 'react';
import { Handle, Position, NodeResizer, type NodeProps } from '@xyflow/react';
import { useSettingsStore } from '../../../stores/settingsStore';
import { useGraphStore } from '../../../stores/graphStore';
import { getTypeColor } from '../BaseNode';
import { cn } from '@/lib/utils';

const HEADER_HEIGHT = 36;
const HANDLE_ROW_HEIGHT = 22;
const HANDLE_SIZE = 10;
const MIN_WIDTH = 300;
const MIN_HEIGHT = 250;

// Calculate handle position (same as BaseNode)
const getInputHandleTop = (index: number) => {
  return HEADER_HEIGHT + (index * HANDLE_ROW_HEIGHT) + (HANDLE_ROW_HEIGHT / 2);
};

export const CompareImageNode = memo(({ id, data, selected }: NodeProps) => {
  const getApiBaseUrl = useSettingsStore((s) => s.getApiBaseUrl);
  const currentNode = useGraphStore((s) => s.currentNode);
  const executingNodes = useGraphStore((s) => s.executingNodes);
  const containerRef = useRef<HTMLDivElement>(null);

  // Check if this node is currently executing (includes minimum display time)
  const isExecuting = currentNode === id || !!executingNodes[id];
  const [dividerPosition, setDividerPosition] = useState(0.5);
  const [isHovering, setIsHovering] = useState(false);
  const [beforeLoaded, setBeforeLoaded] = useState(false);
  const [afterLoaded, setAfterLoaded] = useState(false);
  const [beforeError, setBeforeError] = useState(false);
  const [afterError, setAfterError] = useState(false);

  const beforePath = data._before_url as string | undefined;
  const afterPath = data._after_url as string | undefined;

  // Construct full URLs
  const beforeUrl = useMemo(() => {
    if (!beforePath) return undefined;
    if (beforePath.startsWith('http://') || beforePath.startsWith('https://') || beforePath.startsWith('data:')) {
      return beforePath;
    }
    if (beforePath.startsWith('/')) {
      return `${getApiBaseUrl()}${beforePath}`;
    }
    return beforePath;
  }, [beforePath, getApiBaseUrl]);

  const afterUrl = useMemo(() => {
    if (!afterPath) return undefined;
    if (afterPath.startsWith('http://') || afterPath.startsWith('https://') || afterPath.startsWith('data:')) {
      return afterPath;
    }
    if (afterPath.startsWith('/')) {
      return `${getApiBaseUrl()}${afterPath}`;
    }
    return afterPath;
  }, [afterPath, getApiBaseUrl]);

  // Reset load states when URLs change
  useEffect(() => {
    setBeforeLoaded(false);
    setBeforeError(false);
  }, [beforeUrl]);

  useEffect(() => {
    setAfterLoaded(false);
    setAfterError(false);
  }, [afterUrl]);

  const handleMouseMove = useCallback((e: React.MouseEvent) => {
    if (!containerRef.current) return;
    const rect = containerRef.current.getBoundingClientRect();
    const x = e.clientX - rect.left;
    setDividerPosition(Math.max(0, Math.min(1, x / rect.width)));
  }, []);

  const handleMouseEnter = useCallback(() => {
    setIsHovering(true);
  }, []);

  const handleMouseLeave = useCallback(() => {
    setIsHovering(false);
    setDividerPosition(0.5);
  }, []);

  // Only show comparison when both images are loaded successfully
  const hasImages = beforeUrl && afterUrl && beforeLoaded && afterLoaded && !beforeError && !afterError;
  const hasPartialImages = (beforeUrl && !beforeError) || (afterUrl && !afterError);

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
            Compare Image
          </span>
        </div>

        {/* Input labels */}
        <div style={{ borderBottom: '1px solid rgba(255, 255, 255, 0.04)' }}>
          <div
            className="flex items-center px-2"
            style={{ height: HANDLE_ROW_HEIGHT }}
          >
            <span className="text-[11px]" style={{ color: 'var(--color-text-muted)' }}>
              BEFORE
            </span>
          </div>
          <div
            className="flex items-center px-2"
            style={{ height: HANDLE_ROW_HEIGHT }}
          >
            <span className="text-[11px]" style={{ color: 'var(--color-text-muted)' }}>
              AFTER
            </span>
          </div>
        </div>

        {/* Image content area */}
        <div className="p-2 flex-1 min-h-0">
          {/* Hidden preload images to track loading state */}
          {beforeUrl && (
            <img
              src={beforeUrl}
              alt=""
              style={{ display: 'none' }}
              onLoad={() => setBeforeLoaded(true)}
              onError={() => setBeforeError(true)}
            />
          )}
          {afterUrl && (
            <img
              src={afterUrl}
              alt=""
              style={{ display: 'none' }}
              onLoad={() => setAfterLoaded(true)}
              onError={() => setAfterError(true)}
            />
          )}

          {hasImages ? (
            <div
              ref={containerRef}
              className="relative w-full h-full rounded overflow-hidden"
              style={{
                border: '1px solid var(--color-overlay-0)',
                backgroundColor: 'var(--color-crust)',
                cursor: 'ew-resize',
              }}
              onMouseMove={handleMouseMove}
              onMouseEnter={handleMouseEnter}
              onMouseLeave={handleMouseLeave}
            >
              {/* After image - full size, bottom layer */}
              <img
                src={afterUrl}
                alt="After"
                className="absolute inset-0 w-full h-full object-contain"
              />

              {/* Before image - clipped from right, top layer */}
              <img
                src={beforeUrl}
                alt="Before"
                className="absolute inset-0 w-full h-full object-contain"
                style={{
                  clipPath: `inset(0 ${(1 - dividerPosition) * 100}% 0 0)`,
                  transition: isHovering ? 'none' : 'clip-path 0.3s ease-out',
                }}
              />

              {/* Divider line */}
              <div
                className="absolute top-0 h-full pointer-events-none"
                style={{
                  left: `${dividerPosition * 100}%`,
                  width: 2,
                  backgroundColor: 'white',
                  transform: 'translateX(-50%)',
                  boxShadow: '0 0 4px rgba(0,0,0,0.5)',
                  transition: isHovering ? 'none' : 'left 0.3s ease-out',
                }}
              />
            </div>
          ) : (
            <div
              className="rounded flex items-center justify-center text-xs w-full h-full"
              style={{
                border: '2px dashed var(--color-overlay-0)',
                backgroundColor: 'color-mix(in srgb, var(--color-crust) 30%, transparent)',
                color: 'var(--color-text-muted)',
              }}
            >
              {(beforeUrl && !beforeLoaded && !beforeError) || (afterUrl && !afterLoaded && !afterError)
                ? 'Loading...'
                : hasPartialImages
                  ? `Missing ${!beforeUrl || beforeError ? 'before' : 'after'} image`
                  : 'No image'}
            </div>
          )}
        </div>
      </div>
      </div>

      {/* Input Handles */}
      <Handle
        type="target"
        position={Position.Left}
        id="before"
        data-handletype="IMAGE"
        className="transition-transform hover:scale-125"
        style={{
          background: getTypeColor('IMAGE'),
          width: HANDLE_SIZE,
          height: HANDLE_SIZE,
          border: 'none',
          top: getInputHandleTop(0),
          zIndex: 10,
        }}
      />
      <Handle
        type="target"
        position={Position.Left}
        id="after"
        data-handletype="IMAGE"
        className="transition-transform hover:scale-125"
        style={{
          background: getTypeColor('IMAGE'),
          width: HANDLE_SIZE,
          height: HANDLE_SIZE,
          border: 'none',
          top: getInputHandleTop(1),
          zIndex: 10,
        }}
      />
    </>
  );
});

CompareImageNode.displayName = 'CompareImageNode';
