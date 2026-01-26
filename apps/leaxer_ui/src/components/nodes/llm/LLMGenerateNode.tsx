import { memo } from 'react';
import { Position, type NodeProps } from '@xyflow/react';
import { BaseNode } from '../BaseNode';
import { useGraphStore } from '@/stores/graphStore';
import { Label } from '@/components/ui/label';
import { Slider } from '@/components/ui/slider';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';

export const LLMGenerateNode = memo(({ id, data, selected }: NodeProps) => {
  const updateNodeData = useGraphStore((state) => state.updateNodeData);

  return (
    <BaseNode
      nodeId={id}
      title="LLM Generate"
      customTitle={data._title as string | undefined}
      onTitleChange={(newTitle) => updateNodeData(id, { _title: newTitle })}
      selected={selected}
      handles={[
        { id: 'llm', type: 'target', position: Position.Left, label: 'LLM', dataType: 'LLM' },
        { id: 'text', type: 'source', position: Position.Right, label: 'TEXT', dataType: 'STRING' },
      ]}
    >
      <div className="space-y-3 min-w-[280px]">
        {/* Prompt textarea */}
        <div className="space-y-1.5">
          <Label className="text-xs text-text-muted">PROMPT</Label>
          <Textarea
            value={(data.prompt as string) || ''}
            onChange={(e) => updateNodeData(id, { prompt: e.target.value })}
            placeholder="Enter your text generation prompt..."
            className="nodrag nowheel text-xs min-h-[60px] max-h-[120px] resize-none"
            rows={3}
          />
        </div>

        {/* Max Tokens slider */}
        <div className="w-full space-y-2">
          <div className="flex justify-between">
            <Label className="text-xs text-text-muted">MAX TOKENS</Label>
            <span className="text-xs text-text-secondary tabular-nums">
              {(data.max_tokens as number) ?? 512}
            </span>
          </div>
          <Slider
            value={(data.max_tokens as number) ?? 512}
            onChange={(v: number) => updateNodeData(id, { max_tokens: v })}
            min={1}
            max={4096}
            step={16}
            className="nodrag nowheel w-full"
          />
        </div>

        {/* Temperature slider */}
        <div className="w-full space-y-2">
          <div className="flex justify-between">
            <Label className="text-xs text-text-muted">TEMPERATURE</Label>
            <span className="text-xs text-text-secondary tabular-nums">
              {((data.temperature as number) ?? 0.7).toFixed(1)}
            </span>
          </div>
          <Slider
            value={(data.temperature as number) ?? 0.7}
            onChange={(v: number) => updateNodeData(id, { temperature: v })}
            min={0.0}
            max={2.0}
            step={0.1}
            className="nodrag nowheel w-full"
          />
          <div className="text-[10px] text-text-muted">
            0 = deterministic, higher = more creative
          </div>
        </div>

        {/* Top-P slider */}
        <div className="w-full space-y-2">
          <div className="flex justify-between">
            <Label className="text-xs text-text-muted">TOP-P</Label>
            <span className="text-xs text-text-secondary tabular-nums">
              {((data.top_p as number) ?? 0.9).toFixed(2)}
            </span>
          </div>
          <Slider
            value={(data.top_p as number) ?? 0.9}
            onChange={(v: number) => updateNodeData(id, { top_p: v })}
            min={0.0}
            max={1.0}
            step={0.05}
            className="nodrag nowheel w-full"
          />
          <div className="text-[10px] text-text-muted">
            Nucleus sampling cutoff probability
          </div>
        </div>

        {/* Top-K input */}
        <div className="w-full space-y-1.5">
          <Label className="text-xs text-text-muted">TOP-K</Label>
          <Input
            type="number"
            value={(data.top_k as number) ?? 40}
            onChange={(e) => updateNodeData(id, { top_k: parseInt(e.target.value) || 40 })}
            min={0}
            max={100}
            step={5}
            className="nodrag nowheel h-8 text-xs"
            placeholder="40"
          />
          <div className="text-[10px] text-text-muted">
            Top-K sampling cutoff (0 = disabled)
          </div>
        </div>

        {/* Stop Sequences textarea (optional) */}
        <div className="space-y-1.5">
          <Label className="text-xs text-text-muted">STOP SEQUENCES (Optional)</Label>
          <Textarea
            value={(data.stop_sequences as string) || ''}
            onChange={(e) => updateNodeData(id, { stop_sequences: e.target.value })}
            placeholder="One stop sequence per line..."
            className="nodrag nowheel text-xs min-h-[40px] max-h-[80px] resize-none"
            rows={2}
          />
          <div className="text-[10px] text-text-muted">
            Stop sequences separated by newlines
          </div>
        </div>
      </div>
    </BaseNode>
  );
});

LLMGenerateNode.displayName = 'LLMGenerateNode';