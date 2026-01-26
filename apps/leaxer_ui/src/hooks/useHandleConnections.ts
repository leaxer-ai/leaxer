import { useWorkflowStore } from '../stores/workflowStore';

// Helper selector for getting edges from active tab
const selectActiveTabEdges = (s: ReturnType<typeof useWorkflowStore.getState>) => {
  const tabId = s.activeTabId || s.tabs[0]?.id;
  const tab = s.tabs.find((t) => t.id === tabId);
  return tab?.edges ?? [];
};

/**
 * Hook to check if a specific handle on a node is connected
 */
export function useIsHandleConnected(nodeId: string, handleId: string, handleType: 'source' | 'target'): boolean {
  const edges = useWorkflowStore(selectActiveTabEdges);

  if (handleType === 'target') {
    return edges.some((edge) => edge.target === nodeId && edge.targetHandle === handleId);
  } else {
    return edges.some((edge) => edge.source === nodeId && edge.sourceHandle === handleId);
  }
}

/**
 * Hook to get all connected handles for a node
 */
export function useConnectedHandles(nodeId: string): { targets: string[]; sources: string[] } {
  const edges = useWorkflowStore(selectActiveTabEdges);

  const targets = edges
    .filter((edge) => edge.target === nodeId)
    .map((edge) => edge.targetHandle as string);

  const sources = edges
    .filter((edge) => edge.source === nodeId)
    .map((edge) => edge.sourceHandle as string);

  return { targets, sources };
}
