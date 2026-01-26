import { memo, useCallback, useMemo, useEffect, type ComponentType } from 'react';
import { Position, useUpdateNodeInternals, type NodeProps } from '@xyflow/react';
import { BaseNode, type HandleConfig } from './BaseNode';
import { AutoParameterUI } from './AutoParameterUI';
import { useNodeSpecsContextOptional } from '@/contexts/NodeSpecsContext';
import { useGraphStore } from '@/stores/graphStore';
import { useWorkflowStore } from '@/stores/workflowStore';
import type { NodeSpec, FieldSpec } from '@/types/nodeSpecs';
import { createLogger } from '@/lib/logger';

const log = createLogger('NodeFactory');

// Track which unknown node types have been warned about to avoid log spam
// Used by both AutoNodeWithConnections and getNodeComponent
const warnedUnknownTypes = new Set<string>();

// Custom UI components that override auto-generation
import { PreviewImageNode } from './PreviewImageNode';
import { PreviewTextNode } from './utility/PreviewTextNode';
import { NoteNode } from './utility/NoteNode';
import { ModelSelectorNode } from './ModelSelectorNode';
import { GenerateImageNode } from './inference/GenerateImageNode';
import { LoadModelNode } from './inference/LoadModelNode';
import { LoadImageNode } from './io/LoadImageNode';
import { CompareImageNode } from './image/CompareImageNode';
import { LoadLoRANode } from './inference/LoadLoRANode';
import { StackLoRANode } from './inference/StackLoRANode';
import { LoadControlNetNode } from './inference/LoadControlNetNode';
import { LoadVAENode } from './inference/LoadVAENode';
import { LoadLLMNode, LLMGenerateNode, LLMPromptEnhanceNode } from './llm';
import { GenerateVideoNode } from './inference/GenerateVideoNode';
import { LoadPhotoMakerNode } from './inference/LoadPhotoMakerNode';
import { LoadTextEncodersNode } from './inference/LoadTextEncodersNode';
import { FluxKontextNode } from './inference/FluxKontextNode';
import { QwenImageGenerateNode } from './inference/QwenImageGenerateNode';
import { QwenImageEditNode } from './inference/QwenImageEditNode';
import { ChromaSettingsNode } from './inference/ChromaSettingsNode';
import { CacheSettingsNode } from './inference/CacheSettingsNode';
import { SamplerSettingsNode } from './inference/SamplerSettingsNode';
import { ZImageGenerateNode } from './inference/ZImageGenerateNode';
import { OvisImageGenerateNode } from './inference/OvisImageGenerateNode';
import { GroupNode } from './GroupNode';

/**
 * Registry of custom UI components that override the auto-generated UI.
 * Key is the component name from ui_component: {:custom, "name"}
 */
const CUSTOM_COMPONENTS: Record<string, ComponentType<NodeProps>> = {
  PreviewImageNode,
  PreviewTextNode,
  NoteNode,
  ModelSelectorNode,
  GenerateImageNode,
  GenerateVideoNode,
  LoadModelNode,
  LoadImageNode,
  CompareImageNode,
  LoadLoRANode,
  StackLoRANode,
  LoadControlNetNode,
  LoadVAENode,
  LoadPhotoMakerNode,
  LoadTextEncodersNode,
  FluxKontextNode,
  QwenImageGenerateNode,
  QwenImageEditNode,
  ChromaSettingsNode,
  CacheSettingsNode,
  SamplerSettingsNode,
  ZImageGenerateNode,
  OvisImageGenerateNode,
  LoadLLMNode,
  LLMGenerateNode,
  LLMPromptEnhanceNode,
  GroupNode,
};

/**
 * Build handles configuration from input/output specs.
 */
function buildHandles(
  inputSpec: Record<string, FieldSpec>,
  outputSpec: Record<string, FieldSpec>
): HandleConfig[] {
  const handles: HandleConfig[] = [];

  // Input handles
  for (const [id, field] of Object.entries(inputSpec)) {
    handles.push({
      id,
      type: 'target',
      position: Position.Left,
      label: field.label,
      dataType: field.type.toUpperCase(),
    });
  }

  // Output handles
  for (const [id, field] of Object.entries(outputSpec)) {
    handles.push({
      id,
      type: 'source',
      position: Position.Right,
      label: field.label,
      dataType: field.type.toUpperCase(),
    });
  }

  return handles;
}

