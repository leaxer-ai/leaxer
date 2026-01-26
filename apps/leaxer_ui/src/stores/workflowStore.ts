import { create } from 'zustand';
import { persist, subscribeWithSelector } from 'zustand/middleware';
import type { Node, Edge, Viewport } from '@xyflow/react';
import type {
  WorkflowMetadata,
  ValidationError,
  LxrWorkflowFormat,
} from '../types/workflow';
import {
  createWorkflowMetadata,
  createLxrWorkflow,
  parseLxrWorkflow,
  deserializeNodes,
  deserializeEdges,
  serializeNodes,
  serializeEdges,
} from '../types/workflow';
import { deepClone } from '../lib/deepClone';

// History entry for undo/redo
interface HistoryEntry {
  nodes: Node[];
  edges: Edge[];
}

// Sanitized state for dirty comparison (excludes transient execution data)
interface SanitizedState {
  nodes: string;  // JSON string of serialized nodes
  edges: string;  // JSON string of serialized edges
}

// A single workflow tab
export interface WorkflowTab {
  id: string;
  filePath: string | null;         // null = unsaved
  metadata: WorkflowMetadata;
  isDirty: boolean;
  nodes: Node[];
  edges: Edge[];
  viewport: Viewport;
  history: HistoryEntry[];
  historyIndex: number;
  validationErrors: ValidationError[];
  lastSavedState?: SanitizedState;  // For dirty comparison
}

// Default workflow template
const defaultNodes: Node[] = [
  {
    id: 'node_0',
    type: 'ModelSelector',
    position: { x: 50, y: 50 },
    data: { repo: 'CompVis/stable-diffusion-v1-4' },
  },
  {
    id: 'node_1',
    type: 'CLIPTextEncode',
    position: { x: 50, y: 280 },
    data: { text: 'a photo of a cat', negative_text: 'blurry, bad quality' },
  },
  {
    id: 'node_2',
    type: 'EmptyLatentImage',
    position: { x: 50, y: 580 },
    data: { width: 512, height: 512 },
  },
  {
    id: 'node_3',
    type: 'KSampler',
    position: { x: 400, y: 200 },
    data: { steps: 20, cfg: 7.5, seed: -1 },
  },
  {
    id: 'node_4',
    type: 'PreviewImage',
    position: { x: 700, y: 280 },
    data: {},
  },
];

const defaultEdges: Edge[] = [
  { id: 'e0-3', source: 'node_0', sourceHandle: 'model', target: 'node_3', targetHandle: 'model', type: 'colored', data: { dataType: 'MODEL' } },
  { id: 'e1-3a', source: 'node_1', sourceHandle: 'positive', target: 'node_3', targetHandle: 'positive', type: 'colored', data: { dataType: 'POSITIVE' } },
  { id: 'e1-3b', source: 'node_1', sourceHandle: 'negative', target: 'node_3', targetHandle: 'negative', type: 'colored', data: { dataType: 'NEGATIVE' } },
  { id: 'e2-3', source: 'node_2', sourceHandle: 'latent', target: 'node_3', targetHandle: 'latent', type: 'colored', data: { dataType: 'LATENT' } },
  { id: 'e3-4', source: 'node_3', sourceHandle: 'image', target: 'node_4', targetHandle: 'image', type: 'colored', data: { dataType: 'IMAGE' } },
];

const defaultViewport: Viewport = { x: 0, y: 0, zoom: 1 };

const MAX_HISTORY_SIZE = 50;

