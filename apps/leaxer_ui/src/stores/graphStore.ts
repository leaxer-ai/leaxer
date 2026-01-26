import { create } from 'zustand';
import { subscribeWithSelector } from 'zustand/middleware';
import type { Node, Edge } from '@xyflow/react';
import { type WorkflowTemplate } from '../data/workflowTemplates';
import { useWorkflowStore } from './workflowStore';
import { deepClone } from '../lib/deepClone';

export interface GraphProgress {
  currentIndex: number;
  totalNodes: number;
  percentage: number;
}

export interface NodeProgress {
  currentStep: number | null;
  totalSteps: number | null;
  percentage: number;
  status: 'pending' | 'running' | 'completed' | 'error';
  phase?: 'loading' | 'inference';
}

interface ClipboardData {
  nodes: Node[];
  edges: Edge[];
}

export interface NodeError {
  code: string;
  message: string;
  field?: string;
  correlationId?: string;
}

export type JobStatus = 'completed' | 'error' | 'stopped' | null;

// Minimum time (ms) to show a node as executing for visual feedback
const MIN_EXECUTING_DISPLAY_MS = 200;

// Track active timers for cleanup
const executingTimers = new Map<string, ReturnType<typeof setTimeout>>();

interface GraphState {
  // Execution state (shared across tabs)
  isExecuting: boolean;
  currentNode: string | null;
  // Nodes that should be displayed as executing (includes min display time)
  executingNodes: Record<string, boolean>;
  lastJobStatus: JobStatus;

  // Node being renamed (for triggering edit mode from context menu)
  renamingNodeId: string | null;

  // Progress tracking (shared across tabs)
  graphProgress: GraphProgress | null;
  nodeProgress: Record<string, NodeProgress>;

  // Error tracking
  nodeErrors: Record<string, NodeError>;

  // Clipboard (global)
  clipboard: ClipboardData | null;

  // Derived from workflowStore's active tab (read-only in graphStore, workflowStore is source of truth)
  nodes: Node[];
  edges: Edge[];

  // Actions that update workflowStore (single source of truth)
  setNodes: (nodes: Node[]) => void;
  setEdges: (edges: Edge[] | ((prev: Edge[]) => Edge[])) => void;
  addNode: (node: Node) => void;
  updateNodeData: (nodeId: string, data: Record<string, unknown>) => void;
  setExecuting: (executing: boolean) => void;
  setCurrentNode: (nodeId: string | null) => void;
  isNodeExecuting: (nodeId: string) => boolean;
  clearExecutingNodes: () => void;
  setLastJobStatus: (status: JobStatus) => void;
  clearGraph: () => void;
  loadTemplate: (template: WorkflowTemplate) => void;

  // Rename action
  setRenamingNodeId: (nodeId: string | null) => void;

  // Progress actions
  setGraphProgress: (progress: GraphProgress | null) => void;
  setNodeProgress: (nodeId: string, progress: NodeProgress) => void;
  clearProgress: () => void;

  // Error actions
  setNodeError: (nodeId: string, error: NodeError) => void;
  clearNodeError: (nodeId: string) => void;
  clearAllErrors: () => void;

  // Clipboard actions
  copyNodes: (nodeIds: string[]) => void;
  pasteNodes: (position: { x: number; y: number }) => { nodes: Node[]; edges: Edge[] } | null;

  // History actions (delegated to workflowStore)
  pushHistory: () => void;
  undo: () => void;
  redo: () => void;
  canUndo: () => boolean;
  canRedo: () => boolean;

  // Selection actions
  selectAll: () => void;
  deselectAll: () => void;

  // Sync with workflowStore
  syncFromActiveTab: () => void;
}

// Helper to generate unique node IDs with timestamp for scheduler ordering
const generateNodeId = () => {
  const timestamp = Date.now();
  const id = `node_${timestamp}_${Math.random().toString(36).slice(2, 7)}`;
  return { id, createdAt: timestamp };
};

// Helper to deduplicate by id
const deduplicateById = <T extends { id: string }>(items: T[]): T[] => {
  // Defensive check: ensure items is an array
  if (!Array.isArray(items)) {
    console.warn('deduplicateById received non-array:', items);
    return [];
  }
  const seen = new Set<string>();
  return items.filter((item) => {
    if (seen.has(item.id)) return false;
    seen.add(item.id);
    return true;
  });
};