interface FactoryNodeProps extends NodeProps {
  /** Node specification (injected by factory) */
  spec?: NodeSpec;
}

/**
 * Auto-generated node component based on backend spec.
 * Uses AutoParameterUI for rendering controls.
 */
const AutoNode = memo(({ id, data, selected, spec }: FactoryNodeProps) => {
  const updateNodeData = useGraphStore((s) => s.updateNodeData);
  const currentNode = useGraphStore((s) => s.currentNode);

  const isExecuting = currentNode === id;

  // Build handles from spec
  const handles = useMemo(() => {
    if (!spec) return [];
    return buildHandles(spec.input_spec, spec.output_spec);
  }, [spec]);

  // Track which input fields are connected
  // We need to check each input handle
  const connectedFields = useMemo(() => {
    const result: Record<string, boolean> = {};
    if (!spec) return result;

    for (const key of Object.keys(spec.input_spec)) {
      // Note: This is a placeholder - actual connection checking needs useIsHandleConnected per field
      result[key] = false;
    }
    return result;
  }, [spec]);

  const handleFieldChange = useCallback(
    (fieldId: string, value: unknown) => {
      updateNodeData(id, { [fieldId]: value });
    },
    [id, updateNodeData]
  );

  if (!spec) {
    return (
      <BaseNode title="Unknown Node" handles={[]} selected={selected}>
        <div className="text-xs text-error">Node spec not found</div>
      </BaseNode>
    );
  }

  return (
    <BaseNode
      nodeId={id}
      title={spec.label}
      customTitle={data._title as string | undefined}
      onTitleChange={(newTitle) => updateNodeData(id, { _title: newTitle })}
      selected={selected}
      executing={isExecuting}
      handles={handles}
      bypassed={data.bypassed as boolean | undefined}
    >
      <AutoParameterUI
        inputSpec={spec.input_spec}
        data={data as Record<string, unknown>}
        connectedFields={connectedFields}
        onFieldChange={handleFieldChange}
      />
    </BaseNode>
  );
});

AutoNode.displayName = 'AutoNode';

/**
 * Enhanced AutoNode that properly tracks handle connections.
 */
const AutoNodeWithConnections = memo(({ id, data, selected, type }: NodeProps) => {
  const specsContext = useNodeSpecsContextOptional();
  const updateNodeData = useGraphStore((s) => s.updateNodeData);
  const edges = useWorkflowStore((s) => {
    const tabId = s.activeTabId || s.tabs[0]?.id;
    const tab = s.tabs.find((t) => t.id === tabId);
    return tab?.edges ?? [];
  });
  const currentNode = useGraphStore((s) => s.currentNode);
  const executingNodes = useGraphStore((s) => s.executingNodes);

  // Check both currentNode and executingNodes for minimum display time
  const isExecuting = currentNode === id || !!executingNodes[id];

  // Get spec from context
  const spec = specsContext?.getSpec(type || '');

  // Notify React Flow when handles change (spec loads)
  // This fixes "Couldn't create edge for source handle" warnings on page refresh
  // Per https://reactflow.dev/learn/troubleshooting/common-errors#008
  const updateNodeInternals = useUpdateNodeInternals();
  useEffect(() => {
    if (spec) {
      updateNodeInternals(id);
    }
  }, [spec, id, updateNodeInternals]);

  // Build handles from spec
  const handles = useMemo(() => {
    if (!spec) return [];
    return buildHandles(spec.input_spec, spec.output_spec);
  }, [spec]);

  // Build connected fields map from edges
  const connectedFields = useMemo(() => {
    const result: Record<string, boolean> = {};
    edges
      .filter((e) => e.target === id)
      .forEach((e) => {
        if (e.targetHandle) {
          result[e.targetHandle] = true;
        }
      });
    return result;
  }, [edges, id]);

  const handleFieldChange = useCallback(
    (fieldId: string, value: unknown) => {
      updateNodeData(id, { [fieldId]: value });
    },
    [id, updateNodeData]
  );

  if (!spec) {
    // Log warning once per type to avoid spam (uses module-level Set)
    if (import.meta.env.DEV && type && !warnedUnknownTypes.has(type)) {
      warnedUnknownTypes.add(type);
      log.warn(`Node type "${type}" has no spec from backend. Check if the node type exists or is misspelled.`);
    }
    return (
      <BaseNode title={type || 'Unknown'} handles={[]} selected={selected}>
        <div className="text-xs text-error">
          Node spec not found for type: {type}
        </div>
      </BaseNode>
    );
  }

  return (
    <BaseNode
      nodeId={id}
      title={spec.label}
      customTitle={data._title as string | undefined}
      onTitleChange={(newTitle) => updateNodeData(id, { _title: newTitle })}
      selected={selected}
      executing={isExecuting}
      handles={handles}
      bypassed={data.bypassed as boolean | undefined}
    >
      <AutoParameterUI
        inputSpec={spec.input_spec}
        data={data as Record<string, unknown>}
        connectedFields={connectedFields}
        onFieldChange={handleFieldChange}
      />
    </BaseNode>
  );
});

