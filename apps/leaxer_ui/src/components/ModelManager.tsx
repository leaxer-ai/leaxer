import { useEffect, useMemo, useRef, useState } from 'react';
import {
  X,
  Download,
  Search,
  CheckCircle,
  ExternalLink,
  AlertCircle,
  Loader2,
  Box,
  Layers,
  Palette,
  Sliders,
  Cpu,
  Type,
  ArrowUp,
  XCircle,
  Sparkles,
  HardDrive,
  Scale,
  Clock,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { useDownloadStore, type RegistryModel, type ActiveDownload } from '@/stores/downloadStore';
import { useDownloadChannel } from '@/hooks/useDownloadChannel';

type CategoryId = 'checkpoints' | 'loras' | 'vaes' | 'controlnets' | 'llms' | 'text_encoders' | 'upscalers';

const CATEGORIES: { id: CategoryId; label: string; description: string; icon: React.ReactNode }[] = [
  { id: 'checkpoints', label: 'Checkpoints', description: 'Base generation models', icon: <Box className="w-4 h-4" /> },
  { id: 'loras', label: 'LoRAs', description: 'Style adapters', icon: <Layers className="w-4 h-4" /> },
  { id: 'vaes', label: 'VAEs', description: 'Autoencoders', icon: <Palette className="w-4 h-4" /> },
  { id: 'controlnets', label: 'ControlNets', description: 'Image control', icon: <Sliders className="w-4 h-4" /> },
  { id: 'llms', label: 'LLMs', description: 'Language models', icon: <Cpu className="w-4 h-4" /> },
  { id: 'text_encoders', label: 'Text Encoders', description: 'Text processing', icon: <Type className="w-4 h-4" /> },
  { id: 'upscalers', label: 'Upscalers', description: 'Image enhancement', icon: <ArrowUp className="w-4 h-4" /> },
];

function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`;
}

function formatSpeed(bps: number): string {
  if (bps === 0) return '0 B/s';
  return `${formatBytes(bps)}/s`;
}

function formatETA(bytesRemaining: number, speedBps: number): string {
  if (speedBps <= 0) return '--';
  const seconds = Math.ceil(bytesRemaining / speedBps);
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.ceil(seconds / 60)}m`;
  return `${Math.floor(seconds / 3600)}h ${Math.ceil((seconds % 3600) / 60)}m`;
}

interface DownloadProgressProps {
  download: ActiveDownload;
  onCancel: () => void;
  compact?: boolean;
}

