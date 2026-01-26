import { useEffect, useRef, useState } from 'react';
import { X, Server, Sparkles, Bell, Volume2, Play, Cpu, Zap, Info, RotateCcw, Wifi, AlertTriangle, Globe } from 'lucide-react';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Switch } from '@/components/ui/switch';
import { Slider } from '@/components/ui/slider';
import {
  useSettingsStore,
  getAvailableBackends,
  detectPlatform,
  type ComputeBackend,
} from '@/stores/settingsStore';
import { AVAILABLE_SOUNDS, type SoundName, playSound } from '@/lib/sounds';
import { useChatStore } from '@/stores/chatStore';
import { cn } from '@/lib/utils';

// Search provider type
interface SearchProvider {
  id: string;
  name: string;
  description: string;
}

interface SettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
}

type SettingsCategory = 'system' | 'personalization' | 'notification' | 'about';

const categories: { id: SettingsCategory; label: string; icon: React.ReactNode }[] = [
  { id: 'system', label: 'System', icon: <Server className="w-4 h-4" /> },
  { id: 'personalization', label: 'Personalization', icon: <Sparkles className="w-4 h-4" /> },
  { id: 'notification', label: 'Notification', icon: <Bell className="w-4 h-4" /> },
  { id: 'about', label: 'About', icon: <Info className="w-4 h-4" /> },
];

const APP_VERSION = '0.1.0';
const CURRENT_YEAR = new Date().getFullYear();

interface OSSLibrary {
  name: string;
  description: string;
  license: string;
  url: string;
}

const ossLibraries: OSSLibrary[] = [
  // Backend / Runtime
  { name: 'Elixir', description: 'Backend language', license: 'Apache-2.0', url: 'https://github.com/elixir-lang/elixir' },
  { name: 'Phoenix Framework', description: 'Web framework', license: 'MIT', url: 'https://github.com/phoenixframework/phoenix' },
  { name: 'Bandit', description: 'HTTP server', license: 'MIT', url: 'https://github.com/mtrudel/bandit' },
  { name: 'Req', description: 'HTTP client', license: 'Apache-2.0', url: 'https://github.com/wojtekmach/req' },
  { name: 'Floki', description: 'HTML parser', license: 'MIT', url: 'https://github.com/philss/floki' },
  { name: 'Jason', description: 'JSON parser', license: 'Apache-2.0', url: 'https://github.com/michalmuskala/jason' },
  // AI Inference
  { name: 'llama.cpp', description: 'LLM inference', license: 'MIT', url: 'https://github.com/ggerganov/llama.cpp' },
  { name: 'stable-diffusion.cpp', description: 'Image generation', license: 'MIT', url: 'https://github.com/leejet/stable-diffusion.cpp' },
  { name: 'GroundingDINO', description: 'Object detection', license: 'Apache-2.0', url: 'https://github.com/IDEA-Research/GroundingDINO' },
  { name: 'Segment Anything', description: 'Image segmentation', license: 'Apache-2.0', url: 'https://github.com/facebookresearch/segment-anything' },
  { name: 'Real-ESRGAN', description: 'Image upscaling', license: 'BSD-3-Clause', url: 'https://github.com/xinntao/Real-ESRGAN' },
  // Frontend
  { name: 'React', description: 'UI framework', license: 'MIT', url: 'https://github.com/facebook/react' },
  { name: 'React Flow', description: 'Node graph editor', license: 'MIT', url: 'https://github.com/xyflow/xyflow' },
  { name: 'Zustand', description: 'State management', license: 'MIT', url: 'https://github.com/pmndrs/zustand' },
  { name: 'Radix UI', description: 'UI primitives', license: 'MIT', url: 'https://github.com/radix-ui/primitives' },
  { name: 'TanStack Virtual', description: 'Virtualized lists', license: 'MIT', url: 'https://github.com/TanStack/virtual' },
  { name: 'react-markdown', description: 'Markdown renderer', license: 'MIT', url: 'https://github.com/remarkjs/react-markdown' },
  { name: 'PDF.js', description: 'PDF rendering', license: 'Apache-2.0', url: 'https://github.com/nicolo-ribaudo/nicolo-ribaudo.pdfjs-dist-mirror' },
  // Build / Styling
  { name: 'Tailwind CSS', description: 'CSS framework', license: 'MIT', url: 'https://github.com/tailwindlabs/tailwindcss' },
  { name: 'Vite', description: 'Build tool', license: 'MIT', url: 'https://github.com/vitejs/vite' },
  { name: 'Lucide', description: 'Icons', license: 'ISC', url: 'https://github.com/lucide-icons/lucide' },
  // Desktop
  { name: 'Tauri', description: 'Desktop framework', license: 'MIT', url: 'https://github.com/tauri-apps/tauri' },
];

