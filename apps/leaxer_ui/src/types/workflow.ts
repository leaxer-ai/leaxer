import type { Node, Edge, Viewport } from '@xyflow/react';

/**
 * Leaxer Workflow Format (.lxr)
 *
 * A portable file format for saving and sharing workflows.
 */

// Serialized node format (subset of ReactFlow Node)
export interface SerializedNode {
  id: string;
  type: string;
  position: { x: number; y: number };
  data: Record<string, unknown>;
  width?: number;
  height?: number;
}

// Serialized edge format (subset of ReactFlow Edge)
export interface SerializedEdge {
  id: string;
  source: string;
  sourceHandle: string;
  target: string;
  targetHandle: string;
  type?: string;
  data?: Record<string, unknown>;
}

// Workflow metadata
export interface WorkflowMetadata {
  name: string;
  description?: string;
  created_at: string;  // ISO 8601
  modified_at: string; // ISO 8601
  tags?: string[];
}

// Graph structure within workflow
export interface WorkflowGraph {
  nodes: SerializedNode[];
  edges: SerializedEdge[];
  viewport?: { x: number; y: number; zoom: number };
}

// Requirements for validation
export interface WorkflowRequirements {
  node_types: string[];   // Required node types for validation
  models?: string[];      // Referenced model names
}

// Application info in file
export interface AppInfo {
  name: 'leaxer';
  min_version: string;  // Minimum app version to open this file
}

/**
 * The complete .lxr file format
 */
export interface LxrWorkflowFormat {
  format: 'lxr';           // Magic identifier
  format_version: string;  // Semver bound to app version (e.g., "0.1.0")

  app_info: AppInfo;

  metadata: WorkflowMetadata;

  graph: WorkflowGraph;

  requirements: WorkflowRequirements;
}

// Validation error types
export type ValidationErrorType =
  | 'missing_node'
  | 'missing_model'
  | 'version_mismatch'
  | 'invalid_format'
  | 'parse_error';

export interface ValidationError {
  type: ValidationErrorType;
  node_type?: string;
  model_name?: string;
  message: string;
  can_force_open?: boolean;
  node_id?: string;  // For associating error with specific node
}

export interface ValidationResult {
  valid: boolean;
  errors: ValidationError[];
}

// Current app version for format versioning
export const APP_VERSION = '0.1.0';
export const FORMAT_VERSION = '0.1.0';

/**
 * Create a new workflow metadata object
 */
export function createWorkflowMetadata(name: string = 'Untitled'): WorkflowMetadata {
  const now = new Date().toISOString();
  return {
    name,
    created_at: now,
    modified_at: now,
  };
}

/**
 * Keys that contain execution results (not configuration) - should not be saved
 */
const TRANSIENT_DATA_KEYS = new Set([
  // Image preview/comparison URLs (generated during execution)
  'before_url',
  'after_url',
  'preview_url',
  'image_url',
  // Execution output data
  'output',
  'outputs',
  'result',
  'results',
  // Base64 image data embedded in results
  'preview',
  'previews',
]);

/**
 * Check if a value is a base64 image object or data URL
 */
function isImageData(value: unknown): boolean {
  if (typeof value === 'string' && value.startsWith('data:image/')) {
    return true;
  }
  if (value && typeof value === 'object') {
    const obj = value as Record<string, unknown>;
    // Base64 image object: { data: "...", mime_type: "image/..." }
    if (obj.data && obj.mime_type && typeof obj.data === 'string') {
      return true;
    }
  }
  return false;
}

/**
 * Sanitize node data by removing execution results (base64 images, preview URLs, etc.)
 * This keeps workflows small and stateless - only configuration is saved
 */
function sanitizeNodeData(data: Record<string, unknown>): Record<string, unknown> {
  const sanitized: Record<string, unknown> = {};

  for (const [key, value] of Object.entries(data)) {
    // Skip transient keys
    if (TRANSIENT_DATA_KEYS.has(key)) {
      continue;
    }
    // Skip base64 image data
    if (isImageData(value)) {
      continue;
    }
    // Recursively sanitize arrays
    if (Array.isArray(value)) {
      const filtered = value.filter(item => !isImageData(item));
      if (filtered.length > 0) {
        sanitized[key] = filtered;
      }
      continue;
    }
    // Keep other values
    sanitized[key] = value;
  }

  return sanitized;
}

/**
 * Convert ReactFlow nodes to serialized format
 */
export function serializeNodes(nodes: Node[]): SerializedNode[] {
  return nodes.map((node) => {
    // Prefer measured dimensions (actual rendered size), fall back to style width/height
    const width = node.measured?.width ?? (node.style?.width as number | undefined);
    const height = node.measured?.height ?? (node.style?.height as number | undefined);

    // Sanitize data to remove execution results
    const sanitizedData = sanitizeNodeData(node.data as Record<string, unknown>);

    return {
      id: node.id,
      type: node.type || 'unknown',
      position: { x: node.position.x, y: node.position.y },
      data: sanitizedData,
      ...(width && { width }),
      ...(height && { height }),
    };
  });
}