function DownloadProgress({ download, onCancel, compact = false }: DownloadProgressProps) {
  const isActive = download.status === 'downloading' || download.status === 'pending';
  const isFailed = download.status === 'failed' || download.status === 'cancelled';
  const bytesRemaining = download.total_bytes - download.bytes_downloaded;

  if (compact) {
    return (
      <div className="group relative">
        <div
          className="p-2.5 rounded-lg transition-all duration-200"
          style={{ backgroundColor: 'color-mix(in srgb, var(--color-surface-1) 60%, transparent)' }}
        >
          <div className="flex items-center gap-2 mb-1.5">
            <div className="flex-1 min-w-0">
              <span className="text-[11px] font-medium truncate block" style={{ color: 'var(--color-text)' }}>
                {download.model_name || download.filename}
              </span>
            </div>
            {isActive && (
              <button
                onClick={onCancel}
                className="p-0.5 rounded opacity-0 group-hover:opacity-100 hover:bg-white/10 transition-all"
                title="Cancel"
              >
                <XCircle className="w-3 h-3" style={{ color: 'var(--color-error)' }} />
              </button>
            )}
          </div>

          {isActive && (
            <>
              <div className="h-1 rounded-full overflow-hidden" style={{ backgroundColor: 'var(--color-surface-0)' }}>
                <div
                  className="h-full rounded-full transition-all duration-500 ease-out"
                  style={{
                    width: `${download.percentage}%`,
                    background: 'linear-gradient(90deg, var(--color-accent), color-mix(in srgb, var(--color-accent) 80%, white))',
                  }}
                />
              </div>
              <div className="flex items-center justify-between mt-1 text-[9px]" style={{ color: 'var(--color-text-muted)' }}>
                <span className="font-medium">{download.percentage}%</span>
                <span>{formatSpeed(download.speed_bps)}</span>
              </div>
            </>
          )}

          {download.status === 'complete' && (
            <div className="flex items-center gap-1.5 text-[10px]" style={{ color: 'var(--color-success)' }}>
              <CheckCircle className="w-3 h-3" />
              <span>Done</span>
            </div>
          )}

          {isFailed && (
            <div className="flex items-center gap-1.5 text-[10px]" style={{ color: 'var(--color-error)' }}>
              <AlertCircle className="w-3 h-3" />
              <span className="truncate">{download.status === 'cancelled' ? 'Cancelled' : 'Failed'}</span>
            </div>
          )}
        </div>
      </div>
    );
  }

  return (
    <div
      className="p-3 rounded-xl"
      style={{ backgroundColor: 'color-mix(in srgb, var(--color-surface-1) 50%, transparent)' }}
    >
      <div className="flex items-center justify-between mb-2">
        <span className="text-[12px] font-medium truncate flex-1" style={{ color: 'var(--color-text)' }}>
          {download.model_name || download.filename}
        </span>
        {isActive && (
          <button
            onClick={onCancel}
            className="p-1 rounded hover:bg-white/10 transition-colors"
            title="Cancel download"
          >
            <XCircle className="w-3.5 h-3.5" style={{ color: 'var(--color-text-muted)' }} />
          </button>
        )}
      </div>

      {isActive && (
        <>
          <div className="h-1.5 rounded-full overflow-hidden mb-2" style={{ backgroundColor: 'var(--color-surface-0)' }}>
            <div
              className="h-full rounded-full transition-all duration-300"
              style={{
                width: `${download.percentage}%`,
                background: 'linear-gradient(90deg, var(--color-accent), color-mix(in srgb, var(--color-accent) 80%, white))',
              }}
            />
          </div>
          <div className="flex items-center justify-between text-[10px]" style={{ color: 'var(--color-text-muted)' }}>
            <span className="font-semibold" style={{ color: 'var(--color-text)' }}>{download.percentage}%</span>
            <span>{formatBytes(download.bytes_downloaded)} / {formatBytes(download.total_bytes)}</span>
            <div className="flex items-center gap-1">
              <Clock className="w-3 h-3" />
              <span>{formatETA(bytesRemaining, download.speed_bps)}</span>
            </div>
            <span className="font-medium">{formatSpeed(download.speed_bps)}</span>
          </div>
        </>
      )}

      {download.status === 'complete' && (
        <div className="flex items-center gap-2 text-[11px]" style={{ color: 'var(--color-success)' }}>
          <CheckCircle className="w-3.5 h-3.5" />
          <span>Complete</span>
        </div>
      )}

      {isFailed && (
        <div className="flex items-center gap-2 text-[11px]" style={{ color: 'var(--color-error)' }}>
          <AlertCircle className="w-3.5 h-3.5" />
          <span className="truncate">{download.error || 'Download failed'}</span>
        </div>
      )}
    </div>
  );
}

interface ModelCardProps {
  model: RegistryModel;
  isInstalled: boolean;
  isDownloading: boolean;
  activeDownload?: ActiveDownload;
  onDownload: () => void;
  onCancel: () => void;
}