AutoNodeWithConnections.displayName = 'AutoNodeWithConnections';

/**
 * Extract custom component name from ui_component spec.
 * Handles both Elixir tuple format (serialized as array) and object format.
 * - Elixir: {:custom, "LoadModelNode"} -> JSON: ["custom", "LoadModelNode"]
 * - Object: { custom: "LoadModelNode" }
 */
function getCustomComponentName(uiComponent: unknown): string | null {
  if (!uiComponent) return null;

  // Handle Elixir tuple serialized as array: ["custom", "LoadModelNode"]
  if (Array.isArray(uiComponent) && uiComponent[0] === 'custom' && typeof uiComponent[1] === 'string') {
    return uiComponent[1];
  }

  // Handle object format: { custom: "LoadModelNode" }
  if (typeof uiComponent === 'object' && uiComponent !== null && 'custom' in uiComponent) {
    const obj = uiComponent as { custom: string };
    if (typeof obj.custom === 'string') {
      return obj.custom;
    }
  }

  return null;
}

/**
 * Creates a node component for a given type.
 * Returns a custom component if registered, otherwise auto-generates one.
 */
// eslint-disable-next-line react-refresh/only-export-components
export function createNodeComponent(
  type: string,
  spec?: NodeSpec
): ComponentType<NodeProps> {
  // Debug logging
  log.debug(`Creating component for type: ${type}, ui_component:`, spec?.ui_component);

  // Check if there's a custom UI component registered
  const customName = getCustomComponentName(spec?.ui_component);
  if (customName) {
    log.debug(`Looking for custom component: ${customName}`);
    const CustomComponent = CUSTOM_COMPONENTS[customName];
    if (CustomComponent) {
      log.debug(`Found custom component for ${type}`);
      return CustomComponent;
    }
    log.warn(`Custom component "${customName}" not found for node type "${type}"`);
  }

  // Return the auto-generated component
  log.debug(`Using auto-generated component for ${type}`);
  return AutoNodeWithConnections;
}

/**
 * Factory that creates all node type components from specs.
 * Returns a record suitable for ReactFlow's nodeTypes prop.
 */
// eslint-disable-next-line react-refresh/only-export-components
export function createNodeTypes(specs: NodeSpec[]): Record<string, ComponentType<NodeProps>> {
  const nodeTypes: Record<string, ComponentType<NodeProps>> = {};

  for (const spec of specs) {
    nodeTypes[spec.type] = createNodeComponent(spec.type, spec);
  }

  return nodeTypes;
}

/**
 * Hook to get dynamic node types from context.
 * Falls back to empty object if context not available.
 */
// eslint-disable-next-line react-refresh/only-export-components
export function useNodeTypes(): Record<string, ComponentType<NodeProps>> {
  const specsContext = useNodeSpecsContextOptional();

  return useMemo(() => {
    if (!specsContext) return {};
    return createNodeTypes(specsContext.specs);
  }, [specsContext?.specs]);
}

/**
 * Static node types for built-in nodes with custom UIs.
 * Maps node type names (matching backend) to their React components.
 * This is the single source of truth for custom node components.
 */
