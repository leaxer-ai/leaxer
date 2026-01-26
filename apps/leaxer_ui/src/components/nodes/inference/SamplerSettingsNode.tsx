import { memo } from 'react';
import { Position, type NodeProps } from '@xyflow/react';
import { BaseNode } from '../BaseNode';
import { useGraphStore } from '@/stores/graphStore';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { ParameterHandle } from '../ParameterHandle';
import { useIsHandleConnected } from '@/hooks/useHandleConnections';
import { cn } from '@/lib/utils';
import { Sliders } from 'lucide-react';

const SAMPLING_METHODS = [
  { value: 'euler', label: 'Euler' },
  { value: 'euler_a', label: 'Euler Ancestral' },
  { value: 'heun', label: 'Heun' },
  { value: 'dpm2', label: 'DPM2' },
  { value: 'dpm++2s_a', label: 'DPM++ 2S Ancestral' },
  { value: 'dpm++2m', label: 'DPM++ 2M' },
  { value: 'ipndm', label: 'iPNDM' },
  { value: 'lcm', label: 'LCM' },
  { value: 'ddim', label: 'DDIM' },
  { value: 'tcd', label: 'TCD' },
];

const SCHEDULERS = [
  { value: 'discrete', label: 'Discrete' },
  { value: 'karras', label: 'Karras' },
  { value: 'exponential', label: 'Exponential' },
  { value: 'ays', label: 'AYS' },
  { value: 'gits', label: 'GITS' },
];

export const SamplerSettingsNode = memo(({ id, data, selected }: NodeProps) => {
  const updateNodeData = useGraphStore((state) => state.updateNodeData);

  // Check handle connections
  const etaConnected = useIsHandleConnected(id, 'eta', 'target');

  return (
    <BaseNode
      nodeId={id}
      title="Sampler Settings"
      customTitle={data._title as string | undefined}
      onTitleChange={(newTitle) => updateNodeData(id, { _title: newTitle })}
      selected={selected}
      handles={[
        { id: 'sampler_settings', type: 'source', position: Position.Right, label: 'SAMPLER SETTINGS', dataType: 'SAMPLER_SETTINGS' },
      ]}
    >
      <div className="w-full space-y-3">
        {/* Info */}
        <div className="flex items-start gap-2 p-2 bg-blue-500/10 border border-blue-500/30 rounded text-xs text-blue-200">
          <Sliders className="w-4 h-4 flex-shrink-0 mt-0.5" />
          <span>Configure sampling method and scheduler for image generation.</span>
        </div>

        {/* Sampling Method */}
        <div className="w-full space-y-1.5">
          <Label className="text-xs text-text-muted">SAMPLING METHOD</Label>
          <select
            value={(data.method as string) || 'euler_a'}
            onChange={(e) => updateNodeData(id, { method: e.target.value })}
            className="nodrag w-full h-8 px-2 text-xs bg-surface-1/50 border border-overlay-0 rounded focus:outline-none focus:ring-1 focus:ring-accent"
          >
            {SAMPLING_METHODS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
          <p className="text-[10px] text-text-muted">
            Algorithm for noise sampling
          </p>
        </div>

        {/* Scheduler */}
        <div className="w-full space-y-1.5">
          <Label className="text-xs text-text-muted">SCHEDULER</Label>
          <select
            value={(data.scheduler as string) || 'discrete'}
            onChange={(e) => updateNodeData(id, { scheduler: e.target.value })}
            className="nodrag w-full h-8 px-2 text-xs bg-surface-1/50 border border-overlay-0 rounded focus:outline-none focus:ring-1 focus:ring-accent"
          >
            {SCHEDULERS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
          <p className="text-[10px] text-text-muted">
            Noise schedule type
          </p>
        </div>

        {/* Eta */}
        <div className="relative w-full space-y-1.5">
          <ParameterHandle id="eta" dataType="FLOAT" />
          <Label className="text-xs text-text-muted">ETA</Label>
          <Input
            type="number"
            value={etaConnected ? '' : ((data.eta as number) ?? 0)}
            onChange={(e) => updateNodeData(id, { eta: parseFloat(e.target.value) || 0 })}
            onKeyDown={(e) => e.stopPropagation()}
            placeholder={etaConnected ? 'Connected' : '0'}
            disabled={etaConnected}
            min={0}
            max={1}
            step={0.05}
            className={cn(
              'nodrag nowheel w-full h-8 text-xs bg-surface-1/50 border-overlay-0',
              etaConnected && 'opacity-50'
            )}
          />
          <p className="text-[10px] text-text-muted">
            0 = deterministic, higher = more variation
          </p>
        </div>
      </div>
    </BaseNode>
  );
});

SamplerSettingsNode.displayName = 'SamplerSettingsNode';
