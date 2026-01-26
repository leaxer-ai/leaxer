import { memo, useEffect, useState } from 'react';
import { Position, type NodeProps } from '@xyflow/react';
import { BaseNode } from '../BaseNode';
import { useGraphStore } from '@/stores/graphStore';
import { apiFetch } from '@/lib/fetch';
import { Label } from '@/components/ui/label';
import { Slider } from '@/components/ui/slider';
import { Switch } from '@/components/ui/switch';
import { useSettingsStore } from '@/stores/settingsStore';
import { Loader2, FileWarning } from 'lucide-react';
import { createLogger } from '@/lib/logger';

const log = createLogger('LoadVAENode');

interface VAEModel {
  name: string;
  path: string;
  size_bytes: number;
  size_human: string;
}

export const LoadVAENode = memo(({ id, data, selected }: NodeProps) => {
  const updateNodeData = useGraphStore((state) => state.updateNodeData);
  const getApiBaseUrl = useSettingsStore((s) => s.getApiBaseUrl);

  const [vaeModels, setVaeModels] = useState<VAEModel[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Fetch available VAE models from backend
  useEffect(() => {
    const fetchVAEModels = async () => {
      try {
        setLoading(true);
        setError(null);
        const apiBaseUrl = getApiBaseUrl();
        const url = `${apiBaseUrl}/api/models/vaes`;
        log.debug('Fetching from:', url);

        const response = await apiFetch(url);
        log.debug('Response:', response.status, response.ok);

        if (!response.ok) {
          throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        const json = await response.json();
        log.debug('Data:', json);

        const models = json.models || [];
        log.debug('Models count:', models.length);
        setVaeModels(models);
      } catch (err) {
        log.error('Error:', err);
        setError(err instanceof Error ? err.message : 'Failed to load VAE models');
      } finally {
        setLoading(false);
      }
    };

    fetchVAEModels();
  }, [getApiBaseUrl]);

  const selectedVAE = vaeModels.find((m) => m.path === data.vae_path);

  return (
    <BaseNode
      nodeId={id}
      title="Load VAE"
      customTitle={data._title as string | undefined}
      onTitleChange={(newTitle) => updateNodeData(id, { _title: newTitle })}
      selected={selected}
      handles={[
        { id: 'vae', type: 'source', position: Position.Right, label: 'VAE', dataType: 'VAE' },
      ]}
    >
      <div className="space-y-3 min-w-[240px]">
        <div className="space-y-1.5">
          <Label className="text-xs text-text-muted">VAE MODEL</Label>

          {loading ? (
            <div className="flex items-center gap-2 text-xs text-text-muted py-2">
              <Loader2 className="w-4 h-4 animate-spin" />
              Loading VAE models...
            </div>
          ) : error ? (
            <div className="flex items-center gap-2 text-xs text-error py-2">
              <FileWarning className="w-4 h-4" />
              {error}
            </div>
          ) : vaeModels.length === 0 ? (
            <div className="text-xs text-text-muted py-2">
              No VAE models found. Add .safetensors files to ~/Documents/Leaxer/models/vae/
            </div>
          ) : (
            <select
              value={(data.vae_path as string) || ''}
              onChange={(e) => updateNodeData(id, { vae_path: e.target.value })}
              className="nodrag nowheel w-full h-9 text-xs bg-surface-1/50 border border-overlay-0 rounded-md px-2 text-text-primary"
            >
              <option value="">Select a VAE model...</option>
              {vaeModels.map((model) => (
                <option key={model.path} value={model.path}>
                  {model.name} ({model.size_human})
                </option>
              ))}
            </select>
          )}
        </div>

        {/* Tiling toggle */}
        <div className="w-full space-y-1.5">
          <div className="flex items-center justify-between">
            <Label className="text-xs text-text-muted">TILING</Label>
            <Switch
              checked={(data.tiling as boolean) ?? false}
              onCheckedChange={(checked) => updateNodeData(id, { tiling: checked })}
              className="nodrag"
            />
          </div>
          <div className="text-[10px] text-text-muted">
            Enable VAE tiling to reduce VRAM usage
          </div>
        </div>

        {/* Tile size slider - only show when tiling is enabled */}
        {((data.tiling as boolean) ?? false) && (
          <div className="w-full space-y-2">
            <div className="flex justify-between">
              <Label className="text-xs text-text-muted">TILE SIZE</Label>
              <span className="text-xs text-text-secondary tabular-nums">
                {(data.tile_size as number) ?? 512}px
              </span>
            </div>
            <Slider
              value={(data.tile_size as number) ?? 512}
              onChange={(v: number) => updateNodeData(id, { tile_size: v })}
              min={128}
              max={2048}
              step={64}
              className="nodrag nowheel w-full"
            />
          </div>
        )}

        {/* On CPU toggle */}
        <div className="w-full space-y-1.5">
          <div className="flex items-center justify-between">
            <Label className="text-xs text-text-muted">ON CPU</Label>
            <Switch
              checked={(data.on_cpu as boolean) ?? false}
              onCheckedChange={(checked) => updateNodeData(id, { on_cpu: checked })}
              className="nodrag"
            />
          </div>
          <div className="text-[10px] text-text-muted">
            Keep VAE on CPU to save VRAM
          </div>
        </div>

        {/* VAE model info */}
        {selectedVAE && (
          <div className="text-[10px] text-text-muted space-y-1 p-2 bg-surface-1/30 rounded">
            <div className="flex justify-between">
              <span>Size:</span>
              <span className="text-text-secondary">{selectedVAE.size_human}</span>
            </div>
            <div className="flex justify-between">
              <span>File:</span>
              <span className="text-text-secondary truncate max-w-[120px]" title={selectedVAE.name}>
                {selectedVAE.name}
              </span>
            </div>
          </div>
        )}
      </div>
    </BaseNode>
  );
});

LoadVAENode.displayName = 'LoadVAENode';