// eslint-disable-next-line react-refresh/only-export-components
export const staticNodeTypes: Record<string, ComponentType<NodeProps>> = {
  // Utility nodes
  PreviewImage: PreviewImageNode,
  PreviewText: PreviewTextNode,
  Note: NoteNode,
  // Model/inference nodes
  ModelSelector: ModelSelectorNode,
  LoadModel: LoadModelNode,
  GenerateImage: GenerateImageNode,
  GenerateVideo: GenerateVideoNode,
  // Extension nodes
  LoadLoRA: LoadLoRANode,
  StackLoRA: StackLoRANode,
  LoadControlNet: LoadControlNetNode,
  LoadVAE: LoadVAENode,
  LoadPhotoMaker: LoadPhotoMakerNode,
  LoadTextEncoders: LoadTextEncodersNode,
  FluxKontext: FluxKontextNode,
  QwenImageGenerate: QwenImageGenerateNode,
  QwenImageEdit: QwenImageEditNode,
  ChromaSettings: ChromaSettingsNode,
  CacheSettings: CacheSettingsNode,
  SamplerSettings: SamplerSettingsNode,
  ZImageGenerate: ZImageGenerateNode,
  OvisImageGenerate: OvisImageGenerateNode,
  // IO nodes
  LoadImage: LoadImageNode,
  CompareImage: CompareImageNode,
  // LLM nodes
  LoadLLM: LoadLLMNode,
  LLMGenerate: LLMGenerateNode,
  LLMPromptEnhance: LLMPromptEnhanceNode,
  // Special nodes
  Group: GroupNode,
};

/**
 * Get a node component for a given type.
 * Returns the registered custom component, or AutoNodeWithConnections for dynamic types.
 * Logs a warning in development when unknown types are encountered.
 */
// eslint-disable-next-line react-refresh/only-export-components
export function getNodeComponent(type: string): ComponentType<NodeProps> {
  // Check if it's a registered static node type
  if (type in staticNodeTypes) {
    return staticNodeTypes[type as keyof typeof staticNodeTypes];
  }

  // For unknown types, log a development warning (once per type)
  if (import.meta.env.DEV && !warnedUnknownTypes.has(type)) {
    warnedUnknownTypes.add(type);
    log.debug(
      `Node type "${type}" not in staticNodeTypes, using auto-generated component. ` +
        `This is expected for backend-defined nodes without custom UI.`
    );
  }

  // Return the auto-generated component for dynamic node types
  return AutoNodeWithConnections;
}

/**
 * Creates a node types map for ReactFlow from static and dynamic types.
 * This replaces the Proxy pattern with explicit type registration.
 *
 * @param knownTypes - Array of node type strings that should be available
 *                     (typically from backend specs)
 * @returns Record suitable for ReactFlow's nodeTypes prop
 */
// eslint-disable-next-line react-refresh/only-export-components
export function createNodeTypesMap(
  knownTypes: string[] = []
): Record<string, ComponentType<NodeProps>> {
  const result: Record<string, ComponentType<NodeProps>> = { ...staticNodeTypes };

  // Add entries for any backend-defined types not in staticNodeTypes
  for (const type of knownTypes) {
    if (!(type in result)) {
      result[type] = AutoNodeWithConnections;
    }
  }

  return result;
}

/**
 * Node types map with auto-generated fallback for unknown types.
 *
 * ARCHITECTURE NOTE: This uses a Proxy to provide a fallback for unknown node types.
 * The Proxy approach is intentional here because:
 * 1. ReactFlow requires all node types to be registered upfront
 * 2. Node types can come from backend specs that load asynchronously
 * 3. Saved workflows may reference node types before specs load
 *
 * The fallback renders AutoNodeWithConnections, which:
 * - Shows "Node spec not found" if the type is truly invalid
 * - Renders correctly once specs load from backend
 *
 * To catch type mismatches, check the browser console for warnings
 * about unknown node types (development mode only).
 */
// eslint-disable-next-line react-refresh/only-export-components
export const nodeTypes = new Proxy(staticNodeTypes, {
  get(_target, prop) {
    if (typeof prop !== 'string') {
      return undefined;
    }
    return getNodeComponent(prop);
  },
  has(_target, _prop) {
    // Always return true so ReactFlow doesn't error on unknown types
    return true;
  },
  ownKeys(target) {
    return Reflect.ownKeys(target);
  },
  getOwnPropertyDescriptor(target, prop) {
    if (prop in target) {
      return Object.getOwnPropertyDescriptor(target, prop);
    }
    // Return a descriptor for dynamic properties
    return {
      enumerable: true,
      configurable: true,
      value: AutoNodeWithConnections,
    };
  },
});

export { AutoNode, AutoNodeWithConnections, CUSTOM_COMPONENTS };