// Helper to generate unique IDs
const generateTabId = () => `tab_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;

// Create a sanitized state for dirty comparison
// This strips transient execution data (previews, base64 images, etc.)
function createSanitizedState(nodes: Node[], edges: Edge[]): SanitizedState {
  return {
    nodes: JSON.stringify(serializeNodes(nodes)),
    edges: JSON.stringify(serializeEdges(edges)),
  };
}

// Check if current state differs from last saved state
function hasRealChanges(
  currentNodes: Node[],
  currentEdges: Edge[],
  lastSavedState?: SanitizedState
): boolean {
  if (!lastSavedState) return true;  // No saved state = consider dirty
  const current = createSanitizedState(currentNodes, currentEdges);
  return current.nodes !== lastSavedState.nodes || current.edges !== lastSavedState.edges;
}

// Create a new tab with default or specified content
function createTab(
  nodes: Node[] = defaultNodes,
  edges: Edge[] = defaultEdges,
  viewport: Viewport = defaultViewport,
  metadata?: WorkflowMetadata,
  filePath: string | null = null
): WorkflowTab {
  const clonedNodes = deepClone(nodes);
  const clonedEdges = deepClone(edges);
  return {
    id: generateTabId(),
    filePath,
    metadata: metadata || createWorkflowMetadata(),
    isDirty: false,
    nodes: clonedNodes,
    edges: clonedEdges,
    viewport: { ...viewport },
    history: [{ nodes: deepClone(clonedNodes), edges: deepClone(clonedEdges) }],
    historyIndex: 0,
    validationErrors: [],
    lastSavedState: createSanitizedState(clonedNodes, clonedEdges),
  };
}

interface WorkflowStoreState {
  tabs: WorkflowTab[];
  activeTabId: string | null;

  // Tab management
  getActiveTab: () => WorkflowTab | null;
  createNewTab: (nodes?: Node[], edges?: Edge[], metadata?: WorkflowMetadata, filePath?: string | null) => string;
  closeTab: (tabId: string) => boolean; // returns true if closed, false if cancelled
  setActiveTab: (tabId: string) => void;
  reorderTabs: (fromIndex: number, toIndex: number) => void;

  // Tab content management
  setTabNodes: (tabId: string, nodes: Node[]) => void;
  setTabEdges: (tabId: string, edges: Edge[]) => void;
  setTabViewport: (tabId: string, viewport: Viewport) => void;
  updateTabMetadata: (tabId: string, updates: Partial<WorkflowMetadata>) => void;
  setTabDirty: (tabId: string, isDirty: boolean) => void;
  setTabFilePath: (tabId: string, filePath: string | null) => void;
  setTabValidationErrors: (tabId: string, errors: ValidationError[]) => void;

  // Active tab shortcuts (for compatibility with graphStore)
  setNodes: (nodes: Node[]) => void;
  setEdges: (edges: Edge[]) => void;
  setViewport: (viewport: Viewport) => void;
  markDirty: () => void;

  // Node state management
  toggleNodeBypassed: (nodeId: string) => void;

  // History per tab
  pushHistory: (tabId?: string) => void;
  undo: (tabId?: string) => void;
  redo: (tabId?: string) => void;
  canUndo: (tabId?: string) => boolean;
  canRedo: (tabId?: string) => boolean;

  // File operations
  loadWorkflowFromContent: (content: string, filePath: string) => { success: boolean; error?: string; tabId?: string };
  exportWorkflow: (tabId?: string) => LxrWorkflowFormat | null;
}

export const useWorkflowStore = create<WorkflowStoreState>()(
  subscribeWithSelector(
    persist(
      (set, get) => {
      // Helper to update a specific tab
      const updateTab = (tabId: string, updates: Partial<WorkflowTab>) => {
        set((state) => ({
          tabs: state.tabs.map((tab) =>
            tab.id === tabId ? { ...tab, ...updates } : tab
          ),
        }));
      };

      return {
        tabs: [createTab()],
        activeTabId: null,

        getActiveTab: () => {
          const state = get();
          const tabId = state.activeTabId || state.tabs[0]?.id;
          return state.tabs.find((t) => t.id === tabId) || null;
        },

        createNewTab: (nodes, edges, metadata, filePath = null) => {
          const newTab = createTab(
            nodes || [],
            edges || [],
            defaultViewport,
            metadata,
            filePath
          );

          // If no nodes provided, start with empty workflow
          if (!nodes) {
            newTab.nodes = [];
            newTab.edges = [];
            newTab.history = [{ nodes: [], edges: [] }];
          }

          set((state) => ({
            tabs: [...state.tabs, newTab],
            activeTabId: newTab.id,
          }));

          return newTab.id;
        },

        closeTab: (tabId) => {
          const state = get();
          const tab = state.tabs.find((t) => t.id === tabId);

          if (!tab) return true;

          // If only one tab, don't close it
          if (state.tabs.length === 1) {
            // Reset to empty workflow instead
            const newTab = createTab([], [], defaultViewport, createWorkflowMetadata());
            newTab.id = tabId;
            set({ tabs: [newTab] });
            return true;
          }

          // Find the next tab to activate
          const tabIndex = state.tabs.findIndex((t) => t.id === tabId);
          const newActiveId = state.tabs[tabIndex === 0 ? 1 : tabIndex - 1]?.id || null;

          set((state) => ({
            tabs: state.tabs.filter((t) => t.id !== tabId),
            activeTabId: state.activeTabId === tabId ? newActiveId : state.activeTabId,
          }));

          return true;
        },

        setActiveTab: (tabId) => {
          const state = get();
          if (state.tabs.some((t) => t.id === tabId)) {
            set({ activeTabId: tabId });
          }
        },

        reorderTabs: (fromIndex, toIndex) => {
          set((state) => {
            const tabs = [...state.tabs];
            const [removed] = tabs.splice(fromIndex, 1);
            tabs.splice(toIndex, 0, removed);
            return { tabs };
          });
        },

        setTabNodes: (tabId, nodes) => {
          // Deduplicate nodes by id
          const seen = new Set<string>();
          const uniqueNodes = nodes.filter((n) => {
            if (seen.has(n.id)) return false;
            seen.add(n.id);
            return true;
          });
          // Only mark dirty if sanitized state actually changed
          const tab = get().tabs.find((t) => t.id === tabId);
          const isDirty = hasRealChanges(uniqueNodes, tab?.edges ?? [], tab?.lastSavedState);
          updateTab(tabId, { nodes: uniqueNodes, isDirty });
        },

        setTabEdges: (tabId, edges) => {
          // Deduplicate edges by id
          const seen = new Set<string>();
          const uniqueEdges = edges.filter((e) => {
            if (seen.has(e.id)) return false;
            seen.add(e.id);
            return true;
          });
          // Only mark dirty if sanitized state actually changed
          const tab = get().tabs.find((t) => t.id === tabId);
          const isDirty = hasRealChanges(tab?.nodes ?? [], uniqueEdges, tab?.lastSavedState);
          updateTab(tabId, { edges: uniqueEdges, isDirty });
        },

        setTabViewport: (tabId, viewport) => {
          updateTab(tabId, { viewport });
        },

        updateTabMetadata: (tabId, updates) => {
          const state = get();
          const tab = state.tabs.find((t) => t.id === tabId);
          if (tab) {
            updateTab(tabId, {
              metadata: { ...tab.metadata, ...updates, modified_at: new Date().toISOString() },
              isDirty: true,
            });
          }
        },

        setTabDirty: (tabId, isDirty) => {
          // When marking as not dirty, update last saved state
          if (!isDirty) {
            const tab = get().tabs.find((t) => t.id === tabId);
            const lastSavedState = tab ? createSanitizedState(tab.nodes, tab.edges) : undefined;
            updateTab(tabId, { isDirty, lastSavedState });
          } else {
            updateTab(tabId, { isDirty });
          }
        },

        setTabFilePath: (tabId, filePath) => {
          // Update last saved state when saving
          const tab = get().tabs.find((t) => t.id === tabId);
          const lastSavedState = tab ? createSanitizedState(tab.nodes, tab.edges) : undefined;
          updateTab(tabId, { filePath, isDirty: false, lastSavedState });
        },

        setTabValidationErrors: (tabId, errors) => {
          updateTab(tabId, { validationErrors: errors });
        },

        // Active tab shortcuts
        setNodes: (nodes) => {
          const tab = get().getActiveTab();
          if (tab) {
            get().setTabNodes(tab.id, nodes);
          }
        },

        setEdges: (edges) => {
          const tab = get().getActiveTab();
          if (tab) {
            get().setTabEdges(tab.id, edges);
          }
        },

        setViewport: (viewport) => {
          const tab = get().getActiveTab();
          if (tab) {
            get().setTabViewport(tab.id, viewport);
          }
        },

        markDirty: () => {
          const tab = get().getActiveTab();
          if (tab) {
            get().setTabDirty(tab.id, true);
          }
        },

        toggleNodeBypassed: (nodeId) => {
          const tab = get().getActiveTab();
          if (!tab) return;

          const updatedNodes = tab.nodes.map((node) => {
            if (node.id === nodeId) {
              return {
                ...node,
                data: {
                  ...node.data,
                  bypassed: !node.data.bypassed,
                },
              };
            }
            return node;
          });

          get().pushHistory(tab.id);
          get().setTabNodes(tab.id, updatedNodes);
          get().setTabDirty(tab.id, true);
        },

        // History
        pushHistory: (tabId) => {
          const state = get();
          const tab = tabId
            ? state.tabs.find((t) => t.id === tabId)
            : state.getActiveTab();

          if (!tab) return;

          const newEntry: HistoryEntry = {
            nodes: deepClone(tab.nodes),
            edges: deepClone(tab.edges),
          };

          // Remove any redo history after current index
          const newHistory = tab.history.slice(0, tab.historyIndex + 1);
          newHistory.push(newEntry);

          // Limit history size
          if (newHistory.length > MAX_HISTORY_SIZE) {
            newHistory.shift();
          }

          updateTab(tab.id, {
            history: newHistory,
            historyIndex: newHistory.length - 1,
          });
        },

        undo: (tabId) => {
          const state = get();
          const tab = tabId
            ? state.tabs.find((t) => t.id === tabId)
            : state.getActiveTab();

          if (!tab || tab.historyIndex <= 0) return;

          const newIndex = tab.historyIndex - 1;
          const entry = tab.history[newIndex];
          const newNodes = deepClone(entry.nodes);
          const newEdges = deepClone(entry.edges);

          updateTab(tab.id, {
            nodes: newNodes,
            edges: newEdges,
            historyIndex: newIndex,
            isDirty: hasRealChanges(newNodes, newEdges, tab.lastSavedState),
          });
        },

        redo: (tabId) => {
          const state = get();
          const tab = tabId
            ? state.tabs.find((t) => t.id === tabId)
            : state.getActiveTab();

          if (!tab || tab.historyIndex >= tab.history.length - 1) return;

          const newIndex = tab.historyIndex + 1;
          const entry = tab.history[newIndex];
          const newNodes = deepClone(entry.nodes);
          const newEdges = deepClone(entry.edges);

          updateTab(tab.id, {
            nodes: newNodes,
            edges: newEdges,
            historyIndex: newIndex,
            isDirty: hasRealChanges(newNodes, newEdges, tab.lastSavedState),
          });
        },

        canUndo: (tabId) => {
          const state = get();
          const tab = tabId
            ? state.tabs.find((t) => t.id === tabId)
            : state.getActiveTab();
          return tab ? tab.historyIndex > 0 : false;
        },

        canRedo: (tabId) => {
          const state = get();
          const tab = tabId
            ? state.tabs.find((t) => t.id === tabId)
            : state.getActiveTab();
          return tab ? tab.historyIndex < tab.history.length - 1 : false;
        },

        // File operations
        loadWorkflowFromContent: (content, filePath) => {
          const { workflow, error } = parseLxrWorkflow(content);

          if (error || !workflow) {
            return { success: false, error: error || 'Unknown error' };
          }

          const nodes = deserializeNodes(workflow.graph.nodes);
          const edges = deserializeEdges(workflow.graph.edges);
          const viewport = workflow.graph.viewport || defaultViewport;

          const tabId = get().createNewTab(nodes, edges, workflow.metadata, filePath);

          // Set the viewport
          get().setTabViewport(tabId, viewport);

          // Reset dirty state since we just loaded
          get().setTabDirty(tabId, false);

          // Reset history and set last saved state
          const lastSavedState = createSanitizedState(nodes, edges);
          set((state) => ({
            tabs: state.tabs.map((tab) =>
              tab.id === tabId
                ? {
                    ...tab,
                    history: [{ nodes: deepClone(nodes), edges: deepClone(edges) }],
                    historyIndex: 0,
                    lastSavedState,
                    isDirty: false,
                  }
                : tab
            ),
          }));

          return { success: true, tabId };
        },

        exportWorkflow: (tabId) => {
          const state = get();
          const tab = tabId
            ? state.tabs.find((t) => t.id === tabId)
            : state.getActiveTab();

          if (!tab) return null;

          return createLxrWorkflow(tab.nodes, tab.edges, tab.viewport, tab.metadata);
        },
      };
    },
    {
      name: 'leaxer-workflows',
      partialize: (state) => ({
        tabs: state.tabs.map((tab) => {
          // Sanitize nodes to remove execution results (base64 images, etc.)
          // This uses serializeNodes which strips transient data, then deserialize back
          const sanitizedNodes = serializeNodes(tab.nodes).map(sn => ({
            id: sn.id,
            type: sn.type,
            position: sn.position,
            data: sn.data,
            style: { width: sn.width ?? 300, ...(sn.height && { height: sn.height }) },
          }));

          return {
            id: tab.id,
            filePath: tab.filePath,
            metadata: tab.metadata,
            isDirty: tab.isDirty,
            nodes: sanitizedNodes,
            edges: tab.edges,
            viewport: tab.viewport,
            // Don't persist full history, just create a single entry
            history: [{ nodes: sanitizedNodes, edges: tab.edges }],
            historyIndex: 0,
            validationErrors: [],
          };
        }),
        activeTabId: state.activeTabId,
      }),
      onRehydrateStorage: () => {
        return (_state, error) => {
          if (error) {
            console.error('Error rehydrating workflow store:', error);
          } else {
            // Dispatch a custom event that graphStore can listen for
            window.dispatchEvent(new CustomEvent('workflowstore-rehydrated'));
          }
        };
      },
    }
    )
  )
);

// Selector helpers
export const selectActiveTab = (state: WorkflowStoreState) => state.getActiveTab();
export const selectTabs = (state: WorkflowStoreState) => state.tabs;
export const selectActiveTabId = (state: WorkflowStoreState) => state.activeTabId;
