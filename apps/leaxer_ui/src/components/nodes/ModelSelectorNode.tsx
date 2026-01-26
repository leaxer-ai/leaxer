import { memo } from 'react';
import { Position, type NodeProps } from '@xyflow/react';
import { BaseNode } from './BaseNode';
import { useGraphStore } from '../../stores/graphStore';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

export const ModelSelectorNode = memo(({ id, data, selected }: NodeProps) => {
  const updateNodeData = useGraphStore((state) => state.updateNodeData);

  return (
    <BaseNode
      nodeId={id}
      title="Model Selector"
      customTitle={data._title as string | undefined}
      onTitleChange={(newTitle) => updateNodeData(id, { _title: newTitle })}
      selected={selected}
      handles={[
        { id: 'model', type: 'source', position: Position.Right, label: 'MODEL', dataType: 'MODEL' },
      ]}
    >
      <div className="w-full space-y-2">
        <Label className="text-xs text-text-muted">MODEL</Label>
        <Input
          type="text"
          value={(data.repo as string) ?? 'CompVis/stable-diffusion-v1-4'}
          onChange={(e) => {
            e.stopPropagation();
            updateNodeData(id, { repo: e.target.value });
          }}
          onKeyDown={(e) => e.stopPropagation()}
          onKeyUp={(e) => e.stopPropagation()}
          onMouseDown={(e) => e.stopPropagation()}
          onClick={(e) => e.stopPropagation()}
          className="nodrag nowheel nopan w-full h-8 text-xs bg-surface-1/50 border-overlay-0"
        />
        <p className="text-[10px] text-overlay-0">
          HuggingFace repo or local folder
        </p>
      </div>
    </BaseNode>
  );
});

ModelSelectorNode.displayName = 'ModelSelectorNode';