interface SettingRowProps {
  label: string;
  description?: string;
  children: React.ReactNode;
  vertical?: boolean;
}

function SettingRow({ label, description, children, vertical = false }: SettingRowProps) {
  return (
    <div className={cn(
      "py-3",
      vertical ? "space-y-3" : "flex items-start justify-between gap-4"
    )}>
      <div className={vertical ? "" : "flex-1"}>
        <Label className="text-[13px] font-medium" style={{ color: 'var(--color-text)' }}>
          {label}
        </Label>
        {description && (
          <p className="text-[11px] mt-0.5" style={{ color: 'var(--color-text-muted)' }}>
            {description}
          </p>
        )}
      </div>
      <div className={cn("flex-shrink-0", vertical && "w-full")}>{children}</div>
    </div>
  );
}

function SettingGroup({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mb-6">
      <h3
        className="text-[11px] font-medium uppercase tracking-wider mb-3"
        style={{ color: 'var(--color-text-muted)' }}
      >
        {title}
      </h3>
      <div className="space-y-1">{children}</div>
    </div>
  );
}

function SoundSelector({
  value,
  onChange,
  disabled,
}: {
  value: SoundName;
  onChange: (sound: SoundName) => void;
  disabled: boolean;
}) {
  return (
    <div className="flex items-center gap-2">
      <select
        className={cn(
          "h-8 px-3 text-[12px] rounded-lg cursor-pointer transition-colors",
          "focus:outline-none",
          disabled && "opacity-50 cursor-not-allowed"
        )}
        style={{
          border: 'none',
          background: 'color-mix(in srgb, var(--color-surface-1) 50%, transparent)',
          color: 'var(--color-text)',
        }}
        value={value}
        onChange={(e) => onChange(e.target.value as SoundName)}
        disabled={disabled}
      >
        {AVAILABLE_SOUNDS.map((sound) => (
          <option key={sound} value={sound} style={{ background: 'var(--color-surface-0)' }}>
            {sound}
          </option>
        ))}
      </select>
      <button
        onClick={() => playSound(value)}
        disabled={disabled}
        className={cn(
          "p-2 rounded-lg transition-colors cursor-pointer",
          disabled && "opacity-50 cursor-not-allowed"
        )}
        style={{ color: 'var(--color-text-muted)' }}
        title="Preview"
      >
        <Play className="w-3.5 h-3.5" />
      </button>
    </div>
  );
}

