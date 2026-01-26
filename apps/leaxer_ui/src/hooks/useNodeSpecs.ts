import { useState, useEffect, useCallback, useRef } from 'react';
import type { NodeSpec, NodeStats, NodesApiResponse } from '@/types/nodeSpecs';
import { apiFetch } from '@/lib/fetch';

interface UseNodeSpecsOptions {
  /** Base URL for the API (defaults to relative /api) */
  baseUrl?: string;
  /** Whether to fetch immediately on mount */
  autoFetch?: boolean;
}

interface UseNodeSpecsResult {
  /** List of all node specifications */
  specs: NodeSpec[];
  /** Map of node type to spec for O(1) lookup */
  specsMap: Map<string, NodeSpec>;
  /** Statistics about loaded nodes */
  stats: NodeStats | null;
  /** Whether specs are currently loading */
  loading: boolean;
  /** Error message if fetch failed */
  error: string | null;
  /** Manually trigger a fetch/refetch */
  refetch: () => Promise<void>;
  /** Reload custom nodes from the backend */
  reloadCustomNodes: () => Promise<void>;
}

/**
 * Hook to fetch and manage node specifications from the backend API.
 *
 * @example
 * const { specs, specsMap, loading, error } = useNodeSpecs();
 *
 * // Get a specific node spec
 * const mathOpSpec = specsMap.get('MathOp');
 */
export function useNodeSpecs(options: UseNodeSpecsOptions = {}): UseNodeSpecsResult {
  const { baseUrl = '', autoFetch = true } = options;

  const [specs, setSpecs] = useState<NodeSpec[]>([]);
  const [specsMap, setSpecsMap] = useState<Map<string, NodeSpec>>(new Map());
  const [stats, setStats] = useState<NodeStats | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Track if component is mounted to avoid state updates after unmount
  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  const fetchSpecs = useCallback(async () => {
    if (!mountedRef.current) return;

    setLoading(true);
    setError(null);

    try {
      const response = await apiFetch(`${baseUrl}/api/nodes`);

      if (!response.ok) {
        throw new Error(`Failed to fetch nodes: ${response.status} ${response.statusText}`);
      }

      const data: NodesApiResponse = await response.json();

      if (!mountedRef.current) return;

      // Build the specs map for O(1) lookup
      const map = new Map<string, NodeSpec>();
      for (const spec of data.nodes) {
        map.set(spec.type, spec);
      }

      setSpecs(data.nodes);
      setSpecsMap(map);
      setStats(data.stats);
    } catch (err) {
      if (!mountedRef.current) return;
      setError(err instanceof Error ? err.message : 'Failed to fetch node specs');
    } finally {
      if (mountedRef.current) {
        setLoading(false);
      }
    }
  }, [baseUrl]);

  const reloadCustomNodes = useCallback(async () => {
    if (!mountedRef.current) return;

    try {
      const response = await apiFetch(`${baseUrl}/api/nodes/reload`, {
        method: 'POST',
      });

      if (!response.ok) {
        throw new Error(`Failed to reload: ${response.status} ${response.statusText}`);
      }

      // Refetch all specs after reload
      await fetchSpecs();
    } catch (err) {
      if (!mountedRef.current) return;
      setError(err instanceof Error ? err.message : 'Failed to reload custom nodes');
    }
  }, [baseUrl, fetchSpecs]);

  // Auto-fetch on mount if enabled
  useEffect(() => {
    if (autoFetch) {
      fetchSpecs();
    }
  }, [autoFetch, fetchSpecs]);

  return {
    specs,
    specsMap,
    stats,
    loading,
    error,
    refetch: fetchSpecs,
    reloadCustomNodes,
  };
}