export const useGraphStore = create<GraphState>()(
  subscribeWithSelector((set, get) => ({
    nodes: [],
    edges: [],
    isExecuting: false,
    currentNode: null,
    executingNodes: {},
    lastJobStatus: null,
    renamingNodeId: null,
    graphProgress: null,
    nodeProgress: {},
    nodeErrors: {},
    clipboard: null,

    setNodes: (nodes) => {
      const uniqueNodes = deduplicateById(nodes);
      // Only update workflowStore (single source of truth)
      useWorkflowStore.getState().setNodes(uniqueNodes);
    },

    setEdges: (edgesOrFn) => {
      // Get current edges from workflowStore (source of truth)
      const activeTab = useWorkflowStore.getState().getActiveTab();
      const currentEdges = activeTab?.edges ?? [];
      const edges = typeof edgesOrFn === 'function' ? edgesOrFn(currentEdges) : edgesOrFn;
      const uniqueEdges = deduplicateById(edges);
      // Only update workflowStore (single source of truth)
      useWorkflowStore.getState().setEdges(uniqueEdges);
    },

    addNode: (node) => {
      // Get current nodes from workflowStore (source of truth)
      const activeTab = useWorkflowStore.getState().getActiveTab();
      const currentNodes = activeTab?.nodes ?? [];
      const newNodes = [...currentNodes, node];
      // Only update workflowStore (single source of truth)
      useWorkflowStore.getState().setNodes(newNodes);
    },

    updateNodeData: (nodeId, data) => {
      // Get current nodes from workflowStore (source of truth)
      const activeTab = useWorkflowStore.getState().getActiveTab();
      const currentNodes = activeTab?.nodes ?? [];
      const newNodes = currentNodes.map((n) =>
        n.id === nodeId ? { ...n, data: { ...n.data, ...data } } : n
      );
      // Only update workflowStore (single source of truth)
      useWorkflowStore.getState().setNodes(newNodes);
    },

    setExecuting: (isExecuting) => set({ isExecuting }),
    setCurrentNode: (nodeId) => {
      const previousNode = get().currentNode;
      set({ currentNode: nodeId });

      // When moving to a new node, schedule removal of the previous node after minimum display time
      if (previousNode && previousNode !== nodeId) {
        // Clear any existing timer for the previous node
        const existingTimer = executingTimers.get(previousNode);
        if (existingTimer) {
          clearTimeout(existingTimer);
        }

        // Set timer to remove previous node from executing set
        const timer = setTimeout(() => {
          executingTimers.delete(previousNode);
          set((state) => {
            const { [previousNode]: _removed, ...rest } = state.executingNodes;
            return { executingNodes: rest };
          });
        }, MIN_EXECUTING_DISPLAY_MS);

        executingTimers.set(previousNode, timer);
      }

      // Add new node to executing set immediately
      if (nodeId) {
        set((state) => ({
          executingNodes: { ...state.executingNodes, [nodeId]: true },
        }));
      }
    },
    isNodeExecuting: (nodeId) => {
      const state = get();
      return state.currentNode === nodeId || !!state.executingNodes[nodeId];
    },
    clearExecutingNodes: () => {
      // Clear all timers
      executingTimers.forEach((timer) => clearTimeout(timer));
      executingTimers.clear();
      set({ executingNodes: {}, currentNode: null });
    },
    setLastJobStatus: (lastJobStatus) => set({ lastJobStatus }),
    setRenamingNodeId: (renamingNodeId) => set({ renamingNodeId }),

    clearGraph: () => {
      // Only update workflowStore (single source of truth)
      useWorkflowStore.getState().setNodes([]);
      useWorkflowStore.getState().setEdges([]);
    },

    loadTemplate: (template) => {
      const nodes = deepClone(template.nodes);
      const edges = deepClone(template.edges);
      // Only update workflowStore (single source of truth)
      useWorkflowStore.getState().setNodes(nodes);
      useWorkflowStore.getState().setEdges(edges);
      useWorkflowStore.getState().pushHistory();
    },

    // Progress actions
    setGraphProgress: (graphProgress) => set({ graphProgress }),
    setNodeProgress: (nodeId, progress) =>
      set((state) => ({
        nodeProgress: { ...state.nodeProgress, [nodeId]: progress },
      })),
    clearProgress: () => set({ graphProgress: null, nodeProgress: {} }),

    // Error actions
    setNodeError: (nodeId, error) =>
      set((state) => ({
        nodeErrors: { ...state.nodeErrors, [nodeId]: error },
      })),
    clearNodeError: (nodeId) =>
      set((state) => {
        const { [nodeId]: _removed, ...rest } = state.nodeErrors;
        return { nodeErrors: rest };
      }),
    clearAllErrors: () => set({ nodeErrors: {} }),

    // Clipboard actions
    copyNodes: (nodeIds) => {
      const state = get();
      const nodesToCopy = state.nodes.filter((n) => nodeIds.includes(n.id));
      if (nodesToCopy.length === 0) return;

      // Get edges between copied nodes
      const nodeIdSet = new Set(nodeIds);
      const edgesToCopy = state.edges.filter(
        (e) => nodeIdSet.has(e.source) && nodeIdSet.has(e.target)
      );

      set({
        clipboard: {
          nodes: nodesToCopy,
          edges: edgesToCopy,
        },
      });
    },

    pasteNodes: (position) => {
      const state = get();
      if (!state.clipboard || state.clipboard.nodes.length === 0) return null;

      // Get current nodes and edges from workflowStore (source of truth)
      const activeTab = useWorkflowStore.getState().getActiveTab();
      const currentNodes = activeTab?.nodes ?? [];
      const currentEdges = activeTab?.edges ?? [];

      // Calculate offset from original position to paste position
      const clipboardNodes = state.clipboard.nodes;
      const minX = Math.min(...clipboardNodes.map((n) => n.position.x));
      const minY = Math.min(...clipboardNodes.map((n) => n.position.y));
      const offsetX = position.x - minX;
      const offsetY = position.y - minY;

      // Create ID mapping for new nodes (with created_at timestamps)
      const idMap = new Map<string, { id: string; createdAt: number }>();
      clipboardNodes.forEach((n) => {
        idMap.set(n.id, generateNodeId());
      });

      // Create new nodes with new IDs, positions, and created_at timestamps
      const newNodes: Node[] = clipboardNodes.map((n) => {
        const { id, createdAt } = idMap.get(n.id)!;
        return {
          ...n,
          id,
          position: {
            x: n.position.x + offsetX,
            y: n.position.y + offsetY,
          },
          data: { ...n.data, created_at: createdAt },
          selected: true,
        };
      });

      // Create new edges with updated node IDs
      const newEdges: Edge[] = state.clipboard.edges.map((e) => ({
        ...e,
        id: `e_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
        source: idMap.get(e.source)!.id,
        target: idMap.get(e.target)!.id,
      }));

      // Deselect existing nodes
      const updatedExistingNodes = currentNodes.map((n) => ({
        ...n,
        selected: false,
      }));

      const allNodes = [...updatedExistingNodes, ...newNodes];
      const allEdges = [...currentEdges, ...newEdges];

      // Only update workflowStore (single source of truth)
      useWorkflowStore.getState().setNodes(allNodes);
      useWorkflowStore.getState().setEdges(allEdges);

      return { nodes: newNodes, edges: newEdges };
    },

    // History actions - delegate to workflowStore
    pushHistory: () => {
      useWorkflowStore.getState().pushHistory();
    },

    undo: () => {
      useWorkflowStore.getState().undo();
      // Sync from workflowStore
      get().syncFromActiveTab();
    },

    redo: () => {
      useWorkflowStore.getState().redo();
      // Sync from workflowStore
      get().syncFromActiveTab();
    },

    canUndo: () => {
      return useWorkflowStore.getState().canUndo();
    },

    canRedo: () => {
      return useWorkflowStore.getState().canRedo();
    },

    // Selection actions
    selectAll: () => {
      // Get current nodes from workflowStore (source of truth)
      const activeTab = useWorkflowStore.getState().getActiveTab();
      const currentNodes = activeTab?.nodes ?? [];
      const newNodes = currentNodes.map((n) => ({ ...n, selected: true }));
      // Only update workflowStore (single source of truth)
      useWorkflowStore.getState().setNodes(newNodes);
    },

    deselectAll: () => {
      // Get current nodes from workflowStore (source of truth)
      const activeTab = useWorkflowStore.getState().getActiveTab();
      const currentNodes = activeTab?.nodes ?? [];
      const newNodes = currentNodes.map((n) => ({ ...n, selected: false }));
      // Only update workflowStore (single source of truth)
      useWorkflowStore.getState().setNodes(newNodes);
    },

    // Sync from workflowStore's active tab
    syncFromActiveTab: () => {
      const activeTab = useWorkflowStore.getState().getActiveTab();
      if (activeTab) {
        set({
          nodes: activeTab.nodes,
          edges: activeTab.edges,
        });
      }
    },
  }))
);

// Subscribe to workflowStore changes to sync when active tab changes
let previousActiveTabId: string | null = null;
let isInitialized = false;
let isUpdatingFromWorkflowStore = false; // Guard against circular updates

useWorkflowStore.subscribe(
  (state) => state.activeTabId,
  (activeTabId) => {
    if (activeTabId !== previousActiveTabId) {
      previousActiveTabId = activeTabId;
      useGraphStore.getState().syncFromActiveTab();
    }
  }
);

// Subscribe to active tab's nodes/edges changes with efficient comparison
useWorkflowStore.subscribe(
  (state) => {
    const tab = state.getActiveTab();
    return tab ? { nodes: tab.nodes, edges: tab.edges, tabId: tab.id } : null;
  },
  (tabData) => {
    if (tabData && !isUpdatingFromWorkflowStore) {
      isUpdatingFromWorkflowStore = true;
      try {
        // Directly update graphStore state from workflowStore (one-way sync)
        useGraphStore.setState({
          nodes: tabData.nodes,
          edges: tabData.edges,
        });
      } finally {
        isUpdatingFromWorkflowStore = false;
      }
    }
  },
  {
    // Use reference equality for better performance than JSON.stringify
    equalityFn: (a, b) => {
      if (a === b) return true;
      if (!a || !b) return false;
      return (
        a.tabId === b.tabId &&
        a.nodes === b.nodes &&
        a.edges === b.edges
      );
    },
  }
);

// Initialize after zustand persist has rehydrated
const initializeSync = () => {
  if (isInitialized) return;
  isInitialized = true;

  // Clear old localStorage data from previous graphStore implementation
  if (typeof window !== 'undefined') {
    localStorage.removeItem('leaxer-graph');
  }

  // Sync from workflowStore
  useGraphStore.getState().syncFromActiveTab();
};

// Wait for workflowStore to finish rehydration before syncing
if (typeof window !== 'undefined') {
  const persistApi = useWorkflowStore.persist;

  if (persistApi?.onFinishHydration && persistApi?.hasHydrated) {
    const unsubFinishHydration = persistApi.onFinishHydration(() => {
      initializeSync();
      unsubFinishHydration();
    });

    // Handle case where workflowStore is already hydrated (e.g., hot reload)
    if (persistApi.hasHydrated()) {
      initializeSync();
      unsubFinishHydration();
    }
  } else {
    // Fallback: listen for the custom event and also try after a delay
    window.addEventListener('workflowstore-rehydrated', () => {
      initializeSync();
    });
    // Also try after a short delay as backup
    setTimeout(() => {
      initializeSync();
    }, 100);
  }
}

// Development-time invariant checks to verify stores stay in sync
if (typeof window !== 'undefined') {
  // Add periodic sync checks in development
  const isDev = localStorage.getItem('debug') === 'true' || window.location.hostname === 'localhost';
  if (isDev) {
    setInterval(() => {
      const graphState = useGraphStore.getState();
      const activeTab = useWorkflowStore.getState().getActiveTab();

      if (activeTab) {
        // Check if stores have diverged
        const nodesEqual = graphState.nodes === activeTab.nodes;
        const edgesEqual = graphState.edges === activeTab.edges;

        if (!nodesEqual || !edgesEqual) {
          console.warn('Store sync divergence detected:', {
            nodesEqual,
            edgesEqual,
            graphNodes: graphState.nodes.length,
            workflowNodes: activeTab.nodes.length,
            graphEdges: graphState.edges.length,
            workflowEdges: activeTab.edges.length,
          });
        }
      }
    }, 5000); // Check every 5 seconds in development
  }
}
