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

const log = createLogger('LoadControlNetNode');

interface ControlNetModel {
  name: string;
  path: string;
  size_bytes: number;
  size_human: string;
}

export const LoadControlNetNode = memo(({ id, data, selected }: NodeProps) => {
  const updateNodeData = useGraphStore((state) => state.updateNodeData);
  const getApiBaseUrl = useSettingsStore((s) => s.getApiBaseUrl);

  const [controlnetModels, setControlnetModels] = useState<ControlNetModel[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Fetch available ControlNet models from backend
  useEffect(() => {
    const fetchControlNetModels = async () => {
      try {
        setLoading(true);
        setError(null);
        const apiBaseUrl = getApiBaseUrl();
        const url = `${apiBaseUrl}/api/models/controlnets`;
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
        setControlnetModels(models);
      } catch (err) {
        log.error('Error:', err);
        setError(err instanceof Error ? err.message : 'Failed to load ControlNet models');
      } finally {
        setLoading(false);
      }
    };

    fetchControlNetModels();
  }, [getApiBaseUrl]);

  const selectedControlNet = controlnetModels.find((m) => m.path === data.controlnet_path);

  return (
    <BaseNode
      nodeId={id}
      title="Load ControlNet"
      customTitle={data._title as string | undefined}
      onTitleChange={(newTitle) => updateNodeData(id, { _title: newTitle })}
      selected={selected}
      handles={[
        { id: 'controlnet', type: 'source', position: Position.Right, label: 'CONTROLNET', dataType: 'CONTROLNET' },
      ]}
    >
      <div className="space-y-3 min-w-[240px]">
        <div className="space-y-1.5">
          <Label className="text-xs text-text-muted">CONTROLNET MODEL</Label>

          {loading ? (
            <div className="flex items-center gap-2 text-xs text-text-muted py-2">
              <Loader2 className="w-4 h-4 animate-spin" />
              Loading ControlNet models...
            </div>
          ) : error ? (
            <div className="flex items-center gap-2 text-xs text-error py-2">
              <FileWarning className="w-4 h-4" />
              {error}
            </div>
          ) : controlnetModels.length === 0 ? (
            <div className="text-xs text-text-muted py-2">
              No ControlNet models found. Add .safetensors files to ~/Documents/Leaxer/models/controlnet/
            </div>
          ) : (
            <select
              value={(data.controlnet_path as string) || ''}
              onChange={(e) => updateNodeData(id, { controlnet_path: e.target.value })}
              className="nodrag nowheel w-full h-9 text-xs bg-surface-1/50 border border-overlay-0 rounded-md px-2 text-text-primary"
            >
              <option value="">Select a ControlNet model...</option>
              {controlnetModels.map((model) => (
                <option key={model.path} value={model.path}>
                  {model.name} ({model.size_human})
                </option>
              ))}
            </select>
          )}
        </div>

        {/* Strength slider */}
        <div className="w-full space-y-2">
          <div className="flex justify-between">
            <Label className="text-xs text-text-muted">STRENGTH</Label>
            <span className="text-xs text-text-secondary tabular-nums">
              {(data.strength as number) ?? 1.0}
            </span>
          </div>
          <Slider
            value={(data.strength as number) ?? 1.0}
            onChange={(v: number) => updateNodeData(id, { strength: v })}
            min={0.0}
            max={1.0}
            step={0.1}
            className="nodrag nowheel w-full"
          />
        </div>

        {/* CPU toggle */}
        <div className="w-full space-y-1.5">
          <div className="flex items-center justify-between">
            <Label className="text-xs text-text-muted">KEEP ON CPU</Label>
            <Switch
              checked={(data.keep_on_cpu as boolean) ?? false}
              onCheckedChange={(checked) => updateNodeData(id, { keep_on_cpu: checked })}
              className="nodrag"
            />
          </div>
          <div className="text-[10px] text-text-muted">
            Keep ControlNet model on CPU to save VRAM
          </div>
        </div>

        {/* ControlNet model info */}
        {selectedControlNet && (
          <div className="text-[10px] text-text-muted space-y-1 p-2 bg-surface-1/30 rounded">
            <div className="flex justify-between">
              <span>Size:</span>
              <span className="text-text-secondary">{selectedControlNet.size_human}</span>
            </div>
            <div className="flex justify-between">
              <span>File:</span>
              <span className="text-text-secondary truncate max-w-[120px]" title={selectedControlNet.name}>
                {selectedControlNet.name}
              </span>
            </div>
          </div>
        )}
      </div>
    </BaseNode>
  );
});

LoadControlNetNode.displayName = 'LoadControlNetNode';