/**
 * Type definitions for node specifications from the backend API.
 */

export interface EnumOption {
  value: string;
  label: string;
}

export interface FieldSpec {
  type: string;
  label: string;
  default?: unknown;
  min?: number;
  max?: number;
  step?: number;
  multiline?: boolean;
  options?: EnumOption[];
  /** Whether this field should show a UI widget (true) or is input-only (false). Defaults to true if has default. */
  configurable?: boolean;
  /** Placeholder text for the input */
  placeholder?: string;
  /** Description/help text for the field */
  description?: string;
}

export interface NodeSpec {
  type: string;
  label: string;
  category: string;
  category_path: string[];
  description: string;
  input_spec: Record<string, FieldSpec>;
  output_spec: Record<string, FieldSpec>;
  default_config: Record<string, unknown>;
  ui_component: 'auto' | { custom: string };
  source: 'builtin' | 'custom';
}

export interface NodeStats {
  total: number;
  builtin: number;
  custom: number;
  categories: number;
}

export interface NodesApiResponse {
  nodes: NodeSpec[];
  stats: NodeStats;
}

export interface HandleInfo {
  id: string;
  type: 'source' | 'target';
  dataType: string;
  label: string;
}

export interface NodeItemWithHandles extends NodeSpec {
  handles: HandleInfo[];
}

/**
 * Convert a node spec to include handle information for the command palette
 */
export function nodeSpecToHandles(spec: NodeSpec): HandleInfo[] {
  const handles: HandleInfo[] = [];

  // Input handles (targets)
  for (const [id, field] of Object.entries(spec.input_spec)) {
    handles.push({
      id,
      type: 'target',
      dataType: field.type.toUpperCase(),
      label: field.label,
    });
  }

  // Output handles (sources)
  for (const [id, field] of Object.entries(spec.output_spec)) {
    handles.push({
      id,
      type: 'source',
      dataType: field.type.toUpperCase(),
      label: field.label,
    });
  }

  return handles;
}

/**
 * Build handle data types map from specs (replaces HANDLE_DATA_TYPES)
 */
export function buildHandleDataTypes(specs: NodeSpec[]): Record<string, Record<string, string>> {
  const result: Record<string, Record<string, string>> = {};

  for (const spec of specs) {
    const handles: Record<string, string> = {};

    for (const [id, field] of Object.entries(spec.input_spec)) {
      handles[id] = field.type.toUpperCase();
    }

    for (const [id, field] of Object.entries(spec.output_spec)) {
      handles[id] = field.type.toUpperCase();
    }

    result[spec.type] = handles;
  }

  return result;
}
