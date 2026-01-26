import { memo, useEffect, useState } from 'react';
import { Position, type NodeProps } from '@xyflow/react';
import { BaseNode } from '../BaseNode';
import { useGraphStore } from '@/stores/graphStore';
import { apiFetch } from '@/lib/fetch';
import { Label } from '@/components/ui/label';
import { Slider } from '@/components/ui/slider';
import { useSettingsStore } from '@/stores/settingsStore';
import { Loader2, FileWarning } from 'lucide-react';
import { createLogger } from '@/lib/logger';

const log = createLogger('LoadLoRANode');

interface LoRAModel {
  name: string;
  path: string;
  size_bytes: number;
  size_human: string;
}

const APPLY_MODES = [
  { value: 'auto', label: 'Auto' },
  { value: 'immediately', label: 'Immediately' },
  { value: 'at_runtime', label: 'At Runtime' },
];

export const LoadLoRANode = memo(({ id, data, selected }: NodeProps) => {
  const updateNodeData = useGraphStore((state) => state.updateNodeData);
  const getApiBaseUrl = useSettingsStore((s) => s.getApiBaseUrl);

  const [loraModels, setLoraModels] = useState<LoRAModel[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Fetch available LoRA models from backend
  useEffect(() => {
    const fetchLoRAModels = async () => {
      try {
        setLoading(true);
        setError(null);
        const apiBaseUrl = getApiBaseUrl();
        const url = `${apiBaseUrl}/api/models/loras`;
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
        setLoraModels(models);
      } catch (err) {
        log.error('Error:', err);
        setError(err instanceof Error ? err.message : 'Failed to load LoRA models');
      } finally {
        setLoading(false);
      }
    };

    fetchLoRAModels();
  }, [getApiBaseUrl]);

  const selectedLoRA = loraModels.find((m) => m.path === data.lora_path);

  return (
    <BaseNode
      nodeId={id}
      title="Load LoRA"
      customTitle={data._title as string | undefined}
      onTitleChange={(newTitle) => updateNodeData(id, { _title: newTitle })}
      selected={selected}
      handles={[
        { id: 'lora', type: 'source', position: Position.Right, label: 'LORA', dataType: 'LORA' },
      ]}
    >
      <div className="space-y-3 min-w-[240px]">
        <div className="space-y-1.5">
          <Label className="text-xs text-text-muted">LORA MODEL</Label>

          {loading ? (
            <div className="flex items-center gap-2 text-xs text-text-muted py-2">
              <Loader2 className="w-4 h-4 animate-spin" />
              Loading LoRA models...
            </div>
          ) : error ? (
            <div className="flex items-center gap-2 text-xs text-error py-2">
              <FileWarning className="w-4 h-4" />
              {error}
            </div>
          ) : loraModels.length === 0 ? (
            <div className="text-xs text-text-muted py-2">
              No LoRA models found. Add .safetensors files to ~/Documents/Leaxer/models/lora/
            </div>
          ) : (
            <select
              value={(data.lora_path as string) || ''}
              onChange={(e) => updateNodeData(id, { lora_path: e.target.value })}
              className="nodrag nowheel w-full h-9 text-xs bg-surface-1/50 border border-overlay-0 rounded-md px-2 text-text-primary"
            >
              <option value="">Select a LoRA model...</option>
              {loraModels.map((model) => (
                <option key={model.path} value={model.path}>
                  {model.name} ({model.size_human})
                </option>
              ))}
            </select>
          )}
        </div>

        {/* Multiplier slider */}
        <div className="w-full space-y-2">
          <div className="flex justify-between">
            <Label className="text-xs text-text-muted">MULTIPLIER</Label>
            <span className="text-xs text-text-secondary tabular-nums">
              {(data.multiplier as number) ?? 1.0}
            </span>
          </div>
          <Slider
            value={(data.multiplier as number) ?? 1.0}
            onChange={(v: number) => updateNodeData(id, { multiplier: v })}
            min={0.0}
            max={2.0}
            step={0.1}
            className="nodrag nowheel w-full"
          />
        </div>

        {/* Apply mode dropdown */}
        <div className="w-full space-y-1.5">
          <Label className="text-xs text-text-muted">APPLY MODE</Label>
          <select
            value={(data.apply_mode as string) || 'auto'}
            onChange={(e) => updateNodeData(id, { apply_mode: e.target.value })}
            className="nodrag nowheel w-full h-8 text-xs bg-surface-1/50 border border-overlay-0 rounded-md px-2 text-text-primary"
          >
            {APPLY_MODES.map((mode) => (
              <option key={mode.value} value={mode.value}>
                {mode.label}
              </option>
            ))}
          </select>
        </div>

        {/* LoRA model info */}
        {selectedLoRA && (
          <div className="text-[10px] text-text-muted space-y-1 p-2 bg-surface-1/30 rounded">
            <div className="flex justify-between">
              <span>Size:</span>
              <span className="text-text-secondary">{selectedLoRA.size_human}</span>
            </div>
            <div className="flex justify-between">
              <span>File:</span>
              <span className="text-text-secondary truncate max-w-[120px]" title={selectedLoRA.name}>
                {selectedLoRA.name}
              </span>
            </div>
          </div>
        )}
      </div>
    </BaseNode>
  );
});

LoadLoRANode.displayName = 'LoadLoRANode';