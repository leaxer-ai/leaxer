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

export const GenerateVideoNode = memo(({ id, data, selected }: NodeProps) => {
  const updateNodeData = useGraphStore((state) => state.updateNodeData);

  // Check handle connections
  const framesConnected = useIsHandleConnected(id, 'video_frames', 'target');
  const fpsConnected = useIsHandleConnected(id, 'fps', 'target');
  const flowShiftConnected = useIsHandleConnected(id, 'flow_shift', 'target');
  const vaceStrengthConnected = useIsHandleConnected(id, 'vace_strength', 'target');
  const stepsConnected = useIsHandleConnected(id, 'steps', 'target');
  const cfgConnected = useIsHandleConnected(id, 'cfg_scale', 'target');
  const seedConnected = useIsHandleConnected(id, 'seed', 'target');

  return (
    <BaseNode
      nodeId={id}
      title="Generate Video"
      customTitle={data._title as string | undefined}
      onTitleChange={(newTitle) => updateNodeData(id, { _title: newTitle })}
      selected={selected}
      handles={[
        { id: 'model', type: 'target', position: Position.Left, label: 'MODEL', dataType: 'MODEL' },
        { id: 'init_image', type: 'target', position: Position.Left, label: 'INIT IMAGE', dataType: 'IMAGE' },
        { id: 'end_image', type: 'target', position: Position.Left, label: 'END IMAGE', dataType: 'IMAGE' },
        { id: 'prompt', type: 'target', position: Position.Left, label: 'PROMPT', dataType: 'STRING' },
        { id: 'negative_prompt', type: 'target', position: Position.Left, label: 'NEGATIVE PROMPT', dataType: 'STRING' },
        { id: 'width', type: 'target', position: Position.Left, label: 'WIDTH', dataType: 'INTEGER' },
        { id: 'height', type: 'target', position: Position.Left, label: 'HEIGHT', dataType: 'INTEGER' },
        { id: 'video', type: 'source', position: Position.Right, label: 'VIDEO', dataType: 'VIDEO' },
      ]}
    >
      <div className="w-full space-y-3">
        {/* Video Frames */}
        <div className="relative w-full space-y-2">
          <ParameterHandle id="video_frames" dataType="INTEGER" />
          <div className="flex justify-between">
            <Label className="text-xs text-text-muted">VIDEO FRAMES</Label>
            <span className="text-xs text-text-secondary tabular-nums">
              {framesConnected ? '–' : String(data.video_frames ?? 17)}
            </span>
          </div>
          <Slider
            value={(data.video_frames as number) || 17}
            onChange={(v: number) => updateNodeData(id, { video_frames: v })}
            min={1}
            max={33}
            step={1}
            disabled={framesConnected}
            className={cn('nodrag nowheel w-full', framesConnected && 'opacity-50')}
          />
        </div>

        {/* FPS */}
        <div className="relative w-full space-y-2">
          <ParameterHandle id="fps" dataType="INTEGER" />
          <div className="flex justify-between">
            <Label className="text-xs text-text-muted">FPS</Label>
            <span className="text-xs text-text-secondary tabular-nums">
              {fpsConnected ? '–' : String(data.fps ?? 24)}
            </span>
          </div>
          <Slider
            value={(data.fps as number) || 24}
            onChange={(v: number) => updateNodeData(id, { fps: v })}
            min={1}
            max={60}
            step={1}
            disabled={fpsConnected}
            className={cn('nodrag nowheel w-full', fpsConnected && 'opacity-50')}
          />
        </div>

        {/* Flow Shift */}
        <div className="relative w-full space-y-2">
          <ParameterHandle id="flow_shift" dataType="FLOAT" />
          <div className="flex justify-between">
            <Label className="text-xs text-text-muted">FLOW SHIFT</Label>
            <span className="text-xs text-text-secondary tabular-nums">
              {flowShiftConnected ? '–' : String(data.flow_shift ?? 7.0)}
            </span>
          </div>
          <Slider
            value={(data.flow_shift as number) ?? 7.0}
            onChange={(v: number) => updateNodeData(id, { flow_shift: v })}
            min={0}
            max={20}
            step={0.5}
            disabled={flowShiftConnected}
            className={cn('nodrag nowheel w-full', flowShiftConnected && 'opacity-50')}
          />
        </div>

        {/* VACE Strength */}
        <div className="relative w-full space-y-2">
          <ParameterHandle id="vace_strength" dataType="FLOAT" />
          <div className="flex justify-between">
            <Label className="text-xs text-text-muted">VACE STRENGTH</Label>
            <span className="text-xs text-text-secondary tabular-nums">
              {vaceStrengthConnected ? '–' : String(data.vace_strength ?? 1.0)}
            </span>
          </div>
          <Slider
            value={(data.vace_strength as number) ?? 1.0}
            onChange={(v: number) => updateNodeData(id, { vace_strength: v })}
            min={0}
            max={2}
            step={0.1}
            disabled={vaceStrengthConnected}
            className={cn('nodrag nowheel w-full', vaceStrengthConnected && 'opacity-50')}
          />
        </div>

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

        {/* CLIP Vision Path */}
        <div className="w-full space-y-1.5">
          <Label className="text-xs text-text-muted">CLIP VISION PATH</Label>
          <Input
            type="text"
            value={(data.clip_vision as string) || ''}
            onChange={(e) => updateNodeData(id, { clip_vision: e.target.value })}
            onKeyDown={(e) => e.stopPropagation()}
            placeholder="Optional: path to CLIP vision model"
            className="nodrag nowheel w-full h-8 text-xs bg-surface-1/50 border-overlay-0"
          />
        </div>
      </div>
    </BaseNode>
  );
});

GenerateVideoNode.displayName = 'GenerateVideoNode';
