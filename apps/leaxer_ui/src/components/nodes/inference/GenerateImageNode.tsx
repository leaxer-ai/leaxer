import { memo } from 'react';
import { Position, type NodeProps } from '@xyflow/react';
import { BaseNode } from '../BaseNode';
import { useGraphStore } from '@/stores/graphStore';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Slider } from '@/components/ui/slider';
import { ParameterHandle } from '../ParameterHandle';
import { useIsHandleConnected } from '@/hooks/useHandleConnections';
import { cn } from '@/lib/utils';

const SAMPLERS = [
  { value: 'euler', label: 'Euler' },
  { value: 'euler_a', label: 'Euler Ancestral' },
  { value: 'heun', label: 'Heun' },
  { value: 'dpm2', label: 'DPM2' },
  { value: 'dpm++2s_a', label: 'DPM++ 2S Ancestral' },
  { value: 'dpm++2m', label: 'DPM++ 2M' },
  { value: 'dpm++2mv2', label: 'DPM++ 2M v2' },
  { value: 'lcm', label: 'LCM' },
];

export const GenerateImageNode = memo(({ id, data, selected }: NodeProps) => {
  const updateNodeData = useGraphStore((state) => state.updateNodeData);

  // Check handle connections
  const stepsConnected = useIsHandleConnected(id, 'steps', 'target');
  const cfgConnected = useIsHandleConnected(id, 'cfg_scale', 'target');
  const seedConnected = useIsHandleConnected(id, 'seed', 'target');
  const strengthConnected = useIsHandleConnected(id, 'strength', 'target');

  return (
    <BaseNode
      nodeId={id}
      title="Generate Image"
      customTitle={data._title as string | undefined}
      onTitleChange={(newTitle) => updateNodeData(id, { _title: newTitle })}
      selected={selected}
      handles={[
        { id: 'model', type: 'target', position: Position.Left, label: 'MODEL', dataType: 'MODEL' },
        { id: 'init_image', type: 'target', position: Position.Left, label: 'INIT IMAGE', dataType: 'IMAGE' },
        { id: 'lora', type: 'target', position: Position.Left, label: 'LORA', dataType: 'LORA' },
        { id: 'lora_stack', type: 'target', position: Position.Left, label: 'STACKED LORAS', dataType: 'LORA_STACK' },
        { id: 'control_net', type: 'target', position: Position.Left, label: 'CONTROLNET', dataType: 'CONTROLNET' },
        { id: 'control_image', type: 'target', position: Position.Left, label: 'CONTROL IMAGE', dataType: 'IMAGE' },
        { id: 'mask_image', type: 'target', position: Position.Left, label: 'MASK IMAGE', dataType: 'IMAGE' },
        { id: 'vae', type: 'target', position: Position.Left, label: 'VAE', dataType: 'VAE' },
        { id: 'photo_maker', type: 'target', position: Position.Left, label: 'PHOTOMAKER', dataType: 'PHOTO_MAKER' },
        { id: 'text_encoders', type: 'target', position: Position.Left, label: 'TEXT ENCODERS', dataType: 'TEXT_ENCODERS' },
        { id: 'prompt', type: 'target', position: Position.Left, label: 'POSITIVE PROMPT', dataType: 'STRING' },
        { id: 'negative_prompt', type: 'target', position: Position.Left, label: 'NEGATIVE PROMPT', dataType: 'STRING' },
        { id: 'width', type: 'target', position: Position.Left, label: 'WIDTH', dataType: 'INTEGER' },
        { id: 'height', type: 'target', position: Position.Left, label: 'HEIGHT', dataType: 'INTEGER' },
        { id: 'image', type: 'source', position: Position.Right, label: 'IMAGE', dataType: 'IMAGE' },
      ]}
    >
      <div className="w-full space-y-3">
        {/* Steps */}
        <div className="relative w-full space-y-2">
          <ParameterHandle id="steps" dataType="INTEGER" />
          <div className="flex justify-between">
            <Label className="text-xs text-text-muted">STEPS</Label>
            <span className="text-xs text-text-secondary tabular-nums">
              {stepsConnected ? '–' : String(data.steps ?? 20)}
            </span>
          </div>
          <Slider
            value={(data.steps as number) || 20}
            onChange={(v: number) => updateNodeData(id, { steps: v })}
            min={1}
            max={150}
            step={1}
            disabled={stepsConnected}
            className={cn('nodrag nowheel w-full', stepsConnected && 'opacity-50')}
          />
        </div>

        {/* CFG Scale */}
        <div className="relative w-full space-y-2">
          <ParameterHandle id="cfg_scale" dataType="FLOAT" />
          <div className="flex justify-between">
            <Label className="text-xs text-text-muted">CFG SCALE</Label>
            <span className="text-xs text-text-secondary tabular-nums">
              {cfgConnected ? '–' : String(data.cfg_scale ?? 7.0)}
            </span>
          </div>
          <Slider
            value={(data.cfg_scale as number) ?? 7.0}
            onChange={(v: number) => updateNodeData(id, { cfg_scale: v })}
            min={1}
            max={30}
            step={0.5}
            disabled={cfgConnected}
            className={cn('nodrag nowheel w-full', cfgConnected && 'opacity-50')}
          />
        </div>

        {/* Strength */}
        <div className="relative w-full space-y-2">
          <ParameterHandle id="strength" dataType="FLOAT" />
          <div className="flex justify-between">
            <Label className="text-xs text-text-muted">STRENGTH</Label>
            <span className="text-xs text-text-secondary tabular-nums">
              {strengthConnected ? '–' : String(data.strength ?? 0.75)}
            </span>
          </div>
          <Slider
            value={(data.strength as number) ?? 0.75}
            onChange={(v: number) => updateNodeData(id, { strength: v })}
            min={0}
            max={1}
            step={0.05}
            disabled={strengthConnected}
            className={cn('nodrag nowheel w-full', strengthConnected && 'opacity-50')}
          />
        </div>

        {/* Seed */}
        <div className="relative w-full space-y-1.5">
          <ParameterHandle id="seed" dataType="BIGINT" />
          <Label className="text-xs text-text-muted">SEED (-1 = random)</Label>
          <Input
            type="number"
            value={seedConnected ? '' : ((data.seed as number) ?? -1)}
            onChange={(e) => updateNodeData(id, { seed: parseInt(e.target.value) })}
            onKeyDown={(e) => e.stopPropagation()}
            placeholder={seedConnected ? 'Connected' : undefined}
            disabled={seedConnected}
            className={cn(
              'nodrag nowheel w-full h-8 text-xs bg-surface-1/50 border-overlay-0',
              seedConnected && 'opacity-50'
            )}
          />
        </div>

        {/* Sampler */}
        <div className="w-full space-y-1.5">
          <Label className="text-xs text-text-muted">SAMPLER</Label>
          <select
            value={(data.sampler as string) || 'euler_a'}
            onChange={(e) => updateNodeData(id, { sampler: e.target.value })}
            className="nodrag nowheel w-full h-8 text-xs bg-surface-1/50 border border-overlay-0 rounded-md px-2 text-text-primary"
          >
            {SAMPLERS.map((s) => (
              <option key={s.value} value={s.value}>
                {s.label}
              </option>
            ))}
          </select>
        </div>
      </div>
    </BaseNode>
  );
});

GenerateImageNode.displayName = 'GenerateImageNode';