function ModelCard({ model, isInstalled, isDownloading, activeDownload, onDownload, onCancel }: ModelCardProps) {
  const bytesRemaining = activeDownload ? activeDownload.total_bytes - activeDownload.bytes_downloaded : 0;

  return (
    <div
      className={cn(
        'group relative rounded-xl transition-all duration-200 overflow-hidden',
        isInstalled && 'ring-1 ring-[var(--color-success)]/20',
        activeDownload?.status === 'downloading' && 'ring-1 ring-[var(--color-accent)]/30'
      )}
      style={{
        backgroundColor: 'color-mix(in srgb, var(--color-surface-1) 50%, transparent)',
      }}
    >
      {/* Progress bar background for downloading state */}
      {activeDownload?.status === 'downloading' && (
        <div
          className="absolute inset-0 opacity-10 transition-all duration-500"
          style={{
            background: `linear-gradient(90deg, var(--color-accent) ${activeDownload.percentage}%, transparent ${activeDownload.percentage}%)`,
          }}
        />
      )}

      <div className="relative p-4">
        {/* Header row */}
        <div className="flex items-start justify-between gap-3 mb-3">
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 flex-wrap mb-1">
              <h4 className="text-[13px] font-semibold truncate" style={{ color: 'var(--color-text)' }}>
                {model.name}
              </h4>
              {model.recommended && (
                <span
                  className="inline-flex items-center gap-1 px-1.5 py-0.5 text-[9px] font-semibold rounded-full"
                  style={{
                    background: 'linear-gradient(135deg, var(--color-accent), color-mix(in srgb, var(--color-accent) 70%, var(--color-mauve)))',
                    color: 'var(--color-base)',
                  }}
                >
                  <Sparkles className="w-2.5 h-2.5" />
                  PICK
                </span>
              )}
              {isInstalled && (
                <span
                  className="inline-flex items-center gap-1 px-1.5 py-0.5 text-[9px] font-semibold rounded-full"
                  style={{
                    backgroundColor: 'color-mix(in srgb, var(--color-success) 20%, transparent)',
                    color: 'var(--color-success)',
                  }}
                >
                  <CheckCircle className="w-2.5 h-2.5" />
                  READY
                </span>
              )}
            </div>
          </div>

          <a
            href={model.homepage}
            target="_blank"
            rel="noopener noreferrer"
            className="p-1.5 rounded-lg opacity-40 hover:opacity-100 hover:bg-white/5 transition-all flex-shrink-0"
            title="View on source"
          >
            <ExternalLink className="w-3.5 h-3.5" style={{ color: 'var(--color-text)' }} />
          </a>
        </div>

        {/* Description */}
        <p className="text-[11px] leading-relaxed mb-3 line-clamp-2" style={{ color: 'var(--color-text-muted)' }}>
          {model.description}
        </p>

        {/* Meta info row */}
        <div className="flex flex-wrap items-center gap-2 mb-3">
          <span
            className="inline-flex items-center gap-1 px-2 py-1 text-[10px] font-medium rounded-md"
            style={{
              backgroundColor: 'color-mix(in srgb, var(--color-surface-0) 80%, transparent)',
              color: 'var(--color-text-muted)',
            }}
          >
            <HardDrive className="w-3 h-3" />
            {model.size_human}
          </span>
          <span
            className="inline-flex items-center gap-1 px-2 py-1 text-[10px] font-medium rounded-md uppercase"
            style={{
              backgroundColor: 'color-mix(in srgb, var(--color-surface-0) 80%, transparent)',
              color: 'var(--color-text-muted)',
            }}
          >
            {model.format}
          </span>
          {model.quantization && (
            <span
              className="inline-flex items-center gap-1 px-2 py-1 text-[10px] font-medium rounded-md"
              style={{
                backgroundColor: 'color-mix(in srgb, var(--color-mauve) 15%, transparent)',
                color: 'var(--color-mauve)',
              }}
            >
              {model.quantization}
            </span>
          )}
          {model.parameters && (
            <span
              className="inline-flex items-center gap-1 px-2 py-1 text-[10px] font-medium rounded-md"
              style={{
                backgroundColor: 'color-mix(in srgb, var(--color-blue) 15%, transparent)',
                color: 'var(--color-blue)',
              }}
            >
              {model.parameters}
            </span>
          )}
          <span
            className="inline-flex items-center gap-1 px-2 py-1 text-[10px] font-medium rounded-md"
            style={{
              backgroundColor: model.commercial_use
                ? 'color-mix(in srgb, var(--color-success) 15%, transparent)'
                : 'color-mix(in srgb, var(--color-warning) 15%, transparent)',
              color: model.commercial_use ? 'var(--color-success)' : 'var(--color-warning)',
            }}
          >
            <Scale className="w-3 h-3" />
            {model.commercial_use ? 'Commercial' : 'Non-commercial'}
          </span>
        </div>

        {/* Download progress or action */}
        {activeDownload && activeDownload.status === 'downloading' ? (
          <div className="space-y-2">
            <div className="flex items-center justify-between text-[10px]" style={{ color: 'var(--color-text-muted)' }}>
              <span className="font-semibold" style={{ color: 'var(--color-accent)' }}>{activeDownload.percentage}%</span>
              <span>{formatBytes(activeDownload.bytes_downloaded)} / {formatBytes(activeDownload.total_bytes)}</span>
              <div className="flex items-center gap-1">
                <Clock className="w-3 h-3" />
                <span>{formatETA(bytesRemaining, activeDownload.speed_bps)}</span>
              </div>
              <span className="font-semibold">{formatSpeed(activeDownload.speed_bps)}</span>
            </div>
            <div className="flex items-center gap-2">
              <div className="flex-1 h-2 rounded-full overflow-hidden" style={{ backgroundColor: 'var(--color-surface-0)' }}>
                <div
                  className="h-full rounded-full transition-all duration-500 ease-out relative overflow-hidden"
                  style={{
                    width: `${activeDownload.percentage}%`,
                    background: 'linear-gradient(90deg, var(--color-accent), color-mix(in srgb, var(--color-accent) 80%, white))',
                  }}
                >
                  {/* Shimmer effect */}
                  <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/30 to-transparent animate-shimmer" />
                </div>
              </div>
              <button
                onClick={onCancel}
                className="p-1.5 rounded-lg transition-colors hover:bg-[var(--color-error)]/20"
                style={{ color: 'var(--color-error)' }}
                title="Cancel download"
              >
                <XCircle className="w-4 h-4" />
              </button>
            </div>
          </div>
        ) : activeDownload && (activeDownload.status === 'pending') ? (
          <div className="flex items-center gap-2">
            <Loader2 className="w-4 h-4 animate-spin" style={{ color: 'var(--color-accent)' }} />
            <span className="text-[11px]" style={{ color: 'var(--color-text-muted)' }}>Starting download...</span>
          </div>
        ) : (
          <button
            onClick={onDownload}
            disabled={isInstalled || isDownloading}
            className={cn(
              'w-full py-2 rounded-lg text-[11px] font-semibold flex items-center justify-center gap-2 transition-all duration-200',
              isInstalled
                ? 'cursor-not-allowed opacity-60'
                : 'hover:brightness-110'
            )}
            style={{
              backgroundColor: isInstalled
                ? 'color-mix(in srgb, var(--color-success) 20%, transparent)'
                : 'var(--color-accent)',
              color: isInstalled ? 'var(--color-success)' : 'var(--color-base)',
              boxShadow: isInstalled ? 'none' : '0 4px 12px color-mix(in srgb, var(--color-accent) 30%, transparent)',
            }}
          >
            {isDownloading ? (
              <>
                <Loader2 className="w-3.5 h-3.5 animate-spin" />
                Starting...
              </>
            ) : isInstalled ? (
              <>
                <CheckCircle className="w-3.5 h-3.5" />
                Installed
              </>
            ) : (
              <>
                <Download className="w-3.5 h-3.5" />
                Download
              </>
            )}
          </button>
        )}

        {/* Note */}
        {model.note && (
          <p className="mt-2 text-[10px] italic" style={{ color: 'var(--color-text-muted)' }}>
            {model.note}
          </p>
        )}
      </div>
    </div>
  );
}

