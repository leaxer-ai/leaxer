import { useReactFlow, useViewport } from '@xyflow/react';
import { ZoomIn, ZoomOut, Maximize, Lock, Unlock } from 'lucide-react';
import { useCallback } from 'react';
import { cn } from '@/lib/utils';
import { useUIStore } from '@/stores/uiStore';

interface ZoomControlButtonProps {
  onClick: () => void;
  title: string;
  disabled?: boolean;
  children: React.ReactNode;
}

function ZoomControlButton({ onClick, title, disabled, children }: ZoomControlButtonProps) {
  return (
    <button
      onClick={onClick}
      title={title}
      disabled={disabled}
      className={cn(
        "w-[44px] h-[44px] flex items-center justify-center transition-all duration-150 cursor-pointer",
        "hover:bg-white/10 active:scale-95 disabled:opacity-40 disabled:cursor-not-allowed"
      )}
      style={{ color: 'var(--color-text-secondary)' }}
    >
      {children}
    </button>
  );
}

export function ZoomControls() {
  const { zoomIn, zoomOut, fitView } = useReactFlow();
  const viewport = useViewport();
  const isLocked = useUIStore((s) => s.viewportLocked);
  const toggleViewportLocked = useUIStore((s) => s.toggleViewportLocked);

  const handleZoomIn = useCallback(() => {
    if (isLocked) return;
    zoomIn({ duration: 200 });
  }, [zoomIn, isLocked]);

  const handleZoomOut = useCallback(() => {
    if (isLocked) return;
    zoomOut({ duration: 200 });
  }, [zoomOut, isLocked]);

  const handleFitView = useCallback(() => {
    if (isLocked) return;
    fitView({ duration: 300, padding: 0.1 });
  }, [fitView, isLocked]);

  // Format zoom percentage
  const zoomPercentage = Math.round(viewport.zoom * 100);

  return (
    <div
      className="flex flex-row items-center overflow-hidden"
      style={{
        backgroundColor: 'rgba(255, 255, 255, 0.08)',
        backdropFilter: 'blur(24px)',
        WebkitBackdropFilter: 'blur(24px)',
        borderRadius: '9999px',
        boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
      }}
    >
      <ZoomControlButton onClick={handleZoomOut} title="Zoom out" disabled={isLocked}>
        <ZoomOut className="w-4 h-4" />
      </ZoomControlButton>

      {/* Zoom percentage display */}
      <div
        className="h-[44px] w-12 flex items-center justify-center text-[11px] font-medium select-none tabular-nums"
        style={{ color: 'var(--color-text-muted)' }}
        title={`Current zoom: ${zoomPercentage}%`}
      >
        {zoomPercentage}%
      </div>

      <ZoomControlButton onClick={handleZoomIn} title="Zoom in" disabled={isLocked}>
        <ZoomIn className="w-4 h-4" />
      </ZoomControlButton>

      <ZoomControlButton onClick={handleFitView} title="Fit view" disabled={isLocked}>
        <Maximize className="w-4 h-4" />
      </ZoomControlButton>

      <button
        onClick={toggleViewportLocked}
        title={isLocked ? 'Unlock viewport' : 'Lock viewport'}
        className={cn(
          "w-[44px] h-[44px] flex items-center justify-center transition-all duration-150 cursor-pointer",
          "hover:bg-white/10 active:scale-95"
        )}
        style={{ color: isLocked ? 'var(--color-accent)' : 'var(--color-text-secondary)' }}
      >
        {isLocked ? <Lock className="w-4 h-4" /> : <Unlock className="w-4 h-4" />}
      </button>
    </div>
  );
}