/**
 * Convert ReactFlow edges to serialized format
 */
export function serializeEdges(edges: Edge[]): SerializedEdge[] {
  return edges.map((edge) => ({
    id: edge.id,
    source: edge.source,
    sourceHandle: edge.sourceHandle || 'output',
    target: edge.target,
    targetHandle: edge.targetHandle || 'input',
    type: edge.type,
    data: edge.data as Record<string, unknown> | undefined,
  }));
}

/**
 * Convert serialized nodes to ReactFlow format
 */
export function deserializeNodes(serialized: SerializedNode[]): Node[] {
  return serialized.map((node) => ({
    id: node.id,
    type: node.type,
    position: node.position,
    data: node.data,
    // Restore dimensions via style for ReactFlow rendering
    // Default to width: 300 if not saved (matches new node default)
    style: {
      width: node.width ?? 300,
      ...(node.height && { height: node.height }),
    },
  }));
}

/**
 * Convert serialized edges to ReactFlow format
 */
export function deserializeEdges(serialized: SerializedEdge[]): Edge[] {
  return serialized.map((edge) => ({
    id: edge.id,
    source: edge.source,
    sourceHandle: edge.sourceHandle,
    target: edge.target,
    targetHandle: edge.targetHandle,
    type: edge.type || 'colored',
    data: edge.data,
  }));
}

/**
 * Extract required node types from nodes
 */
export function extractNodeTypes(nodes: Node[]): string[] {
  const types = new Set<string>();
  nodes.forEach((node) => {
    if (node.type) {
      types.add(node.type);
    }
  });
  return Array.from(types);
}

/**
 * Extract model references from nodes
 */
export function extractModels(nodes: Node[]): string[] {
  const models = new Set<string>();
  nodes.forEach((node) => {
    // Check common model-related fields
    const data = node.data as Record<string, unknown>;
    if (data.model && typeof data.model === 'string') {
      models.add(data.model);
    }
    if (data.repo && typeof data.repo === 'string') {
      models.add(data.repo);
    }
    if (data.checkpoint && typeof data.checkpoint === 'string') {
      models.add(data.checkpoint);
    }
  });
  return Array.from(models);
}

/**
 * Create a complete .lxr workflow file object
 */
export function createLxrWorkflow(
  nodes: Node[],
  edges: Edge[],
  viewport: Viewport | undefined,
  metadata: WorkflowMetadata
): LxrWorkflowFormat {
  return {
    format: 'lxr',
    format_version: FORMAT_VERSION,
    app_info: {
      name: 'leaxer',
      min_version: APP_VERSION,
    },
    metadata: {
      ...metadata,
      modified_at: new Date().toISOString(),
    },
    graph: {
      nodes: serializeNodes(nodes),
      edges: serializeEdges(edges),
      viewport: viewport ? { x: viewport.x, y: viewport.y, zoom: viewport.zoom } : undefined,
    },
    requirements: {
      node_types: extractNodeTypes(nodes),
      models: extractModels(nodes),
    },
  };
}

/**
 * Parse and validate a .lxr file
 */
export function parseLxrWorkflow(content: string): { workflow: LxrWorkflowFormat | null; error: string | null } {
  try {
    const parsed = JSON.parse(content);

    // Validate magic identifier
    if (parsed.format !== 'lxr') {
      return { workflow: null, error: 'Invalid file format: not a .lxr workflow file' };
    }

    // Validate required fields
    if (!parsed.format_version) {
      return { workflow: null, error: 'Invalid file format: missing format_version' };
    }

    if (!parsed.graph || !Array.isArray(parsed.graph.nodes) || !Array.isArray(parsed.graph.edges)) {
      return { workflow: null, error: 'Invalid file format: missing or invalid graph data' };
    }

    if (!parsed.metadata || !parsed.metadata.name) {
      return { workflow: null, error: 'Invalid file format: missing metadata' };
    }

    return { workflow: parsed as LxrWorkflowFormat, error: null };
  } catch (e) {
    return { workflow: null, error: `Failed to parse workflow file: ${e instanceof Error ? e.message : 'Unknown error'}` };
  }
}

/**
 * Compare semantic versions
 * Returns: -1 if a < b, 0 if a == b, 1 if a > b
 */
export function compareVersions(a: string, b: string): number {
  const partsA = a.split('.').map(Number);
  const partsB = b.split('.').map(Number);

  for (let i = 0; i < Math.max(partsA.length, partsB.length); i++) {
    const numA = partsA[i] || 0;
    const numB = partsB[i] || 0;

    if (numA < numB) return -1;
    if (numA > numB) return 1;
  }

  return 0;
}

/**
 * Check if workflow version is compatible
 */
export function checkVersionCompatibility(workflowVersion: string): {
  compatible: boolean;
  warning?: string;
} {
  const comparison = compareVersions(workflowVersion, FORMAT_VERSION);

  if (comparison > 0) {
    return {
      compatible: true,
      warning: `This workflow was created with a newer version (${workflowVersion}). Some features may not work correctly.`,
    };
  }

  return { compatible: true };
}
