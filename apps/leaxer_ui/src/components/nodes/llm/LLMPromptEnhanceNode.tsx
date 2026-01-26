import { memo } from 'react';
import { Position, type NodeProps } from '@xyflow/react';
import { BaseNode } from '../BaseNode';
import { useGraphStore } from '@/stores/graphStore';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';

const STYLE_OPTIONS = [
  { value: 'photorealistic', label: 'Photorealistic' },
  { value: 'artistic', label: 'Artistic' },
  { value: 'anime', label: 'Anime' },
  { value: 'abstract', label: 'Abstract' },
];

export const LLMPromptEnhanceNode = memo(({ id, data, selected }: NodeProps) => {
  const updateNodeData = useGraphStore((state) => state.updateNodeData);

  return (
    <BaseNode
      nodeId={id}
      title="LLM Prompt Enhance"
      customTitle={data._title as string | undefined}
      onTitleChange={(newTitle) => updateNodeData(id, { _title: newTitle })}
      selected={selected}
      handles={[
        { id: 'llm', type: 'target', position: Position.Left, label: 'LLM', dataType: 'LLM' },
        { id: 'enhanced_prompt', type: 'source', position: Position.Right, label: 'ENHANCED PROMPT', dataType: 'STRING' },
      ]}
    >
      <div className="space-y-3 min-w-[280px]">
        {/* Basic Prompt textarea */}
        <div className="space-y-1.5">
          <Label className="text-xs text-text-muted">BASIC PROMPT</Label>
          <Textarea
            value={(data.basic_prompt as string) || ''}
            onChange={(e) => updateNodeData(id, { basic_prompt: e.target.value })}
            placeholder="Enter a simple description to enhance..."
            className="nodrag nowheel text-xs min-h-[60px] max-h-[120px] resize-none"
            rows={3}
          />
          <div className="text-[10px] text-text-muted">
            Simple description to transform into detailed prompt
          </div>
        </div>

        {/* Style dropdown */}
        <div className="space-y-1.5">
          <Label className="text-xs text-text-muted">STYLE</Label>
          <select
            value={(data.style as string) || 'photorealistic'}
            onChange={(e) => updateNodeData(id, { style: e.target.value })}
            className="nodrag nowheel w-full h-9 text-xs bg-surface-1/50 border border-overlay-0 rounded-md px-2 text-text-primary"
          >
            {STYLE_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
          <div className="text-[10px] text-text-muted">
            Target style for the enhanced prompt
          </div>
        </div>

        {/* Style descriptions for educational purposes */}
        <div className="text-[10px] text-text-muted space-y-1 p-2 bg-surface-1/30 rounded">
          {((data.style as string) || 'photorealistic') === 'photorealistic' && (
            <div>
              <span className="text-text-secondary font-medium">Photorealistic:</span> Focuses on camera settings, lighting, and technical photography terms
            </div>
          )}
          {((data.style as string) || 'photorealistic') === 'artistic' && (
            <div>
              <span className="text-text-secondary font-medium">Artistic:</span> Emphasizes composition, art movements, and creative visual elements
            </div>
          )}
          {((data.style as string) || 'photorealistic') === 'anime' && (
            <div>
              <span className="text-text-secondary font-medium">Anime:</span> Focuses on manga art style with vibrant colors and expressive characteristics
            </div>
          )}
          {((data.style as string) || 'photorealistic') === 'abstract' && (
            <div>
              <span className="text-text-secondary font-medium">Abstract:</span> Emphasizes conceptual elements, geometric forms, and non-representational art
            </div>
          )}
        </div>
      </div>
    </BaseNode>
  );
});

LLMPromptEnhanceNode.displayName = 'LLMPromptEnhanceNode';