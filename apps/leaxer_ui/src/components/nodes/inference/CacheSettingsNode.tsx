import { memo } from 'react';
import { Position, type NodeProps } from '@xyflow/react';
import { BaseNode } from '../BaseNode';
import { useGraphStore } from '@/stores/graphStore';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { ParameterHandle } from '../ParameterHandle';
import { useIsHandleConnected } from '@/hooks/useHandleConnections';
import { cn } from '@/lib/utils';
import { Zap } from 'lucide-react';

const CACHE_MODES = [
  { value: 'none', label: 'None (disabled)' },
  { value: 'ucache', label: 'Uniform Cache' },
  { value: 'easycache', label: 'Easy Cache' },
  { value: 'dbcache', label: 'DB Cache' },
  { value: 'taylorseer', label: 'Taylor Seer' },
];

const CACHE_PRESETS = [
  { value: 'slow', label: 'Slow (highest quality)' },
  { value: 'medium', label: 'Medium (balanced)' },
  { value: 'fast', label: 'Fast (lower quality)' },
  { value: 'ultra', label: 'Ultra (fastest)' },
];

export const CacheSettingsNode = memo(({ id, data, selected }: NodeProps) => {
  const updateNodeData = useGraphStore((state) => state.updateNodeData);

  // Check handle connections
  const thresholdConnected = useIsHandleConnected(id, 'threshold', 'target');
  const warmupConnected = useIsHandleConnected(id, 'warmup', 'target');
  const startStepConnected = useIsHandleConnected(id, 'start_step', 'target');
  const endStepConnected = useIsHandleConnected(id, 'end_step', 'target');

  const mode = (data.mode as string) || 'none';
  const isEnabled = mode !== 'none';

  return (
    <BaseNode
      nodeId={id}
      title="Cache Settings"
      customTitle={data._title as string | undefined}
      onTitleChange={(newTitle) => updateNodeData(id, { _title: newTitle })}
      selected={selected}
      handles={[
        { id: 'cache_settings', type: 'source', position: Position.Right, label: 'CACHE SETTINGS', dataType: 'CACHE_SETTINGS' },
      ]}
    >
      <div className="w-full space-y-3">
        {/* Info */}
        <div className="flex items-start gap-2 p-2 bg-green-500/10 border border-green-500/30 rounded text-xs text-green-200">
          <Zap className="w-4 h-4 flex-shrink-0 mt-0.5" />
          <span>Configure caching for faster inference. Trades quality for speed.</span>
        </div>

        {/* Cache Mode */}
        <div className="w-full space-y-1.5">
          <Label className="text-xs text-text-muted">CACHE MODE</Label>
          <select
            value={mode}
            onChange={(e) => updateNodeData(id, { mode: e.target.value })}
            className="nodrag w-full h-8 px-2 text-xs bg-surface-1/50 border border-overlay-0 rounded focus:outline-none focus:ring-1 focus:ring-accent"
          >
            {CACHE_MODES.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </div>

        {/* Show preset and options only when caching is enabled */}
        {isEnabled && (
          <>
            {/* Cache Preset */}
            <div className="w-full space-y-1.5">
              <Label className="text-xs text-text-muted">PRESET</Label>
              <select
                value={(data.preset as string) || 'medium'}
                onChange={(e) => updateNodeData(id, { preset: e.target.value })}
                className="nodrag w-full h-8 px-2 text-xs bg-surface-1/50 border border-overlay-0 rounded focus:outline-none focus:ring-1 focus:ring-accent"
              >
                {CACHE_PRESETS.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </select>
              <p className="text-[10px] text-text-muted">
                Speed/quality tradeoff preset
              </p>
            </div>

            {/* Advanced Options */}
            <div className="p-2 bg-surface-1/20 rounded space-y-3">
              <Label className="text-xs text-text-muted font-medium">Advanced Options</Label>

              {/* Threshold */}
              <div className="relative w-full space-y-1.5">
                <ParameterHandle id="threshold" dataType="FLOAT" />
                <Label className="text-xs text-text-muted">THRESHOLD</Label>
                <Input
                  type="number"
                  value={thresholdConnected ? '' : ((data.threshold as number) ?? 0.5)}
                  onChange={(e) => updateNodeData(id, { threshold: parseFloat(e.target.value) || 0.5 })}
                  onKeyDown={(e) => e.stopPropagation()}
                  placeholder={thresholdConnected ? 'Connected' : '0.5'}
                  disabled={thresholdConnected}
                  min={0}
                  max={1}
                  step={0.05}
                  className={cn(
                    'nodrag nowheel w-full h-8 text-xs bg-surface-1/50 border-overlay-0',
                    thresholdConnected && 'opacity-50'
                  )}
                />
              </div>

              {/* Warmup */}
              <div className="relative w-full space-y-1.5">
                <ParameterHandle id="warmup" dataType="INTEGER" />
                <Label className="text-xs text-text-muted">WARMUP STEPS</Label>
                <Input
                  type="number"
                  value={warmupConnected ? '' : ((data.warmup as number) ?? 2)}
                  onChange={(e) => updateNodeData(id, { warmup: parseInt(e.target.value) || 2 })}
                  onKeyDown={(e) => e.stopPropagation()}
                  placeholder={warmupConnected ? 'Connected' : '2'}
                  disabled={warmupConnected}
                  min={0}
                  max={20}
                  className={cn(
                    'nodrag nowheel w-full h-8 text-xs bg-surface-1/50 border-overlay-0',
                    warmupConnected && 'opacity-50'
                  )}
                />
              </div>

              {/* Start Step */}
              <div className="relative w-full space-y-1.5">
                <ParameterHandle id="start_step" dataType="INTEGER" />
                <Label className="text-xs text-text-muted">START STEP</Label>
                <Input
                  type="number"
                  value={startStepConnected ? '' : ((data.start_step as number) ?? 0)}
                  onChange={(e) => updateNodeData(id, { start_step: parseInt(e.target.value) || 0 })}
                  onKeyDown={(e) => e.stopPropagation()}
                  placeholder={startStepConnected ? 'Connected' : '0'}
                  disabled={startStepConnected}
                  min={0}
                  max={100}
                  className={cn(
                    'nodrag nowheel w-full h-8 text-xs bg-surface-1/50 border-overlay-0',
                    startStepConnected && 'opacity-50'
                  )}
                />
              </div>

              {/* End Step */}
              <div className="relative w-full space-y-1.5">
                <ParameterHandle id="end_step" dataType="INTEGER" />
                <Label className="text-xs text-text-muted">END STEP</Label>
                <Input
                  type="number"
                  value={endStepConnected ? '' : ((data.end_step as number) ?? -1)}
                  onChange={(e) => updateNodeData(id, { end_step: parseInt(e.target.value) })}
                  onKeyDown={(e) => e.stopPropagation()}
                  placeholder={endStepConnected ? 'Connected' : '-1'}
                  disabled={endStepConnected}
                  min={-1}
                  max={100}
                  className={cn(
                    'nodrag nowheel w-full h-8 text-xs bg-surface-1/50 border-overlay-0',
                    endStepConnected && 'opacity-50'
                  )}
                />
                <p className="text-[10px] text-text-muted">
                  -1 means until end
                </p>
              </div>
            </div>
          </>
        )}
      </div>
    </BaseNode>
  );
});

CacheSettingsNode.displayName = 'CacheSettingsNode';
