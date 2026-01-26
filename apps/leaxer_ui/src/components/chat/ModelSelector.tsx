import { memo, useState, useEffect, useRef } from 'react';
import { ChevronDown, Cpu, Check, Loader2 } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useChatStore } from '@/stores/chatStore';
import { useSettingsStore } from '@/stores/settingsStore';
import type { ModelStatus } from '@/types/chat';

interface LLMModel {
  name: string;
  path: string;
  size?: string;
}

interface ModelSelectorProps {
  className?: string;
  onModelLoad?: (model: string) => void;
}

export const ModelSelector = memo(({ className, onModelLoad }: ModelSelectorProps) => {
  const [isOpen, setIsOpen] = useState(false);
  const [models, setModels] = useState<LLMModel[]>([]);
  const [loading, setLoading] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  const selectedModel = useChatStore((s) => s.selectedModel);
  const setSelectedModel = useChatStore((s) => s.setSelectedModel);
  const modelStatus = useChatStore((s) => s.modelStatus);
  const getApiBaseUrl = useSettingsStore((s) => s.getApiBaseUrl);

  // Fetch available LLM models
  useEffect(() => {
    const fetchModels = async () => {
      setLoading(true);
      try {
        const apiBaseUrl = getApiBaseUrl();
        const response = await fetch(`${apiBaseUrl}/api/models/llms`);
        if (response.ok) {
          const data = await response.json();
          // Transform to our format
          const llmModels: LLMModel[] = (data.models || []).map((m: { name: string; path: string; size?: number }) => ({
            name: m.name,
            path: m.path,
            size: m.size ? formatFileSize(m.size) : undefined,
          }));
          setModels(llmModels);
        }
      } catch (err) {
        console.error('Failed to fetch LLM models:', err);
      } finally {
        setLoading(false);
      }
    };

    fetchModels();
  }, [getApiBaseUrl]);

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const handleSelect = (model: LLMModel) => {
    setSelectedModel(model.path);
    setIsOpen(false);
    onModelLoad?.(model.path);
  };

  const selectedModelInfo = models.find((m) => m.path === selectedModel);
  const displayName = selectedModelInfo?.name || 'Select Model';

  const statusIcon = getStatusIcon(modelStatus);

  return (
    <div ref={dropdownRef} className={cn('relative', className)}>
      <button
        onClick={() => setIsOpen(!isOpen)}
        className={cn(
          'flex items-center gap-2 px-4 py-2 rounded-full text-sm transition-colors min-w-[200px]'
        )}
        style={{
          backgroundColor: 'var(--color-surface-1)',
          color: selectedModel ? 'var(--color-text)' : 'var(--color-text-secondary)',
        }}
      >
        {statusIcon}
        <span className="flex-1 text-left truncate">{displayName}</span>
        <ChevronDown
          className={cn('w-4 h-4 transition-transform', isOpen && 'rotate-180')}
          style={{ color: 'var(--color-text-secondary)' }}
        />
      </button>

      {isOpen && (
        <div
          className="absolute top-full left-1/2 -translate-x-1/2 mt-2 py-1.5 rounded-xl shadow-lg z-50 max-h-64 overflow-y-auto min-w-[240px] backdrop-blur-xl"
          style={{
            background: 'color-mix(in srgb, var(--color-surface-1) 95%, transparent)',
            boxShadow: '0 8px 32px rgba(0, 0, 0, 0.2), inset 0 0 0 1px var(--color-border)',
          }}
        >
          {loading ? (
            <div
              className="flex items-center justify-center gap-2 px-3 py-4 text-xs"
              style={{ color: 'var(--color-text-secondary)' }}
            >
              <Loader2 className="w-4 h-4 animate-spin" />
              Loading models...
            </div>
          ) : models.length === 0 ? (
            <div
              className="px-3 py-4 text-xs text-center"
              style={{ color: 'var(--color-text-secondary)' }}
            >
              No LLM models found.
              <br />
              <span className="opacity-70">
                Add .gguf files to models/llm/
              </span>
            </div>
          ) : (
            models.map((model) => (
              <button
                key={model.path}
                onClick={() => handleSelect(model)}
                className={cn(
                  'flex items-center gap-2 w-[calc(100%-12px)] mx-1.5 px-3 py-1.5 text-xs text-left rounded-lg transition-colors',
                  'hover:bg-[var(--color-surface-2)]'
                )}
                style={{
                  color: 'var(--color-text)',
                }}
              >
                <Cpu
                  className="w-4 h-4 flex-shrink-0"
                  style={{ color: 'var(--color-text-secondary)' }}
                />
                <div className="flex-1 min-w-0">
                  <div className="truncate">{model.name}</div>
                  {model.size && (
                    <div
                      className="text-[11px]"
                      style={{ color: 'var(--color-text-secondary)' }}
                    >
                      {model.size}
                    </div>
                  )}
                </div>
                {model.path === selectedModel && (
                  <Check
                    className="w-4 h-4 flex-shrink-0"
                    style={{ color: 'var(--color-accent)' }}
                  />
                )}
              </button>
            ))
          )}
        </div>
      )}
    </div>
  );
});

ModelSelector.displayName = 'ModelSelector';

function getStatusIcon(status: ModelStatus) {
  switch (status) {
    case 'loading':
      return (
        <Loader2
          className="w-4 h-4 animate-spin flex-shrink-0"
          style={{ color: 'var(--color-yellow)' }}
        />
      );
    case 'ready':
      return (
        <div
          className="w-2 h-2 rounded-full flex-shrink-0"
          style={{ backgroundColor: 'var(--color-green)' }}
        />
      );
    case 'error':
      return (
        <div
          className="w-2 h-2 rounded-full flex-shrink-0"
          style={{ backgroundColor: 'var(--color-red)' }}
        />
      );
    default:
      return (
        <Cpu
          className="w-4 h-4 flex-shrink-0"
          style={{ color: 'var(--color-text-muted)' }}
        />
      );
  }
}

function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}
