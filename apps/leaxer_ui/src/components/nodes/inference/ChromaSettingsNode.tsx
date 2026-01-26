import { memo } from 'react';
import { Position, type NodeProps } from '@xyflow/react';
import { BaseNode } from '../BaseNode';
import { useGraphStore } from '@/stores/graphStore';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { ParameterHandle } from '../ParameterHandle';
import { useIsHandleConnected } from '@/hooks/useHandleConnections';
import { cn } from '@/lib/utils';
import { Settings2 } from 'lucide-react';

export const ChromaSettingsNode = memo(({ id, data, selected }: NodeProps) => {
  const updateNodeData = useGraphStore((state) => state.updateNodeData);

  // Check handle connections
  const t5MaskPadConnected = useIsHandleConnected(id, 't5_mask_pad', 'target');

  return (
    <BaseNode
      nodeId={id}
      title="Chroma Settings"
      customTitle={data._title as string | undefined}
      onTitleChange={(newTitle) => updateNodeData(id, { _title: newTitle })}
      selected={selected}
      handles={[
        { id: 'chroma_settings', type: 'source', position: Position.Right, label: 'CHROMA SETTINGS', dataType: 'CHROMA_SETTINGS' },
      ]}
    >
      <div className="w-full space-y-3">
        {/* Info */}
        <div className="flex items-start gap-2 p-2 bg-orange-500/10 border border-orange-500/30 rounded text-xs text-orange-200">
          <Settings2 className="w-4 h-4 flex-shrink-0 mt-0.5" />
          <span>Configure mask settings for Chroma/Chroma1-Radiance models.</span>
        </div>

        {/* Disable DiT Mask */}
        <div className="flex items-center justify-between p-2 bg-surface-1/30 rounded">
          <Label className="text-xs text-text-muted">Disable DiT Mask</Label>
          <Switch
            checked={(data.disable_dit_mask as boolean) || false}
            onCheckedChange={(checked) => updateNodeData(id, { disable_dit_mask: checked })}
            className="nodrag"
          />
        </div>

        {/* Enable T5 Mask */}
        <div className="flex items-center justify-between p-2 bg-surface-1/30 rounded">
          <Label className="text-xs text-text-muted">Enable T5 Mask</Label>
          <Switch
            checked={(data.enable_t5_mask as boolean) || false}
            onCheckedChange={(checked) => updateNodeData(id, { enable_t5_mask: checked })}
            className="nodrag"
          />
        </div>

        {/* T5 Mask Pad */}
        <div className="relative w-full space-y-1.5">
          <ParameterHandle id="t5_mask_pad" dataType="INTEGER" />
          <Label className="text-xs text-text-muted">T5 MASK PAD</Label>
          <Input
            type="number"
            value={t5MaskPadConnected ? '' : ((data.t5_mask_pad as number) ?? 0)}
            onChange={(e) => updateNodeData(id, { t5_mask_pad: parseInt(e.target.value) || 0 })}
            onKeyDown={(e) => e.stopPropagation()}
            placeholder={t5MaskPadConnected ? 'Connected' : '0'}
            disabled={t5MaskPadConnected}
            min={0}
            max={256}
            className={cn(
              'nodrag nowheel w-full h-8 text-xs bg-surface-1/50 border-overlay-0',
              t5MaskPadConnected && 'opacity-50'
            )}
          />
          <p className="text-[10px] text-text-muted">
            Padding value for T5 encoder mask
          </p>
        </div>
      </div>
    </BaseNode>
  );
});

ChromaSettingsNode.displayName = 'ChromaSettingsNode';
