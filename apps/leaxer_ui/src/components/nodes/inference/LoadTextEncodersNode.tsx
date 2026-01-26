import { memo } from 'react';
import { Position, type NodeProps } from '@xyflow/react';
import { BaseNode } from '../BaseNode';
import { useGraphStore } from '@/stores/graphStore';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Cpu, FileType2 } from 'lucide-react';

export const LoadTextEncodersNode = memo(({ id, data, selected }: NodeProps) => {
  const updateNodeData = useGraphStore((state) => state.updateNodeData);

  return (
    <BaseNode
      nodeId={id}
      title="Load Text Encoders"
      customTitle={data._title as string | undefined}
      onTitleChange={(newTitle) => updateNodeData(id, { _title: newTitle })}
      selected={selected}
      handles={[
        { id: 'text_encoders', type: 'source', position: Position.Right, label: 'TEXT ENCODERS', dataType: 'TEXT_ENCODERS' },
      ]}
    >
      <div className="w-full space-y-3">
        {/* Info */}
        <div className="text-[10px] text-text-muted p-2 bg-surface-1/30 rounded">
          Configure text encoders for FLUX.1, FLUX.2, or SD3.5 models
        </div>

        {/* CLIP L */}
        <div className="w-full space-y-1.5">
          <Label className="text-xs text-text-muted flex items-center gap-1">
            <FileType2 className="w-3 h-3" />
            CLIP L
          </Label>
          <Input
            type="text"
            value={(data.clip_l as string) || ''}
            onChange={(e) => updateNodeData(id, { clip_l: e.target.value })}
            onKeyDown={(e) => e.stopPropagation()}
            placeholder="Path to CLIP L encoder"
            className="nodrag nowheel w-full h-8 text-xs bg-surface-1/50 border-overlay-0"
          />
        </div>

        {/* CLIP G */}
        <div className="w-full space-y-1.5">
          <Label className="text-xs text-text-muted flex items-center gap-1">
            <FileType2 className="w-3 h-3" />
            CLIP G
          </Label>
          <Input
            type="text"
            value={(data.clip_g as string) || ''}
            onChange={(e) => updateNodeData(id, { clip_g: e.target.value })}
            onKeyDown={(e) => e.stopPropagation()}
            placeholder="Path to CLIP G encoder (SD3.5)"
            className="nodrag nowheel w-full h-8 text-xs bg-surface-1/50 border-overlay-0"
          />
        </div>

        {/* T5-XXL */}
        <div className="w-full space-y-1.5">
          <Label className="text-xs text-text-muted flex items-center gap-1">
            <FileType2 className="w-3 h-3" />
            T5-XXL
          </Label>
          <Input
            type="text"
            value={(data.t5xxl as string) || ''}
            onChange={(e) => updateNodeData(id, { t5xxl: e.target.value })}
            onKeyDown={(e) => e.stopPropagation()}
            placeholder="Path to T5-XXL encoder"
            className="nodrag nowheel w-full h-8 text-xs bg-surface-1/50 border-overlay-0"
          />
        </div>

        {/* CLIP on CPU */}
        <div className="flex items-center justify-between p-2 bg-surface-1/30 rounded">
          <Label className="text-xs text-text-muted flex items-center gap-1.5">
            <Cpu className="w-3.5 h-3.5" />
            CLIP on CPU
          </Label>
          <Switch
            checked={(data.clip_on_cpu as boolean) || false}
            onCheckedChange={(checked) => updateNodeData(id, { clip_on_cpu: checked })}
            className="nodrag"
          />
        </div>
        <p className="text-[10px] text-text-muted px-1">
          Offload CLIP encoders to CPU to save VRAM
        </p>
      </div>
    </BaseNode>
  );
});

LoadTextEncodersNode.displayName = 'LoadTextEncodersNode';
