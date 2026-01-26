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
import { Folder, AlertCircle } from 'lucide-react';

export const LoadPhotoMakerNode = memo(({ id, data, selected }: NodeProps) => {
  const updateNodeData = useGraphStore((state) => state.updateNodeData);

  // Check handle connections
  const strengthConnected = useIsHandleConnected(id, 'style_strength', 'target');

  return (
    <BaseNode
      nodeId={id}
      title="Load PhotoMaker"
      customTitle={data._title as string | undefined}
      onTitleChange={(newTitle) => updateNodeData(id, { _title: newTitle })}
      selected={selected}
      handles={[
        { id: 'photo_maker', type: 'source', position: Position.Right, label: 'PHOTOMAKER', dataType: 'PHOTO_MAKER' },
      ]}
    >
      <div className="w-full space-y-3">
        {/* Info box */}
        <div className="flex items-start gap-2 p-2 bg-amber-500/10 border border-amber-500/30 rounded text-xs text-amber-200">
          <AlertCircle className="w-4 h-4 flex-shrink-0 mt-0.5" />
          <span>PhotoMaker requires SDXL-based models for proper functionality.</span>
        </div>

        {/* Model Path */}
        <div className="w-full space-y-1.5">
          <Label className="text-xs text-text-muted">MODEL PATH</Label>
          <Input
            type="text"
            value={(data.model_path as string) || ''}
            onChange={(e) => updateNodeData(id, { model_path: e.target.value })}
            onKeyDown={(e) => e.stopPropagation()}
            placeholder="Path to PhotoMaker model file"
            className="nodrag nowheel w-full h-8 text-xs bg-surface-1/50 border-overlay-0"
          />
        </div>

        {/* ID Images Directory */}
        <div className="w-full space-y-1.5">
          <Label className="text-xs text-text-muted flex items-center gap-1">
            <Folder className="w-3 h-3" />
            ID IMAGES DIRECTORY
          </Label>
          <Input
            type="text"
            value={(data.id_images_dir as string) || ''}
            onChange={(e) => updateNodeData(id, { id_images_dir: e.target.value })}
            onKeyDown={(e) => e.stopPropagation()}
            placeholder="Directory with identity images"
            className="nodrag nowheel w-full h-8 text-xs bg-surface-1/50 border-overlay-0"
          />
          <p className="text-[10px] text-text-muted">
            Folder containing reference photos of the subject
          </p>
        </div>

        {/* Style Strength */}
        <div className="relative w-full space-y-2">
          <ParameterHandle id="style_strength" dataType="INTEGER" />
          <div className="flex justify-between">
            <Label className="text-xs text-text-muted">STYLE STRENGTH</Label>
            <span className="text-xs text-text-secondary tabular-nums">
              {strengthConnected ? '–' : `${String(data.style_strength ?? 20)}%`}
            </span>
          </div>
          <Slider
            value={(data.style_strength as number) || 20}
            onChange={(v: number) => updateNodeData(id, { style_strength: v })}
            min={0}
            max={100}
            step={5}
            disabled={strengthConnected}
            className={cn('nodrag nowheel w-full', strengthConnected && 'opacity-50')}
          />
        </div>

        {/* ID Embed Path (PhotoMaker v2) */}
        <div className="w-full space-y-1.5">
          <Label className="text-xs text-text-muted">ID EMBED PATH (v2)</Label>
          <Input
            type="text"
            value={(data.id_embed_path as string) || ''}
            onChange={(e) => updateNodeData(id, { id_embed_path: e.target.value })}
            onKeyDown={(e) => e.stopPropagation()}
            placeholder="Optional: pre-computed embedding file"
            className="nodrag nowheel w-full h-8 text-xs bg-surface-1/50 border-overlay-0"
          />
          <p className="text-[10px] text-text-muted">
            Optional: for PhotoMaker v2 pre-computed embeddings
          </p>
        </div>
      </div>
    </BaseNode>
  );
});

LoadPhotoMakerNode.displayName = 'LoadPhotoMakerNode';