export function SettingsModal({ isOpen, onClose }: SettingsModalProps) {
  const modalRef = useRef<HTMLDivElement>(null);
  const [activeCategory, setActiveCategory] = useState<SettingsCategory>('system');
  const [isVisible, setIsVisible] = useState(false);
  const [isAnimating, setIsAnimating] = useState(false);
  const [shouldShow, setShouldShow] = useState(false);

  // Handle open animation
  useEffect(() => {
    if (isOpen && !isVisible) {
      setIsVisible(true);
      setIsAnimating(true);
      // Start in closed state, then animate open on next frame
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          setShouldShow(true);
          setTimeout(() => setIsAnimating(false), 300);
        });
      });
    }
  }, [isOpen, isVisible]);

  const handleClose = () => {
    if (isAnimating) return;
    setIsAnimating(true);
    setShouldShow(false);
    setTimeout(() => {
      setIsVisible(false);
      setIsAnimating(false);
      onClose();
    }, 200);
  };

  const {
    backendUrl,
    setBackendUrl,
    computeBackend,
    setComputeBackend,
    showGrid,
    setShowGrid,
    snapToGrid,
    setSnapToGrid,
    gridSize,
    setGridSize,
    edgeType,
    setEdgeType,
    showMinimap,
    setShowMinimap,
    theme,
    setTheme,
    soundsEnabled,
    setSoundsEnabled,
    soundVolume,
    setSoundVolume,
    soundStart,
    setSoundStart,
    soundComplete,
    setSoundComplete,
    soundError,
    setSoundError,
    soundStop,
    setSoundStop,
    soundSuccess,
    setSoundSuccess,
    soundReturn,
    setSoundReturn,
    autosaveEnabled,
    setAutosaveEnabled,
    autosaveInterval,
    setAutosaveInterval,
    modelCachingStrategy,
    setModelCachingStrategy,
    useFramelessWindow,
    setUseFramelessWindow,
    networkExposureEnabled,
    networkRestartRequired,
    networkInfo,
    setNetworkExposureEnabled,
    fetchNetworkInfo,
  } = useSettingsStore();

  const [networkLoading, setNetworkLoading] = useState(false);
  const [searchProviders, setSearchProviders] = useState<SearchProvider[]>([
    { id: 'searxng', name: 'SearXNG', description: 'Privacy-respecting meta search (recommended)' },
    { id: 'duckduckgo', name: 'DuckDuckGo', description: 'Privacy-focused search engine' },
    { id: 'brave', name: 'Brave Search', description: 'Independent search engine' },
  ]);

  // Chat store for search settings
  const searchProvider = useChatStore((s) => s.searchProvider);
  const setSearchProvider = useChatStore((s) => s.setSearchProvider);
  const searchMaxResults = useChatStore((s) => s.searchMaxResults);
  const setSearchMaxResults = useChatStore((s) => s.setSearchMaxResults);

  // Fetch search providers from backend
  useEffect(() => {
    if (isOpen) {
      fetch(`${useSettingsStore.getState().getApiBaseUrl()}/api/settings/search-providers`)
        .then((res) => res.json())
        .then((data) => {
          if (data.providers) {
            setSearchProviders(data.providers);
          }
        })
        .catch((err) => console.error('Failed to fetch search providers:', err));
    }
  }, [isOpen]);

  // Fetch network info when modal opens
  useEffect(() => {
    if (isOpen) {
      fetchNetworkInfo();
    }
  }, [isOpen, fetchNetworkInfo]);

  const handleNetworkToggle = async (enabled: boolean) => {
    setNetworkLoading(true);
    try {
      await setNetworkExposureEnabled(enabled);
    } catch (error) {
      console.error('Failed to update network setting:', error);
    } finally {
      setNetworkLoading(false);
    }
  };

  const platform = detectPlatform();
  const availableBackends = getAvailableBackends();

  // Handle escape key
  useEffect(() => {
    if (!isVisible || isAnimating) return;

    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        handleClose();
      }
    };

    document.addEventListener('keydown', handleEscape);
    return () => document.removeEventListener('keydown', handleEscape);
  }, [isVisible, isAnimating]);

  // Handle click outside
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
  }, [isVisible, isAnimating]);

  if (!isVisible) return null;

  const renderContent = () => {
    switch (activeCategory) {
      case 'system':
        return (
          <>
            <SettingGroup title="Connection">
              <SettingRow
                label="Backend URL"
                description="WebSocket server address for the Elixir backend"
              >
                <Input
                  type="text"
                  value={backendUrl}
                  onChange={(e) => setBackendUrl(e.target.value)}
                  className="w-56 h-8 text-[12px] border-none rounded-lg focus:ring-0 focus:outline-none"
                  style={{
                    background: 'color-mix(in srgb, var(--color-surface-1) 50%, transparent)',
                    color: 'var(--color-text)',
                  }}
                  placeholder="ws://localhost:4000/socket"
                />
              </SettingRow>
            </SettingGroup>

            <SettingGroup title="Compute">
              <SettingRow
                label="Hardware Acceleration"
                description={`Select compute backend for ${platform === 'mac' ? 'macOS' : platform === 'windows' ? 'Windows' : 'Linux'}`}
              >
                <select
                  className="h-8 px-3 text-[12px] rounded-lg cursor-pointer transition-colors focus:outline-none"
                  style={{
                    border: 'none',
                    background: 'color-mix(in srgb, var(--color-surface-1) 50%, transparent)',
                    color: 'var(--color-text)',
                  }}
                  value={computeBackend}
                  onChange={(e) => setComputeBackend(e.target.value as ComputeBackend)}
                >
                  {availableBackends.map((backend) => (
                    <option key={backend.value} value={backend.value} style={{ background: 'var(--color-surface-0)' }}>
                      {backend.label}
                    </option>
                  ))}
                </select>
              </SettingRow>

              <div
                className="mt-3 p-3 rounded-xl"
                style={{ backgroundColor: 'color-mix(in srgb, var(--color-surface-1) 30%, transparent)' }}
              >
                <div className="flex items-start gap-3">
                  {computeBackend === 'cpu' ? (
                    <Cpu className="w-4 h-4 mt-0.5" style={{ color: 'var(--color-blue)' }} />
                  ) : (
                    <Zap className="w-4 h-4 mt-0.5" style={{ color: 'var(--color-yellow)' }} />
                  )}
                  <div>
                    <p className="text-[12px]" style={{ color: 'var(--color-text-secondary)' }}>
                      {availableBackends.find((b) => b.value === computeBackend)?.description}
                    </p>
                    {platform === 'mac' && computeBackend === 'metal' && (
                      <p className="text-[11px] mt-1" style={{ color: 'var(--color-text-muted)' }}>
                        Metal may have issues on M4 chips. Use CPU if you experience crashes.
                      </p>
                    )}
                  </div>
                </div>
              </div>
            </SettingGroup>

            <SettingGroup title="Autosave">
              <SettingRow
                label="Enable Autosave"
                description="Automatically save workflows with local file paths"
              >
                <Switch
                  checked={autosaveEnabled}
                  onCheckedChange={setAutosaveEnabled}
                />
              </SettingRow>

              <SettingRow
                label="Interval"
                description="Time between autosaves (in seconds)"
              >
                <Input
                  type="number"
                  value={autosaveInterval}
                  onChange={(e) => setAutosaveInterval(Math.max(10, parseInt(e.target.value) || 60))}
                  min={10}
                  max={600}
                  step={10}
                  disabled={!autosaveEnabled}
                  className="w-24 h-8 text-[12px] border-none rounded-lg text-center focus:ring-0 focus:outline-none"
                  style={{
                    background: 'color-mix(in srgb, var(--color-surface-1) 50%, transparent)',
                    color: 'var(--color-text)',
                    opacity: autosaveEnabled ? 1 : 0.5,
                  }}
                />
              </SettingRow>

              <div
                className="mt-3 p-3 rounded-xl"
                style={{ backgroundColor: 'color-mix(in srgb, var(--color-surface-1) 30%, transparent)' }}
              >
                <p className="text-[11px]" style={{ color: 'var(--color-text-muted)' }}>
                  Autosave only works for workflows that have been saved to a file. In-memory workflows are not autosaved.
                </p>
              </div>
            </SettingGroup>

            <SettingGroup title="Queue Optimization">
              <SettingRow
                label="Model Caching Strategy"
                description="How models stay in VRAM"
              >
                <select
                  className="h-8 px-3 text-[12px] rounded-lg cursor-pointer transition-colors focus:outline-none"
                  style={{
                    border: 'none',
                    background: 'color-mix(in srgb, var(--color-surface-1) 50%, transparent)',
                    color: 'var(--color-text)',
                  }}
                  value={modelCachingStrategy}
                  onChange={(e) => setModelCachingStrategy(e.target.value as 'auto' | 'cli-mode' | 'server-mode')}
                >
                  <option value="auto" style={{ background: 'var(--color-surface-0)' }}>
                    Auto (Recommended)
                  </option>
                  <option value="server-mode" style={{ background: 'var(--color-surface-0)' }}>
                    Server Mode (Keep in VRAM)
                  </option>
                  <option value="cli-mode" style={{ background: 'var(--color-surface-0)' }}>
                    CLI Mode (Reload each job)
                  </option>
                </select>
              </SettingRow>

              <div
                className="mt-3 p-3 rounded-xl"
                style={{ backgroundColor: 'color-mix(in srgb, var(--color-surface-1) 30%, transparent)' }}
              >
                <p className="text-[12px]" style={{ color: 'var(--color-text-secondary)' }}>
                  {modelCachingStrategy === 'auto'
                    ? 'Automatically selects the best strategy. Uses Server Mode when available for maximum speed.'
                    : modelCachingStrategy === 'server-mode'
                    ? 'Keeps models in VRAM between jobs. Much faster for consecutive jobs with the same model.'
                    : 'Reloads the model for each job. More reliable but slower for multiple jobs.'}
                </p>
                {modelCachingStrategy === 'cli-mode' && (
                  <p className="text-[11px] mt-2" style={{ color: 'var(--color-text-muted)' }}>
                    Use this if you experience issues with Server Mode.
                  </p>
                )}
              </div>
            </SettingGroup>

            <SettingGroup title="Network">
              <SettingRow
                label="Allow LAN Access"
                description="Expose Leaxer to other devices on your local network"
              >
                <Switch
                  checked={networkExposureEnabled}
                  onCheckedChange={handleNetworkToggle}
                  disabled={networkLoading}
                />
              </SettingRow>

              {networkExposureEnabled && networkInfo && networkInfo.local_ips.length > 0 && (
                <div
                  className="mt-3 p-3 rounded-xl"
                  style={{ backgroundColor: 'color-mix(in srgb, var(--color-surface-1) 30%, transparent)' }}
                >
                  <div className="flex items-start gap-3">
                    <Wifi className="w-4 h-4 mt-0.5" style={{ color: 'var(--color-green)' }} />
                    <div>
                      <p className="text-[12px] font-medium" style={{ color: 'var(--color-text-secondary)' }}>
                        Access from other devices:
                      </p>
                      <div className="mt-1 space-y-1">
                        {networkInfo.local_ips.map((ip) => (
                          <div key={ip}>
                            <p className="text-[11px]" style={{ color: 'var(--color-text-muted)' }}>Frontend (UI):</p>
                            <p className="text-[12px] font-mono" style={{ color: 'var(--color-text)' }}>
                              http://{ip}:{networkInfo.frontend_port}
                            </p>
                            <p className="text-[11px] mt-1" style={{ color: 'var(--color-text-muted)' }}>Backend URL (set in Settings):</p>
                            <p className="text-[12px] font-mono" style={{ color: 'var(--color-text)' }}>
                              ws://{ip}:{networkInfo.backend_port}/socket
                            </p>
                          </div>
                        ))}
                      </div>
                    </div>
                  </div>
                </div>
              )}

              {networkRestartRequired && (
                <div
                  className="mt-3 p-3 rounded-xl flex items-start gap-3"
                  style={{ backgroundColor: 'color-mix(in srgb, var(--color-yellow) 15%, transparent)' }}
                >
                  <AlertTriangle className="w-4 h-4 mt-0.5 flex-shrink-0" style={{ color: 'var(--color-yellow)' }} />
                  <div>
                    <p className="text-[12px] font-medium" style={{ color: 'var(--color-yellow)' }}>
                      Restart Required
                    </p>
                    <p className="text-[11px] mt-0.5" style={{ color: 'var(--color-text-muted)' }}>
                      The network setting change will take effect after restarting the app.
                    </p>
                  </div>
                </div>
              )}

              {!networkRestartRequired && !networkExposureEnabled && (
                <div
                  className="mt-3 p-3 rounded-xl"
                  style={{ backgroundColor: 'color-mix(in srgb, var(--color-surface-1) 30%, transparent)' }}
                >
                  <p className="text-[11px]" style={{ color: 'var(--color-text-muted)' }}>
                    When enabled, Leaxer's backend API will be accessible from other devices on your local network.
                    For web deployment, this allows accessing the UI from other devices. For the desktop app,
                    other devices can connect to your backend by updating their Backend URL setting.
                  </p>
                </div>
              )}
            </SettingGroup>

            <SettingGroup title="Web Search">
              <SettingRow
                label="Search Provider"
                description="Search engine for the chat internet feature"
              >
                <select
                  className="h-8 px-3 text-[12px] rounded-lg cursor-pointer transition-colors focus:outline-none"
                  style={{
                    border: 'none',
                    background: 'color-mix(in srgb, var(--color-surface-1) 50%, transparent)',
                    color: 'var(--color-text)',
                  }}
                  value={searchProvider}
                  onChange={(e) => setSearchProvider(e.target.value)}
                >
                  {searchProviders.map((provider) => (
                    <option key={provider.id} value={provider.id} style={{ background: 'var(--color-surface-0)' }}>
                      {provider.name}
                    </option>
                  ))}
                </select>
              </SettingRow>

              <SettingRow
                label="Max Results"
                description="Number of web pages to fetch and parse"
              >
                <Input
                  type="number"
                  value={searchMaxResults}
                  onChange={(e) => setSearchMaxResults(Math.max(1, Math.min(10, parseInt(e.target.value) || 3)))}
                  min={1}
                  max={10}
                  step={1}
                  className="w-20 h-8 text-[12px] border-none rounded-lg text-center focus:ring-0 focus:outline-none"
                  style={{
                    background: 'color-mix(in srgb, var(--color-surface-1) 50%, transparent)',
                    color: 'var(--color-text)',
                  }}
                />
              </SettingRow>

              <div
                className="mt-3 p-3 rounded-xl"
                style={{ backgroundColor: 'color-mix(in srgb, var(--color-surface-1) 30%, transparent)' }}
              >
                <div className="flex items-start gap-3">
                  <Globe className="w-4 h-4 mt-0.5" style={{ color: 'var(--color-blue)' }} />
                  <div>
                    <p className="text-[12px]" style={{ color: 'var(--color-text-secondary)' }}>
                      {searchProviders.find((p) => p.id === searchProvider)?.description || 'Select a search provider'}
                    </p>
                    <p className="text-[11px] mt-1" style={{ color: 'var(--color-text-muted)' }}>
                      Web search is used when the internet toggle is enabled in chat. More results provide better context but take longer.
                    </p>
                  </div>
                </div>
              </div>
            </SettingGroup>
          </>
        );

      case 'personalization':
        return (
          <>
            <SettingGroup title="Theme">
              <SettingRow
                label="Color Scheme"
                description="Choose a theme for the interface"
                vertical
              >
                <select
                  className="w-full h-9 px-3 text-[12px] rounded-lg cursor-pointer transition-colors focus:outline-none"
                  style={{
                    border: 'none',
                    background: 'color-mix(in srgb, var(--color-surface-1) 50%, transparent)',
                    color: 'var(--color-text)',
                  }}
                  value={theme}
                  onChange={(e) => setTheme(e.target.value)}
                >
                  <optgroup label="Default" style={{ background: 'var(--color-surface-0)' }}>
                    <option value="leaxer-dark">Lexer Dark</option>
                    <option value="leaxer-light">Lexer Light</option>
                  </optgroup>
                  <optgroup label="Github" style={{ background: 'var(--color-surface-0)' }}>
                    <option value="github-dark">Github Dark</option>
                    <option value="github-light">Github Light</option>
                  </optgroup>
                  <optgroup label="Catppuccin" style={{ background: 'var(--color-surface-0)' }}>
                    <option value="catppuccin-latte">Latte (Light)</option>
                    <option value="catppuccin-frappe">Frappe</option>
                    <option value="catppuccin-macchiato">Macchiato</option>
                    <option value="catppuccin-mocha">Mocha</option>
                  </optgroup>
                  <optgroup label="Popular" style={{ background: 'var(--color-surface-0)' }}>
                    <option value="dracula">Dracula</option>
                    <option value="nord">Nord</option>
                    <option value="tokyo-night">Tokyo Night</option>
                    <option value="one-dark">One Dark</option>
                  </optgroup>
                  <optgroup label="Warm" style={{ background: 'var(--color-surface-0)' }}>
                    <option value="gruvbox">Gruvbox</option>
                    <option value="solarized">Solarized Dark</option>
                    <option value="rose-pine">Rose Pine</option>
                    <option value="everforest">Everforest</option>
                  </optgroup>
                  <optgroup label="Special" style={{ background: 'var(--color-surface-0)' }}>
                    <option value="osaka-jade">Osaka Jade</option>
                  </optgroup>
                </select>
              </SettingRow>
            </SettingGroup>

            <SettingGroup title="Canvas">
              <SettingRow
                label="Show Grid"
                description="Display background grid"
              >
                <Switch
                  checked={showGrid}
                  onCheckedChange={setShowGrid}
                />
              </SettingRow>

              <SettingRow
                label="Snap to Grid"
                description="Align nodes to grid when moving"
              >
                <Switch
                  checked={snapToGrid}
                  onCheckedChange={setSnapToGrid}
                />
              </SettingRow>

              <SettingRow
                label="Grid Size"
                description="Grid spacing in pixels"
              >
                <Input
                  type="number"
                  value={gridSize}
                  onChange={(e) => setGridSize(parseInt(e.target.value) || 10)}
                  min={5}
                  max={50}
                  step={5}
                  className="w-20 h-8 text-[12px] border-none rounded-lg text-center focus:ring-0 focus:outline-none"
                  style={{
                    background: 'color-mix(in srgb, var(--color-surface-1) 50%, transparent)',
                    color: 'var(--color-text)',
                  }}
                />
              </SettingRow>

              <SettingRow
                label="Edge Style"
                description="Connection line appearance"
              >
                <select
                  className="h-8 px-3 text-[12px] rounded-lg cursor-pointer transition-colors focus:outline-none"
                  style={{
                    border: 'none',
                    background: 'color-mix(in srgb, var(--color-surface-1) 50%, transparent)',
                    color: 'var(--color-text)',
                  }}
                  value={edgeType}
                  onChange={(e) => setEdgeType(e.target.value as 'bezier' | 'straight' | 'step' | 'smoothstep')}
                >
                  <option value="bezier" style={{ background: 'var(--color-surface-0)' }}>Bezier</option>
                  <option value="smoothstep" style={{ background: 'var(--color-surface-0)' }}>Smooth Step</option>
                  <option value="step" style={{ background: 'var(--color-surface-0)' }}>Step</option>
                  <option value="straight" style={{ background: 'var(--color-surface-0)' }}>Straight</option>
                </select>
              </SettingRow>

              <SettingRow
                label="Show Minimap"
                description="Display overview minimap in corner"
              >
                <Switch
                  checked={showMinimap}
                  onCheckedChange={setShowMinimap}
                />
              </SettingRow>
            </SettingGroup>

            <SettingGroup title="Window">
              <SettingRow
                label="Custom Title Bar"
                description="Use frameless window with custom controls"
              >
                <Switch
                  checked={useFramelessWindow}
                  onCheckedChange={setUseFramelessWindow}
                />
              </SettingRow>

              <div
                className="mt-3 p-3 rounded-xl flex items-start gap-3"
                style={{ backgroundColor: 'color-mix(in srgb, var(--color-surface-1) 30%, transparent)' }}
              >
                <RotateCcw className="w-4 h-4 mt-0.5 flex-shrink-0" style={{ color: 'var(--color-text-muted)' }} />
                <p className="text-[11px]" style={{ color: 'var(--color-text-muted)' }}>
                  Restart the app to apply window frame changes.
                </p>
              </div>
            </SettingGroup>
          </>
        );

      case 'notification':
        return (
          <>
            <SettingGroup title="Sound Effects">
              <SettingRow
                label="Enable Sounds"
                description="Play audio feedback for events"
              >
                <Switch
                  checked={soundsEnabled}
                  onCheckedChange={setSoundsEnabled}
                />
              </SettingRow>

              <SettingRow
                label="Volume"
                description="Adjust sound volume"
              >
                <div className="flex items-center gap-3 w-40">
                  <Volume2
                    className="w-4 h-4 flex-shrink-0"
                    style={{ color: soundsEnabled ? 'var(--color-text-secondary)' : 'var(--color-text-muted)' }}
                  />
                  <Slider
                    value={soundVolume}
                    onChange={setSoundVolume}
                    min={0}
                    max={1}
                    step={0.1}
                    disabled={!soundsEnabled}
                    className="flex-1"
                  />
                </div>
              </SettingRow>
            </SettingGroup>

            <SettingGroup title="Event Sounds">
              <SettingRow
                label="Start"
                description="When execution begins"
              >
                <SoundSelector
                  value={soundStart}
                  onChange={setSoundStart}
                  disabled={!soundsEnabled}
                />
              </SettingRow>

              <SettingRow
                label="Complete"
                description="When execution finishes"
              >
                <SoundSelector
                  value={soundComplete}
                  onChange={setSoundComplete}
                  disabled={!soundsEnabled}
                />
              </SettingRow>

              <SettingRow
                label="Error"
                description="When an error occurs"
              >
                <SoundSelector
                  value={soundError}
                  onChange={setSoundError}
                  disabled={!soundsEnabled}
                />
              </SettingRow>

              <SettingRow
                label="Stop"
                description="When execution is cancelled"
              >
                <SoundSelector
                  value={soundStop}
                  onChange={setSoundStop}
                  disabled={!soundsEnabled}
                />
              </SettingRow>

              <SettingRow
                label="Success"
                description="When connection is restored"
              >
                <SoundSelector
                  value={soundSuccess}
                  onChange={setSoundSuccess}
                  disabled={!soundsEnabled}
                />
              </SettingRow>

              <SettingRow
                label="Return"
                description="When chat response completes"
              >
                <SoundSelector
                  value={soundReturn}
                  onChange={setSoundReturn}
                  disabled={!soundsEnabled}
                />
              </SettingRow>
            </SettingGroup>
          </>
        );

      case 'about':
        return (
          <>
            <SettingGroup title="Leaxer">
              <p className="text-[13px] leading-relaxed" style={{ color: 'var(--color-text-secondary)' }}>
                Leaxer is an engine for local AI inference, written in Elixir and the BEAM virtual machine.
              </p>
              <p className="text-[12px] mt-3" style={{ color: 'var(--color-text-muted)' }}>
                Leaxer is free and open source software, licensed under Apache 2.0.
              </p>
            </SettingGroup>

            <SettingGroup title="Open Source Licenses">
              <p className="text-[12px] mb-4" style={{ color: 'var(--color-text-muted)' }}>
                Built with these open source projects.
              </p>
              <div className="space-y-3">
                {ossLibraries.map((lib) => (
                  <div key={lib.name} className="flex items-center justify-between">
                    <div>
                      <a
                        href={lib.url}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-[13px] font-medium hover:underline"
                        style={{ color: 'var(--color-text)' }}
                      >
                        {lib.name}
                      </a>
                      <p className="text-[11px]" style={{ color: 'var(--color-text-muted)' }}>
                        {lib.description}
                      </p>
                    </div>
                    <span
                      className="text-[10px]"
                      style={{ color: 'var(--color-text-muted)' }}
                    >
                      {lib.license}
                    </span>
                  </div>
                ))}
              </div>
            </SettingGroup>
          </>
        );
    }
  };

  return (
    <div
      className={cn(
        "fixed inset-0 z-[200] flex items-center justify-center transition-opacity duration-200 ease-out",
        shouldShow ? "opacity-100" : "opacity-0"
      )}
      style={{ backgroundColor: 'rgba(0, 0, 0, 0.6)', backdropFilter: 'blur(4px)' }}
    >
      <div
        ref={modalRef}
        className={cn(
          "w-full max-w-[720px] h-[700px] rounded-2xl overflow-hidden flex backdrop-blur-xl transition-all duration-300 ease-out",
          shouldShow
            ? "opacity-100 scale-100 translate-y-0"
            : "opacity-0 scale-95 translate-y-4"
        )}
        style={{
          background: 'color-mix(in srgb, var(--color-surface-0) 85%, transparent)',
          boxShadow: '0 24px 80px rgba(0, 0, 0, 0.5), inset 0 1px 0 rgba(255, 255, 255, 0.08)',
        }}
      >
        {/* Sidebar */}
        <div
          className="w-56 flex-shrink-0 p-5 flex flex-col"
          style={{
            background: 'color-mix(in srgb, var(--color-crust) 60%, transparent)',
          }}
        >
          <h2
            className="text-[14px] font-semibold mb-6 px-3"
            style={{ color: 'var(--color-text)' }}
          >
            Settings
          </h2>

          <nav className="flex-1 space-y-1">
            {categories.map((category) => (
              <button
                key={category.id}
                onClick={() => setActiveCategory(category.id)}
                className={cn(
                  "w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-[13px] font-medium transition-all duration-150 cursor-pointer",
                  activeCategory === category.id
                    ? ""
                    : "hover:bg-white/5"
                )}
                style={{
                  color: activeCategory === category.id
                    ? 'var(--color-text)'
                    : 'var(--color-text-muted)',
                  background: activeCategory === category.id
                    ? 'color-mix(in srgb, var(--color-accent) 20%, transparent)'
                    : 'transparent',
                }}
              >
                {category.icon}
                {category.label}
              </button>
            ))}
          </nav>

          <div className="pt-4 mt-auto px-3 space-y-0.5">
            <p className="text-[11px] font-medium" style={{ color: 'var(--color-text-secondary)' }}>
              Leaxer {APP_VERSION}
            </p>
            <p className="text-[10px]" style={{ color: 'var(--color-text-muted)' }}>
              © {CURRENT_YEAR} Leaxer AI.
            </p>
          </div>
        </div>

        {/* Content */}
        <div className="flex-1 flex flex-col min-w-0">
          {/* Header */}
          <div className="flex items-center justify-between px-6 py-5">
            <h3
              className="text-[16px] font-semibold"
              style={{ color: 'var(--color-text)' }}
            >
              {categories.find((c) => c.id === activeCategory)?.label}
            </h3>
            <button
              onClick={handleClose}
              className="p-2 rounded-xl transition-colors cursor-pointer hover:bg-white/5"
              style={{ color: 'var(--color-text-muted)' }}
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Scrollable content */}
          <div className="flex-1 overflow-y-auto px-6 pb-6">
            {renderContent()}
          </div>
        </div>
      </div>
    </div>
  );
}
