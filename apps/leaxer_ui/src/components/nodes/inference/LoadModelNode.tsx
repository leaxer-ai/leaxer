import { memo, useEffect, useState } from 'react';
import { Position, type NodeProps } from '@xyflow/react';
import { BaseNode } from '../BaseNode';
import { useGraphStore } from '@/stores/graphStore';
import { apiFetch } from '@/lib/fetch';
import { Label } from '@/components/ui/label';
import { useSettingsStore } from '@/stores/settingsStore';
import { Loader2, FileWarning } from 'lucide-react';

interface ModelInfo {
  name: string;
  path: string;
  format: string;
  size_bytes: number;
  size_human: string;
  type: string;
}

const WEIGHT_TYPES = [
  { value: 'default', label: 'Default (auto)' },
  { value: 'f32', label: 'Float32 (highest quality)' },
  { value: 'f16', label: 'Float16 (good quality)' },
  { value: 'q8_0', label: 'Q8_0 (8-bit)' },
  { value: 'q5_1', label: 'Q5_1 (5-bit)' },
  { value: 'q5_0', label: 'Q5_0 (5-bit)' },
  { value: 'q4_1', label: 'Q4_1 (4-bit)' },
  { value: 'q4_0', label: 'Q4_0 (4-bit)' },
  { value: 'q4_k', label: 'Q4_K (k-quant 4-bit)' },
  { value: 'q3_k', label: 'Q3_K (k-quant 3-bit)' },
  { value: 'q2_k', label: 'Q2_K (k-quant 2-bit)' },
];

export const LoadModelNode = memo(({ id, data, selected }: NodeProps) => {
  const updateNodeData = useGraphStore((state) => state.updateNodeData);
  const getApiBaseUrl = useSettingsStore((s) => s.getApiBaseUrl);

  const [models, setModels] = useState<ModelInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Get API base URL (handles LAN access automatically)
  const apiBaseUrl = getApiBaseUrl();

  // Fetch available models from backend
  useEffect(() => {
    const fetchModels = async () => {
      try {
        setLoading(true);
        setError(null);
        const response = await apiFetch(`${apiBaseUrl}/api/models/checkpoints`);
        if (!response.ok) throw new Error('Failed to fetch models');
        const data = await response.json();
        setModels(data.models || []);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to load models');
      } finally {
        setLoading(false);
      }
    };

    fetchModels();
  }, [apiBaseUrl]);

  const selectedModel = models.find((m) => m.path === data.model_path);
  const isGGUF = selectedModel?.format === 'gguf';

  return (
    <BaseNode
      nodeId={id}
      title="Load Checkpoint"
      customTitle={data._title as string | undefined}
      onTitleChange={(newTitle) => updateNodeData(id, { _title: newTitle })}
      selected={selected}
      handles={[
        { id: 'model', type: 'source', position: Position.Right, label: 'MODEL', dataType: 'MODEL' },
      ]}
    >
      <div className="space-y-3 min-w-[240px]">
        <div className="space-y-1.5">
          <Label className="text-xs text-text-muted">CHECKPOINT MODEL</Label>

          {loading ? (
            <div className="flex items-center gap-2 text-xs text-text-muted py-2">
              <Loader2 className="w-4 h-4 animate-spin" />
              Loading models...
            </div>
          ) : error ? (
            <div className="flex items-center gap-2 text-xs text-error py-2">
              <FileWarning className="w-4 h-4" />
              {error}
            </div>
          ) : models.length === 0 ? (
            <div className="text-xs text-text-muted py-2">
              No models found. Add .safetensors, .ckpt, or .gguf files to your models folder.
            </div>
          ) : (
            <select
              value={(data.model_path as string) || ''}
              onChange={(e) => updateNodeData(id, { model_path: e.target.value })}
              className="nodrag nowheel w-full h-9 text-xs bg-surface-1/50 border border-overlay-0 rounded-md px-2 text-text-primary"
            >
              <option value="">Select a model...</option>
              {models.map((model) => (
                <option key={model.path} value={model.path}>
                  {model.name} ({model.size_human})
                </option>
              ))}
            </select>
          )}
        </div>

        {/* Model info */}
        {selectedModel && (
          <div className="text-[10px] text-text-muted space-y-1 p-2 bg-surface-1/30 rounded">
            <div className="flex justify-between">
              <span>Format:</span>
              <span className="text-text-secondary">{selectedModel.format}</span>
            </div>
            <div className="flex justify-between">
              <span>Size:</span>
              <span className="text-text-secondary">{selectedModel.size_human}</span>
            </div>
          </div>
        )}

        {/* Weight Type (only show for GGUF models or always for advanced users) */}
        {selectedModel && (
          <div className="space-y-1.5">
            <Label className="text-xs text-text-muted">
              WEIGHT TYPE {isGGUF && <span className="text-green-400">(GGUF)</span>}
            </Label>
            <select
              value={(data.weight_type as string) || 'default'}
              onChange={(e) => updateNodeData(id, { weight_type: e.target.value })}
              className="nodrag nowheel w-full h-9 text-xs bg-surface-1/50 border border-overlay-0 rounded-md px-2 text-text-primary"
            >
              {WEIGHT_TYPES.map((type) => (
                <option key={type.value} value={type.value}>
                  {type.label}
                </option>
              ))}
            </select>
            <p className="text-[10px] text-text-muted">
              {isGGUF
                ? 'Quantization for GGUF model weights'
                : 'Convert weights on load (advanced)'}
            </p>
          </div>
        )}

      </div>
    </BaseNode>
  );
});

LoadModelNode.displayName = 'LoadModelNode';
