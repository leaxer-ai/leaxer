import { memo, useCallback } from 'react';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Slider } from '@/components/ui/slider';
import { Label } from '@/components/ui/label';
import type { FieldSpec } from '@/types/nodeSpecs';

interface ParameterControlProps {
  /** Field ID (key) */
  id: string;
  /** Field specification from input_spec */
  spec: FieldSpec;
  /** Current value */
  value: unknown;
  /** Whether the field is connected (disables input) */
  connected?: boolean;
  /** Callback when value changes */
  onChange: (value: unknown) => void;
}

/**
 * Renders a single parameter control based on field spec type.
 */
const ParameterControl = memo(({
  id,
  spec,
  value,
  connected,
  onChange,
}: ParameterControlProps) => {
  const handleChange = useCallback(
    (newValue: unknown) => {
      if (!connected) {
        onChange(newValue);
      }
    },
    [connected, onChange]
  );

  // Type-specific rendering
  const fieldType = spec.type.toLowerCase();

  // Enum type - render as select dropdown
  if (fieldType === 'enum' && spec.options) {
    return (
      <select
        value={String(value ?? spec.default ?? '')}
        onChange={(e) => handleChange(e.target.value)}
        disabled={connected}
        className="nodrag w-full h-7 px-2 text-xs rounded border bg-surface-1/50 border-overlay-0 text-text disabled:opacity-50"
      >
        {spec.options.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
    );
  }

  // Boolean type - render as switch
  if (fieldType === 'boolean') {
    return (
      <div className="flex items-center gap-2">
        <Switch
          id={id}
          checked={Boolean(value ?? spec.default ?? false)}
          onCheckedChange={handleChange}
          disabled={connected}
          className="nodrag"
        />
        <Label
          htmlFor={id}
          className="text-xs text-text-muted cursor-pointer"
        >
          {spec.label}
        </Label>
      </div>
    );
  }

  // String type - render as input or textarea
  if (fieldType === 'string') {
    if (spec.multiline) {
      return (
        <Textarea
          value={connected ? '' : String(value ?? spec.default ?? '')}
          onChange={(e) => handleChange(e.target.value)}
          onKeyDown={(e) => e.stopPropagation()}
          disabled={connected}
          placeholder={connected ? spec.label : ''}
          className="nodrag nowheel w-full min-h-[60px] text-xs bg-surface-1/50 border-overlay-0 resize-none"
        />
      );
    }

    return (
      <Input
        type="text"
        value={connected ? '' : String(value ?? spec.default ?? '')}
        onChange={(e) => handleChange(e.target.value)}
        onKeyDown={(e) => e.stopPropagation()}
        disabled={connected}
        placeholder={connected ? spec.label : ''}
        className="nodrag w-full h-7 text-xs bg-surface-1/50 border-overlay-0"
      />
    );
  }

  // Integer type
  if (fieldType === 'integer') {
    // If has min/max, could use slider - but input is more flexible
    const numValue = connected ? '' : Number(value ?? spec.default ?? 0);

    return (
      <Input
        type="number"
        step={spec.step ?? 1}
        min={spec.min}
        max={spec.max}
        value={numValue}
        onChange={(e) => handleChange(parseInt(e.target.value, 10) || 0)}
        disabled={connected}
        placeholder={connected ? spec.label : ''}
        className="nodrag w-full h-7 text-xs bg-surface-1/50 border-overlay-0"
      />
    );
  }

  // Float type
  if (fieldType === 'float') {
    const numValue = connected ? '' : Number(value ?? spec.default ?? 0);

    // Check if we should use a slider
    const useSlider = spec.min !== undefined && spec.max !== undefined;

    if (useSlider && !connected) {
      return (
        <div className="w-full space-y-1">
          <div className="flex items-center justify-between">
            <span className="text-[10px] text-text-muted">{spec.label}</span>
            <span className="text-[10px] text-text-muted font-mono">
              {Number(numValue).toFixed(2)}
            </span>
          </div>
          <Slider
            value={Number(numValue)}
            onChange={(v: number) => handleChange(v)}
            min={spec.min}
            max={spec.max}
            step={spec.step ?? 0.01}
            className="nodrag w-full"
          />
        </div>
      );
    }

    return (
      <Input
        type="number"
        step={spec.step ?? 'any'}
        min={spec.min}
        max={spec.max}
        value={numValue}
        onChange={(e) => handleChange(parseFloat(e.target.value) || 0)}
        disabled={connected}
        placeholder={connected ? spec.label : ''}
        className="nodrag w-full h-7 text-xs bg-surface-1/50 border-overlay-0"
      />
    );
  }

  // BigInt type
  if (fieldType === 'bigint') {
    const numValue = connected ? '' : Number(value ?? spec.default ?? -1);

    return (
      <Input
        type="number"
        step={1}
        value={numValue}
        onChange={(e) => handleChange(parseInt(e.target.value, 10) || 0)}
        disabled={connected}
        placeholder={connected ? spec.label : ''}
        className="nodrag w-full h-7 text-xs bg-surface-1/50 border-overlay-0"
      />
    );
  }

  // Default fallback - just render as string input
  return (
    <Input
      type="text"
      value={connected ? '' : String(value ?? '')}
      onChange={(e) => handleChange(e.target.value)}
      disabled={connected}
      placeholder={connected ? spec.label : ''}
      className="nodrag w-full h-7 text-xs bg-surface-1/50 border-overlay-0"
    />
  );
});

ParameterControl.displayName = 'ParameterControl';

interface AutoParameterUIProps {
  /** Input spec from node spec */
  inputSpec: Record<string, FieldSpec>;
  /** Current node data values */
  data: Record<string, unknown>;
  /** Map of field ID to connected state */
  connectedFields?: Record<string, boolean>;
  /** Callback when a field value changes */
  onFieldChange: (fieldId: string, value: unknown) => void;
  /** Fields to exclude from rendering (e.g., those that are only inputs) */
  excludeFields?: string[];
  /** Layout mode */
  layout?: 'vertical' | 'compact';
}

/**
 * Automatically renders parameter UI controls based on the input_spec.
 *
 * @example
 * <AutoParameterUI
 *   inputSpec={spec.input_spec}
 *   data={nodeData}
 *   connectedFields={{ a: true }}
 *   onFieldChange={(field, value) => updateNodeData(nodeId, { [field]: value })}
 * />
 */
export const AutoParameterUI = memo(({
  inputSpec,
  data,
  connectedFields = {},
  onFieldChange,
  excludeFields = [],
  layout = 'vertical',
}: AutoParameterUIProps) => {
  // Filter out excluded fields and only show configurable fields
  const fields = Object.entries(inputSpec)
    .filter(([id]) => !excludeFields.includes(id))
    // Only show fields that are configurable (have UI widgets)
    .filter(([_, spec]) => {
      // Use explicit configurable flag from backend if provided
      if (spec.configurable !== undefined) {
        return spec.configurable;
      }
      // Fallback: show UI if field has a default value (backwards compatibility)
      if (spec.default !== undefined) {
        return true;
      }
      // Fallback: hide known data-only types (for nodes not yet updated with configurable flag)
      const type = spec.type.toLowerCase();
      const dataOnlyTypes = ['model', 'conditioning', 'latent', 'image', 'positive', 'negative', 'vae', 'mask', 'segs', 'detector', 'sam_model', 'any'];
      return !dataOnlyTypes.includes(type);
    });

  if (fields.length === 0) {
    return null;
  }

  const containerClass = layout === 'compact'
    ? 'w-full grid grid-cols-2 gap-2'
    : 'w-full space-y-2';

  return (
    <div className={containerClass}>
      {fields.map(([id, spec]) => {
        const showLabel = layout === 'vertical' && spec.type.toLowerCase() !== 'boolean';

        return (
          <div key={id} className={layout === 'vertical' ? 'space-y-1' : ''}>
            {showLabel && (
              <label className="text-[10px] text-text-muted block">
                {spec.label}
              </label>
            )}
            <ParameterControl
              id={id}
              spec={spec}
              value={data[id]}
              connected={connectedFields[id]}
              onChange={(value) => onFieldChange(id, value)}
            />
          </div>
        );
      })}
    </div>
  );
});

AutoParameterUI.displayName = 'AutoParameterUI';

export { ParameterControl };
