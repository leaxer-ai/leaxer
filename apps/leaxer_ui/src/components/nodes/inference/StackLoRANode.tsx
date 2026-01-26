import { memo } from 'react';
import { Position, type NodeProps } from '@xyflow/react';
import { BaseNode } from '../BaseNode';
import { useGraphStore } from '@/stores/graphStore';

export const StackLoRANode = memo(({ id, data, selected }: NodeProps) => {
  const updateNodeData = useGraphStore((state) => state.updateNodeData);

  return (
    <BaseNode
      nodeId={id}
      title="Stack LoRAs"
      customTitle={data._title as string | undefined}
      onTitleChange={(newTitle) => updateNodeData(id, { _title: newTitle })}
      selected={selected}
      handles={[
        { id: 'lora_1', type: 'target', position: Position.Left, label: 'LORA 1', dataType: 'LORA' },
        { id: 'lora_2', type: 'target', position: Position.Left, label: 'LORA 2', dataType: 'LORA' },
        { id: 'lora_3', type: 'target', position: Position.Left, label: 'LORA 3', dataType: 'LORA' },
        { id: 'lora_4', type: 'target', position: Position.Left, label: 'LORA 4', dataType: 'LORA' },
        { id: 'stacked_lora', type: 'source', position: Position.Right, label: 'STACKED LORAS', dataType: 'LORA_STACK' },
      ]}
    >
      <div className="space-y-3 min-w-[200px]">
        <div className="text-xs text-text-muted px-3 py-2 bg-surface-1/30 rounded">
          Connect multiple LoadLoRA nodes to combine their effects.
          The stacked output can be used with GenerateImage.
        </div>
        <div className="text-[10px] text-text-muted px-2">
          <div className="mb-1 font-medium">Usage:</div>
          <div>• Connect LoadLoRA outputs to inputs 1-4</div>
          <div>• At least one LoRA input is required</div>
          <div>• Connect output to GenerateImage STACKED LORAS input</div>
        </div>
      </div>
    </BaseNode>
  );
});

StackLoRANode.displayName = 'StackLoRANode';