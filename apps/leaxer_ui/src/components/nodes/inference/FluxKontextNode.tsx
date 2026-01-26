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
import { Image } from 'lucide-react';

export const FluxKontextNode = memo(({ id, data, selected }: NodeProps) => {
  const updateNodeData = useGraphStore((state) => state.updateNodeData);

  // Check handle connections
  const stepsConnected = useIsHandleConnected(id, 'steps', 'target');
  const cfgConnected = useIsHandleConnected(id, 'cfg_scale', 'target');
  const seedConnected = useIsHandleConnected(id, 'seed', 'target');

  return (
    <BaseNode
      nodeId={id}
      title="FLUX Kontext"
      customTitle={data._title as string | undefined}
      onTitleChange={(newTitle) => updateNodeData(id, { _title: newTitle })}
      selected={selected}
      handles={[
        { id: 'model', type: 'target', position: Position.Left, label: 'MODEL', dataType: 'MODEL' },
        { id: 'ref_image', type: 'target', position: Position.Left, label: 'REFERENCE IMAGE', dataType: 'IMAGE' },
        { id: 'text_encoders', type: 'target', position: Position.Left, label: 'TEXT ENCODERS', dataType: 'TEXT_ENCODERS' },
        { id: 'prompt', type: 'target', position: Position.Left, label: 'PROMPT', dataType: 'STRING' },
        { id: 'negative_prompt', type: 'target', position: Position.Left, label: 'NEGATIVE PROMPT', dataType: 'STRING' },
        { id: 'width', type: 'target', position: Position.Left, label: 'WIDTH', dataType: 'INTEGER' },
        { id: 'height', type: 'target', position: Position.Left, label: 'HEIGHT', dataType: 'INTEGER' },
        { id: 'image', type: 'source', position: Position.Right, label: 'IMAGE', dataType: 'IMAGE' },
      ]}
    >
      <div className="w-full space-y-3">
        {/* Info */}
        <div className="flex items-start gap-2 p-2 bg-blue-500/10 border border-blue-500/30 rounded text-xs text-blue-200">
          <Image className="w-4 h-4 flex-shrink-0 mt-0.5" />
          <span>FLUX.1-Kontext for context-aware image editing. Connect a reference image.</span>
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
            max={100}
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
              {cfgConnected ? '–' : String(data.cfg_scale ?? 1.0)}
            </span>
          </div>
          <Slider
            value={(data.cfg_scale as number) ?? 1.0}
            onChange={(v: number) => updateNodeData(id, { cfg_scale: v })}
            min={1}
            max={10}
            step={0.1}
            disabled={cfgConnected}
            className={cn('nodrag nowheel w-full', cfgConnected && 'opacity-50')}
          />
          <p className="text-[10px] text-text-muted">
            FLUX Kontext works best with low CFG (1.0-3.0)
          </p>
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
      </div>
    </BaseNode>
  );
});

FluxKontextNode.displayName = 'FluxKontextNode';
