import { memo } from 'react';
import { type NodeProps } from '@xyflow/react';
import { useGraphStore } from '../../../stores/graphStore';
import { Textarea } from '@/components/ui/textarea';
import { cn } from '@/lib/utils';

export const NoteNode = memo(({ id, data, selected }: NodeProps) => {
  const updateNodeData = useGraphStore((s) => s.updateNodeData);
  const currentNode = useGraphStore((s) => s.currentNode);
  const executingNodes = useGraphStore((s) => s.executingNodes);

  // Check if this node is currently executing (includes minimum display time)
  const isExecuting = currentNode === id || !!executingNodes[id];

  return (
    <div
      className={cn(
        'relative min-w-[200px] max-w-[300px] rounded-lg',
        isExecuting && 'executing-glow'
      )}
    >
    <div
      className={cn(
        'rounded-lg p-3 transition-all duration-150',
        selected && 'ring-2 ring-warning/50'
      )}
      style={{
        backgroundColor: 'color-mix(in srgb, var(--color-warning) 15%, var(--color-surface-0))',
        border: '1px solid var(--color-warning)',
      }}
    >
      <div
        className="text-[10px] font-medium uppercase tracking-wider mb-2"
        style={{ color: 'var(--color-warning)' }}
      >
        Note
      </div>
      <Textarea
        value={(data.text as string) || ''}
        onChange={(e) => updateNodeData(id, { text: e.target.value })}
        onKeyDown={(e) => e.stopPropagation()}
        placeholder="Add a note..."
        className="nodrag nowheel min-h-[60px] text-xs bg-transparent border-none resize-none focus:ring-0 p-0"
        style={{ color: 'var(--color-text)' }}
      />
    </div>
    </div>
  );
});

NoteNode.displayName = 'NoteNode';
