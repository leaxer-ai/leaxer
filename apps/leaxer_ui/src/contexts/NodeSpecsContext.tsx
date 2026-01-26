import { createContext, useContext, useMemo, type ReactNode } from 'react';
import { useNodeSpecs } from '@/hooks/useNodeSpecs';
import type {
  NodeSpec,
  NodeStats,
  NodeItemWithHandles,
} from '@/types/nodeSpecs';
import { nodeSpecToHandles, buildHandleDataTypes } from '@/types/nodeSpecs';

interface NodeSpecsContextValue {
  /** All node specifications */
  specs: NodeSpec[];
  /** Map of type to spec for O(1) lookup */
  specsMap: Map<string, NodeSpec>;
  /** Statistics about loaded nodes */
  stats: NodeStats | null;
  /** Loading state */
  loading: boolean;
  /** Error message */
  error: string | null;

  // Helper functions

  /** Get spec for a node type */
  getSpec: (type: string) => NodeSpec | undefined;
  /** Get default data for a node type (from default_config) */
  getDefaultData: (type: string) => Record<string, unknown>;
  /** Get data type for a handle on a node */
  getHandleDataType: (nodeType: string, handleId: string) => string | undefined;
  /** Get all nodes with handle info (for command palette) */
  getNodesWithHandles: () => NodeItemWithHandles[];
  /** Get handle data types map (replaces HANDLE_DATA_TYPES) */
  handleDataTypes: Record<string, Record<string, string>>;

  // Actions

  /** Refetch specs from backend */
  refetch: () => Promise<void>;
  /** Reload custom nodes */
  reloadCustomNodes: () => Promise<void>;
}

const NodeSpecsContext = createContext<NodeSpecsContextValue | null>(null);

interface NodeSpecsProviderProps {
  children: ReactNode;
  /** Base URL for API calls */
  baseUrl?: string;
}

export function NodeSpecsProvider({ children, baseUrl }: NodeSpecsProviderProps) {
  const {
    specs,
    specsMap,
    stats,
    loading,
    error,
    refetch,
    reloadCustomNodes,
  } = useNodeSpecs({ baseUrl });

  // Memoize helper functions
  const getSpec = useMemo(() => {
    return (type: string) => specsMap.get(type);
  }, [specsMap]);

  const getDefaultData = useMemo(() => {
    return (type: string): Record<string, unknown> => {
      const spec = specsMap.get(type);
      if (!spec) return {};

      // Return the default_config computed by the backend
      return { ...spec.default_config };
    };
  }, [specsMap]);

  const getHandleDataType = useMemo(() => {
    return (nodeType: string, handleId: string): string | undefined => {
      const spec = specsMap.get(nodeType);
      if (!spec) return undefined;

      // Check input spec first
      const inputField = spec.input_spec[handleId];
      if (inputField) {
        return inputField.type.toUpperCase();
      }

      // Then check output spec
      const outputField = spec.output_spec[handleId];
      if (outputField) {
        return outputField.type.toUpperCase();
      }

      return undefined;
    };
  }, [specsMap]);

  const getNodesWithHandles = useMemo(() => {
    return (): NodeItemWithHandles[] => {
      return specs.map((spec) => ({
        ...spec,
        handles: nodeSpecToHandles(spec),
      }));
    };
  }, [specs]);

  const handleDataTypes = useMemo(() => {
    return buildHandleDataTypes(specs);
  }, [specs]);

  const value: NodeSpecsContextValue = useMemo(
    () => ({
      specs,
      specsMap,
      stats,
      loading,
      error,
      getSpec,
      getDefaultData,
      getHandleDataType,
      getNodesWithHandles,
      handleDataTypes,
      refetch,
      reloadCustomNodes,
    }),
    [
      specs,
      specsMap,
      stats,
      loading,
      error,
      getSpec,
      getDefaultData,
      getHandleDataType,
      getNodesWithHandles,
      handleDataTypes,
      refetch,
      reloadCustomNodes,
    ]
  );

  return (
    <NodeSpecsContext.Provider value={value}>
      {children}
    </NodeSpecsContext.Provider>
  );
}

/**
 * Hook to access node specs context.
 * Must be used within a NodeSpecsProvider.
 *
 * @example
 * const { getSpec, getDefaultData, specs } = useNodeSpecsContext();
 *
 * // Get spec for a specific node
 * const mathSpec = getSpec('MathOp');
 *
 * // Get default data for creating a new node
 * const defaults = getDefaultData('MathOp'); // { a: 0, b: 0, operation: 'add' }
 */
// eslint-disable-next-line react-refresh/only-export-components
export function useNodeSpecsContext(): NodeSpecsContextValue {
  const context = useContext(NodeSpecsContext);
  if (!context) {
    throw new Error('useNodeSpecsContext must be used within a NodeSpecsProvider');
  }
  return context;
}

/**
 * Optional hook that returns null if outside provider (useful for gradual migration)
 */
// eslint-disable-next-line react-refresh/only-export-components
export function useNodeSpecsContextOptional(): NodeSpecsContextValue | null {
  return useContext(NodeSpecsContext);
}
