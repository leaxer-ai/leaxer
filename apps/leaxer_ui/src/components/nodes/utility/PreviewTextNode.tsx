import { memo } from 'react';
import { Position, type NodeProps } from '@xyflow/react';
import { BaseNode } from '../BaseNode';
import { useGraphStore } from '../../../stores/graphStore';

export const PreviewTextNode = memo(({ id, data, selected }: NodeProps) => {
  const updateNodeData = useGraphStore((s) => s.updateNodeData);
  const preview = data._preview as string | undefined;

  return (
    <BaseNode
      nodeId={id}
      title="Preview Text"
      customTitle={data._title as string | undefined}
      onTitleChange={(newTitle) => updateNodeData(id, { _title: newTitle })}
      selected={selected}
      handles={[
        { id: 'text', type: 'target', position: Position.Left, label: 'TEXT', dataType: 'STRING' },
      ]}
    >
      <div
        className="min-h-[60px] max-h-[150px] overflow-auto rounded p-2 text-xs font-mono whitespace-pre-wrap break-words"
        style={{
          backgroundColor: 'var(--color-mantle)',
          color: 'var(--color-text)',
        }}
      >
        {preview || (
          <span style={{ color: 'var(--color-text-muted)' }}>
            Connect text input...
          </span>
        )}
      </div>
    </BaseNode>
  );
});

PreviewTextNode.displayName = 'PreviewTextNode';
