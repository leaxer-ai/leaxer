import { memo } from 'react';
import { Position, type NodeProps } from '@xyflow/react';
import { BaseNode } from '../BaseNode';
import { useGraphStore } from '@/stores/graphStore';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Slider } from '@/components/ui/slider';
import { Switch } from '@/components/ui/switch';
import { ParameterHandle } from '../ParameterHandle';
import { useIsHandleConnected } from '@/hooks/useHandleConnections';
import { cn } from '@/lib/utils';
import { Eye, Zap } from 'lucide-react';

export const OvisImageGenerateNode = memo(({ id, data, selected }: NodeProps) => {
  const updateNodeData = useGraphStore((state) => state.updateNodeData);

  // Check handle connections
  const stepsConnected = useIsHandleConnected(id, 'steps', 'target');
  const cfgConnected = useIsHandleConnected(id, 'cfg_scale', 'target');
  const seedConnected = useIsHandleConnected(id, 'seed', 'target');
  const flowShiftConnected = useIsHandleConnected(id, 'flow_shift', 'target');

  return (
    <BaseNode
      nodeId={id}
      title="Ovis Image Generate"
      customTitle={data._title as string | undefined}
      onTitleChange={(newTitle) => updateNodeData(id, { _title: newTitle })}
      selected={selected}
      handles={[
        { id: 'diffusion_model', type: 'target', position: Position.Left, label: 'DIFFUSION MODEL', dataType: 'STRING' },
        { id: 'vae', type: 'target', position: Position.Left, label: 'VAE', dataType: 'STRING' },
        { id: 'llm', type: 'target', position: Position.Left, label: 'LLM', dataType: 'STRING' },
        { id: 'prompt', type: 'target', position: Position.Left, label: 'PROMPT', dataType: 'STRING' },
        { id: 'negative_prompt', type: 'target', position: Position.Left, label: 'NEGATIVE PROMPT', dataType: 'STRING' },
        { id: 'width', type: 'target', position: Position.Left, label: 'WIDTH', dataType: 'INTEGER' },
        { id: 'height', type: 'target', position: Position.Left, label: 'HEIGHT', dataType: 'INTEGER' },
        { id: 'image', type: 'source', position: Position.Right, label: 'IMAGE', dataType: 'IMAGE' },
      ]}
    >
      <div className="w-full space-y-3">
        {/* Info */}
        <div className="flex items-start gap-2 p-2 bg-cyan-500/10 border border-cyan-500/30 rounded text-xs text-cyan-200">
          <Eye className="w-4 h-4 flex-shrink-0 mt-0.5" />
          <span>Ovis 2.5 image generation. Requires diffusion model, VAE, and Ovis LLM.</span>
        </div>

        {/* Model Paths */}
        <div className="w-full space-y-1.5">
          <Label className="text-xs text-text-muted">DIFFUSION MODEL PATH</Label>
          <Input
            type="text"
            value={(data.diffusion_model as string) || ''}
            onChange={(e) => updateNodeData(id, { diffusion_model: e.target.value })}
            onKeyDown={(e) => e.stopPropagation()}
            placeholder="Path to Ovis diffusion model"
            className="nodrag nowheel w-full h-8 text-xs bg-surface-1/50 border-overlay-0"
          />
        </div>

        <div className="w-full space-y-1.5">
          <Label className="text-xs text-text-muted">VAE PATH</Label>
          <Input
            type="text"
            value={(data.vae as string) || ''}
            onChange={(e) => updateNodeData(id, { vae: e.target.value })}
            onKeyDown={(e) => e.stopPropagation()}
            placeholder="Path to FLUX schnell VAE"
            className="nodrag nowheel w-full h-8 text-xs bg-surface-1/50 border-overlay-0"
          />
        </div>

        <div className="w-full space-y-1.5">
          <Label className="text-xs text-text-muted">LLM PATH</Label>
          <Input
            type="text"
            value={(data.llm as string) || ''}
            onChange={(e) => updateNodeData(id, { llm: e.target.value })}
            onKeyDown={(e) => e.stopPropagation()}
            placeholder="Path to Ovis 2.5 GGUF"
            className="nodrag nowheel w-full h-8 text-xs bg-surface-1/50 border-overlay-0"
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
              {cfgConnected ? '–' : String(data.cfg_scale ?? 5.0)}
            </span>
          </div>
          <Slider
            value={(data.cfg_scale as number) ?? 5.0}
            onChange={(v: number) => updateNodeData(id, { cfg_scale: v })}
            min={1}
            max={15}
            step={0.5}
            disabled={cfgConnected}
            className={cn('nodrag nowheel w-full', cfgConnected && 'opacity-50')}
          />
          <p className="text-[10px] text-text-muted">
            Ovis 2.5 works best with CFG 5.0
          </p>
        </div>

        {/* Flow Shift */}
        <div className="relative w-full space-y-2">
          <ParameterHandle id="flow_shift" dataType="FLOAT" />
          <div className="flex justify-between">
            <Label className="text-xs text-text-muted">FLOW SHIFT</Label>
            <span className="text-xs text-text-secondary tabular-nums">
              {flowShiftConnected ? '–' : String(data.flow_shift ?? 3.0)}
            </span>
          </div>
          <Slider
            value={(data.flow_shift as number) ?? 3.0}
            onChange={(v: number) => updateNodeData(id, { flow_shift: v })}
            min={0}
            max={10}
            step={0.1}
            disabled={flowShiftConnected}
            className={cn('nodrag nowheel w-full', flowShiftConnected && 'opacity-50')}
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

        {/* Flash Attention */}
        <div className="flex items-center justify-between p-2 bg-surface-1/30 rounded">
          <Label className="text-xs text-text-muted flex items-center gap-1.5">
            <Zap className="w-3.5 h-3.5" />
            Flash Attention
          </Label>
          <Switch
            checked={(data.diffusion_fa as boolean) ?? true}
            onCheckedChange={(checked) => updateNodeData(id, { diffusion_fa: checked })}
            className="nodrag"
          />
        </div>
      </div>
    </BaseNode>
  );
});

OvisImageGenerateNode.displayName = 'OvisImageGenerateNode';
