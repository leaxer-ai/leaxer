import { memo, useState, useEffect, useRef, useCallback } from 'react';
import { ChevronDown, Plus, Cpu, Check, Loader2, WifiOff } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useChatStore } from '@/stores/chatStore';
import { useSettingsStore } from '@/stores/settingsStore';
import type { ModelStatus } from '@/types/chat';

interface LLMModel {
  name: string;
  path: string;
  size?: string;
}

interface ChatControlsPillProps {
  onModelLoad?: (model: string) => void;
  onNewChat?: () => void;
}

export const ChatControlsPill = memo(({ onModelLoad, onNewChat }: ChatControlsPillProps) => {
  const [isOpen, setIsOpen] = useState(false);
  const [models, setModels] = useState<LLMModel[]>([]);
  const [loading, setLoading] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  const selectedModel = useChatStore((s) => s.selectedModel);
  const setSelectedModel = useChatStore((s) => s.setSelectedModel);
  const modelStatus = useChatStore((s) => s.modelStatus);
  const isConnected = useChatStore((s) => s.isConnected);
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
          const llmModels: LLMModel[] = (data.models || []).map((m: { name: string; path: string; size_bytes?: number; size_human?: string }) => ({
            name: m.name,
            path: m.path,
            size: m.size_human || (m.size_bytes ? formatFileSize(m.size_bytes) : undefined),
          }));
          setModels(llmModels);
        }
      } catch {
        // Silently fail - models will show as empty
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

  const handleSelect = useCallback((model: LLMModel) => {
    setSelectedModel(model.path);
    setIsOpen(false);
    onModelLoad?.(model.path);
  }, [setSelectedModel, onModelLoad]);

  const handleNewChat = useCallback(() => {
    onNewChat?.();
  }, [onNewChat]);

  const selectedModelInfo = models.find((m) => m.path === selectedModel);
  const displayName = selectedModelInfo?.name || 'Select Model';
  const statusIcon = getStatusIcon(modelStatus, isConnected);
  const statusText = getStatusText(modelStatus, isConnected, selectedModel);

  return (
    <div
      ref={dropdownRef}
      className="fixed top-4 right-4 z-50 flex items-center gap-2"
    >
      {/* New Chat button */}
      <button
        onClick={handleNewChat}
        className="flex items-center justify-center w-[44px] h-[44px] rounded-full backdrop-blur-xl transition-colors hover:bg-white/15"
        style={{
          background: 'rgba(255, 255, 255, 0.08)',
          boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
        }}
        title="New Chat"
      >
        <Plus className="w-5 h-5" style={{ color: 'var(--color-text-secondary)' }} />
      </button>

      {/* Model selector pill */}
      <div className="relative">
        <button
          onClick={() => setIsOpen(!isOpen)}
          className={cn(
            'flex items-center gap-2 px-4 h-[44px] rounded-full backdrop-blur-xl transition-colors',
            isOpen ? 'bg-white/15' : 'hover:bg-white/10'
          )}
          style={{
            background: 'rgba(255, 255, 255, 0.08)',
            boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
          }}
          title={statusText}
        >
          {statusIcon}
          <span
            className="text-xs font-medium max-w-[140px] truncate"
            style={{ color: selectedModel ? 'var(--color-text)' : 'var(--color-text-secondary)' }}
          >
            {displayName}
          </span>
          <ChevronDown
            className={cn('w-4 h-4 transition-transform', isOpen && 'rotate-180')}
            style={{ color: 'var(--color-text-secondary)' }}
          />
        </button>

        {/* Dropdown */}
        {isOpen && (
          <div
            className="absolute top-full right-0 mt-2 py-1.5 rounded-xl min-w-[220px] max-h-64 overflow-y-auto backdrop-blur-xl"
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
                <span className="opacity-70">Add .gguf files to models/llm/</span>
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
                  style={{ color: 'var(--color-text)' }}
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
    </div>
  );
});

ChatControlsPill.displayName = 'ChatControlsPill';

function getStatusIcon(status: ModelStatus, isConnected: boolean) {
  // Not connected - show disconnected icon
  if (!isConnected) {
    return (
      <WifiOff
        className="w-4 h-4 flex-shrink-0"
        style={{ color: 'var(--color-red)' }}
      />
    );
  }

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
          style={{ color: 'var(--color-text-secondary)' }}
        />
      );
  }
}

function getStatusText(status: ModelStatus, isConnected: boolean, selectedModel: string | null): string {
  if (!isConnected) {
    return 'Disconnected - Cannot connect to chat server';
  }

  switch (status) {
    case 'loading':
      return 'Loading model...';
    case 'ready':
      return `Model ready: ${selectedModel ? selectedModel.split('/').pop() : 'Unknown'}`;
    case 'error':
      return 'Error loading model';
    default:
      return selectedModel ? 'Click to load model' : 'Select a model to start chatting';
  }
}

function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}
