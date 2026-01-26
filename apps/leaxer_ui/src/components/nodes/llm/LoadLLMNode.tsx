import { memo, useEffect, useState } from 'react';
import { Position, type NodeProps } from '@xyflow/react';
import { BaseNode } from '../BaseNode';
import { useGraphStore } from '@/stores/graphStore';
import { apiFetch } from '@/lib/fetch';
import { Label } from '@/components/ui/label';
import { Slider } from '@/components/ui/slider';
import { Input } from '@/components/ui/input';
import { useSettingsStore } from '@/stores/settingsStore';
import { Loader2, FileWarning } from 'lucide-react';
import { createLogger } from '@/lib/logger';

const log = createLogger('LoadLLMNode');

interface LLMModel {
  name: string;
  path: string;
  size_bytes: number;
  size_human: string;
}

export const LoadLLMNode = memo(({ id, data, selected }: NodeProps) => {
  const updateNodeData = useGraphStore((state) => state.updateNodeData);
  const getApiBaseUrl = useSettingsStore((s) => s.getApiBaseUrl);

  const [llmModels, setLlmModels] = useState<LLMModel[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Fetch available LLM models from backend
  useEffect(() => {
    const fetchLLMModels = async () => {
      try {
        setLoading(true);
        setError(null);
        const apiBaseUrl = getApiBaseUrl();
        const url = `${apiBaseUrl}/api/models/llms`;
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
        setLlmModels(models);
      } catch (err) {
        log.error('Error:', err);
        setError(err instanceof Error ? err.message : 'Failed to load LLM models');
      } finally {
        setLoading(false);
      }
    };

    fetchLLMModels();
  }, [getApiBaseUrl]);

  const selectedLLM = llmModels.find((m) => m.path === data.model_path);

  return (
    <BaseNode
      nodeId={id}
      title="Load LLM"
      customTitle={data._title as string | undefined}
      onTitleChange={(newTitle) => updateNodeData(id, { _title: newTitle })}
      selected={selected}
      handles={[
        { id: 'llm', type: 'source', position: Position.Right, label: 'LLM', dataType: 'LLM' },
      ]}
    >
      <div className="space-y-3 min-w-[240px]">
        <div className="space-y-1.5">
          <Label className="text-xs text-text-muted">LLM MODEL</Label>

          {loading ? (
            <div className="flex items-center gap-2 text-xs text-text-muted py-2">
              <Loader2 className="w-4 h-4 animate-spin" />
              Loading LLM models...
            </div>
          ) : error ? (
            <div className="flex items-center gap-2 text-xs text-error py-2">
              <FileWarning className="w-4 h-4" />
              {error}
            </div>
          ) : llmModels.length === 0 ? (
            <div className="text-xs text-text-muted py-2">
              No LLM models found. Add .gguf files to ~/Documents/Leaxer/models/llm/
            </div>
          ) : (
            <select
              value={(data.model_path as string) || ''}
              onChange={(e) => updateNodeData(id, { model_path: e.target.value })}
              className="nodrag nowheel w-full h-9 text-xs bg-surface-1/50 border border-overlay-0 rounded-md px-2 text-text-primary"
            >
              <option value="">Select an LLM model...</option>
              {llmModels.map((model) => (
                <option key={model.path} value={model.path}>
                  {model.name} ({model.size_human})
                </option>
              ))}
            </select>
          )}
        </div>

        {/* Context Size slider */}
        <div className="w-full space-y-2">
          <div className="flex justify-between">
            <Label className="text-xs text-text-muted">CONTEXT SIZE</Label>
            <span className="text-xs text-text-secondary tabular-nums">
              {(data.context_size as number) ?? 4096}
            </span>
          </div>
          <Slider
            value={(data.context_size as number) ?? 4096}
            onChange={(v: number) => updateNodeData(id, { context_size: v })}
            min={512}
            max={32768}
            step={256}
            className="nodrag nowheel w-full"
          />
          <div className="text-[10px] text-text-muted">
            Maximum context length in tokens (512 to 32768)
          </div>
        </div>

        {/* GPU Layers input */}
        <div className="w-full space-y-1.5">
          <Label className="text-xs text-text-muted">GPU LAYERS</Label>
          <Input
            type="number"
            value={(data.gpu_layers as number) ?? -1}
            onChange={(e) => updateNodeData(id, { gpu_layers: parseInt(e.target.value) || -1 })}
            min={-1}
            max={100}
            step={1}
            className="nodrag nowheel h-8 text-xs"
            placeholder="-1"
          />
          <div className="text-[10px] text-text-muted">
            Number of layers to offload to GPU (-1 for all)
          </div>
        </div>

        {/* LLM model info */}
        {selectedLLM && (
          <div className="text-[10px] text-text-muted space-y-1 p-2 bg-surface-1/30 rounded">
            <div className="flex justify-between">
              <span>Size:</span>
              <span className="text-text-secondary">{selectedLLM.size_human}</span>
            </div>
            <div className="flex justify-between">
              <span>File:</span>
              <span className="text-text-secondary truncate max-w-[120px]" title={selectedLLM.name}>
                {selectedLLM.name}
              </span>
            </div>
          </div>
        )}
      </div>
    </BaseNode>
  );
});

LoadLLMNode.displayName = 'LoadLLMNode';