export function ModelManager() {
  const modalRef = useRef<HTMLDivElement>(null);
  const [isVisible, setIsVisible] = useState(false);
  const [shouldShow, setShouldShow] = useState(false);
  const [isAnimating, setIsAnimating] = useState(false);
  const [downloadingIds, setDownloadingIds] = useState<Set<string>>(new Set());

  const {
    isModalOpen,
    selectedCategory,
    searchTerm,
    registryModels,
    registryLoading,
    registryError,
    installedModels,
    activeDownloads,
    closeModal,
    setSelectedCategory,
    setSearchTerm,
    getDownloadByModelId,
  } = useDownloadStore();

  const { startDownload, cancelDownload } = useDownloadChannel();

  // Animation handling
  useEffect(() => {
    if (isModalOpen && !isVisible) {
      setIsVisible(true);
      setIsAnimating(true);
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          setShouldShow(true);
          setTimeout(() => setIsAnimating(false), 300);
        });
      });
    }
  }, [isModalOpen, isVisible]);

  const handleClose = () => {
    if (isAnimating) return;
    setIsAnimating(true);
    setShouldShow(false);
    setTimeout(() => {
      setIsVisible(false);
      setIsAnimating(false);
      closeModal();
    }, 200);
  };

  // Escape key
  useEffect(() => {
    if (!isVisible || isAnimating) return;
    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === 'Escape') handleClose();
    };
    document.addEventListener('keydown', handleEscape);
    return () => document.removeEventListener('keydown', handleEscape);
  }, [isVisible, isAnimating, handleClose]);

  // Click outside
  useEffect(() => {
    if (!isVisible || isAnimating) return;
    const handleClickOutside = (e: MouseEvent) => {
      if (modalRef.current && !modalRef.current.contains(e.target as Node)) {
        handleClose();
      }
    };
    const timer = setTimeout(() => {
      document.addEventListener('mousedown', handleClickOutside);
    }, 0);
    return () => {
      clearTimeout(timer);
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [isVisible, isAnimating, handleClose]);

  const filteredModels = useMemo(() => {
    const categoryModels = registryModels[selectedCategory] || [];
    if (!searchTerm) return categoryModels;

    const term = searchTerm.toLowerCase();
    return categoryModels.filter(
      (model) =>
        model.name.toLowerCase().includes(term) ||
        model.description.toLowerCase().includes(term) ||
        model.tags.some((tag) => tag.toLowerCase().includes(term))
    );
  }, [registryModels, selectedCategory, searchTerm]);

  const handleDownload = async (modelId: string) => {
    setDownloadingIds((prev) => new Set(prev).add(modelId));
    try {
      await startDownload(modelId);
    } catch (error) {
      console.error('Failed to start download:', error);
    } finally {
      setDownloadingIds((prev) => {
        const next = new Set(prev);
        next.delete(modelId);
        return next;
      });
    }
  };

  const handleCancel = async (downloadId: string) => {
    try {
      await cancelDownload(downloadId);
    } catch (error) {
      console.error('Failed to cancel download:', error);
    }
  };

  const activeDownloadsList = Object.values(activeDownloads).filter(
    (dl) => dl.status === 'downloading' || dl.status === 'pending'
  );

  const currentCategory = CATEGORIES.find((c) => c.id === selectedCategory);
  const installedInCategory = filteredModels.filter((m) => {
    const filename = m._filename;
    return filename ? installedModels.has(filename) : installedModels.has(m.name) || installedModels.has(m.id);
  }).length;

  if (!isVisible) return null;

  return (
    <div
      className={cn(
        'fixed inset-0 z-[200] flex items-center justify-center transition-opacity duration-200 ease-out',
        shouldShow ? 'opacity-100' : 'opacity-0'
      )}
      style={{ backgroundColor: 'rgba(0, 0, 0, 0.7)', backdropFilter: 'blur(8px)' }}
    >
      <div
        ref={modalRef}
        className={cn(
          'w-full max-w-[1000px] h-[750px] rounded-2xl overflow-hidden flex backdrop-blur-xl transition-all duration-300 ease-out',
          shouldShow ? 'opacity-100 scale-100 translate-y-0' : 'opacity-0 scale-95 translate-y-4'
        )}
        style={{
          background: 'color-mix(in srgb, var(--color-surface-0) 90%, transparent)',
          boxShadow: '0 32px 100px rgba(0, 0, 0, 0.6), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
        }}
      >
        {/* Sidebar */}
        <div
          className="w-52 flex-shrink-0 p-4 flex flex-col"
          style={{
            background: 'linear-gradient(180deg, color-mix(in srgb, var(--color-crust) 80%, transparent), color-mix(in srgb, var(--color-mantle) 60%, transparent))',
          }}
        >
          <div className="flex items-center gap-2 mb-5 px-2">
            <div
              className="p-2 rounded-xl"
              style={{
                background: 'linear-gradient(135deg, var(--color-accent), color-mix(in srgb, var(--color-accent) 70%, var(--color-mauve)))',
              }}
            >
              <Box className="w-4 h-4" style={{ color: 'var(--color-base)' }} />
            </div>
            <h2 className="text-[14px] font-bold" style={{ color: 'var(--color-text)' }}>
              Models
            </h2>
          </div>

          {/* Search */}
          <div className="relative mb-4">
            <Search
              className="absolute left-3 top-1/2 -translate-y-1/2 w-3.5 h-3.5"
              style={{ color: 'var(--color-text-muted)' }}
            />
            <input
              type="text"
              placeholder="Search models..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full pl-8 pr-3 py-2 text-[11px] rounded-lg border-none focus:outline-none focus:ring-2 transition-all"
              style={{
                background: 'color-mix(in srgb, var(--color-surface-1) 60%, transparent)',
                color: 'var(--color-text)',
                '--tw-ring-color': 'var(--color-accent)',
              } as React.CSSProperties}
            />
          </div>

          {/* Categories */}
          <nav className="flex-1 space-y-1">
            {CATEGORIES.map((category) => {
              const count = registryModels[category.id]?.length || 0;
              const isSelected = selectedCategory === category.id;
              return (
                <button
                  key={category.id}
                  onClick={() => setSelectedCategory(category.id)}
                  className={cn(
                    'w-full flex items-center gap-2.5 px-3 py-2 rounded-lg text-[11px] font-medium transition-all duration-150 cursor-pointer',
                    isSelected ? '' : 'hover:bg-white/5'
                  )}
                  style={{
                    color: isSelected ? 'var(--color-text)' : 'var(--color-text-muted)',
                    background: isSelected
                      ? 'linear-gradient(90deg, color-mix(in srgb, var(--color-accent) 25%, transparent), transparent)'
                      : 'transparent',
                    borderLeft: isSelected ? '2px solid var(--color-accent)' : '2px solid transparent',
                  }}
                >
                  <span style={{ color: isSelected ? 'var(--color-accent)' : 'var(--color-text-muted)' }}>
                    {category.icon}
                  </span>
                  <span className="flex-1 text-left">{category.label}</span>
                  {count > 0 && (
                    <span
                      className="text-[9px] px-1.5 py-0.5 rounded-full font-semibold"
                      style={{
                        backgroundColor: isSelected ? 'var(--color-accent)' : 'var(--color-surface-1)',
                        color: isSelected ? 'var(--color-base)' : 'var(--color-text-muted)',
                      }}
                    >
                      {count}
                    </span>
                  )}
                </button>
              );
            })}
          </nav>

          {/* Active Downloads */}
          {activeDownloadsList.length > 0 && (
            <div className="mt-4 pt-4">
              <div className="flex items-center justify-between mb-2 px-2">
                <p
                  className="text-[10px] font-semibold uppercase tracking-wider"
                  style={{ color: 'var(--color-text-muted)' }}
                >
                  Downloads
                </p>
                <span
                  className="text-[9px] px-1.5 py-0.5 rounded-full font-semibold"
                  style={{
                    backgroundColor: 'var(--color-accent)',
                    color: 'var(--color-base)',
                  }}
                >
                  {activeDownloadsList.length}
                </span>
              </div>
              <div className="space-y-1.5 max-h-40 overflow-y-auto">
                {activeDownloadsList.map((dl) => (
                  <DownloadProgress
                    key={dl.download_id}
                    download={dl}
                    onCancel={() => handleCancel(dl.download_id)}
                    compact
                  />
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Content */}
        <div className="flex-1 flex flex-col min-w-0">
          {/* Header */}
          <div
            className="flex items-center justify-between px-6 py-4"
            style={{ backgroundColor: 'color-mix(in srgb, var(--color-surface-0) 30%, transparent)' }}
          >
            <div>
              <div className="flex items-center gap-3">
                <h3 className="text-[18px] font-bold" style={{ color: 'var(--color-text)' }}>
                  {currentCategory?.label}
                </h3>
                <span
                  className="text-[10px] px-2 py-0.5 rounded-full"
                  style={{
                    backgroundColor: 'color-mix(in srgb, var(--color-success) 15%, transparent)',
                    color: 'var(--color-success)',
                  }}
                >
                  {installedInCategory} installed
                </span>
              </div>
              <p className="text-[11px] mt-0.5" style={{ color: 'var(--color-text-muted)' }}>
                {currentCategory?.description}
              </p>
            </div>
            <button
              onClick={handleClose}
              className="p-2 rounded-xl transition-colors cursor-pointer hover:bg-white/5"
              style={{ color: 'var(--color-text-muted)' }}
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Model grid */}
          <div className="flex-1 overflow-y-auto p-6">
            {registryLoading ? (
              <div className="flex flex-col items-center justify-center h-48 gap-3">
                <Loader2 className="w-6 h-6 animate-spin" style={{ color: 'var(--color-accent)' }} />
                <span className="text-[12px]" style={{ color: 'var(--color-text-muted)' }}>
                  Loading models...
                </span>
              </div>
            ) : registryError ? (
              <div
                className="flex flex-col items-center justify-center h-48 p-6 rounded-xl"
                style={{ backgroundColor: 'color-mix(in srgb, var(--color-error) 10%, transparent)' }}
              >
                <AlertCircle className="w-8 h-8 mb-3" style={{ color: 'var(--color-error)' }} />
                <p className="text-[13px] font-medium mb-1" style={{ color: 'var(--color-error)' }}>
                  Failed to load registry
                </p>
                <p className="text-[11px]" style={{ color: 'var(--color-text-muted)' }}>
                  {registryError}
                </p>
              </div>
            ) : filteredModels.length === 0 ? (
              <div className="flex flex-col items-center justify-center h-48 gap-3">
                <Search className="w-8 h-8" style={{ color: 'var(--color-text-muted)' }} />
                <p className="text-[12px]" style={{ color: 'var(--color-text-muted)' }}>
                  {searchTerm ? 'No models found for your search' : 'No models in this category'}
                </p>
              </div>
            ) : (
              <div className="grid grid-cols-2 gap-4">
                {filteredModels.map((model) => {
                  const activeDownload = getDownloadByModelId(model.id);
                  // Check if installed by matching filename from download_url
                  const isInstalled = model._filename
                    ? installedModels.has(model._filename)
                    : installedModels.has(model.name) || installedModels.has(model.id);
                  return (
                    <ModelCard
                      key={model.id}
                      model={model}
                      isInstalled={isInstalled}
                      isDownloading={downloadingIds.has(model.id)}
                      activeDownload={activeDownload}
                      onDownload={() => handleDownload(model.id)}
                      onCancel={() => activeDownload && handleCancel(activeDownload.download_id)}
                    />
                  );
                })}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Shimmer animation style */}
      <style>{`
        @keyframes shimmer {
          0% { transform: translateX(-100%); }
          100% { transform: translateX(100%); }
        }
        .animate-shimmer {
          animation: shimmer 1.5s infinite;
        }
      `}</style>
    </div>
  );
}
