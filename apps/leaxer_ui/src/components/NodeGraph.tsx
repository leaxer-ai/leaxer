import React, { useCallback, useRef, useState, useEffect, useMemo } from 'react';
import {
  ReactFlow,
  Background,
  Panel,
  ReactFlowProvider,
  addEdge,
  reconnectEdge,
  useReactFlow,
  useNodesInitialized,
  SelectionMode,
  ConnectionLineType,
  applyNodeChanges,
  applyEdgeChanges,
  type Connection,
  type Node,
  type Edge,
  type NodeChange,
  type EdgeChange,
  type IsValidConnection,
  ConnectionMode,
} from '@xyflow/react';
import type { FinalConnectionState } from '@xyflow/system';

import { useGraphStore } from '../stores/graphStore';
import { useWorkflowStore } from '../stores/workflowStore';
import { useSettingsStore } from '../stores/settingsStore';
import { useUIStore } from '../stores/uiStore';
import { useNodeSpecsContextOptional } from '../contexts/NodeSpecsContext';
import { NodeContextMenu } from './NodeContextMenu';
import { CommandPalette } from './CommandPalette';
import { ColoredEdge } from './edges/ColoredEdge';
import { nodeTypes } from './nodes/NodeFactory';
import { Minimap } from './Minimap';
import { ZoomControls } from './ZoomControls';
import { createSpatialIndex, type Rectangle } from '../lib/spatialIndex';

const edgeTypes = {
  colored: ColoredEdge,
};

// Generate unique node ID with timestamp for deterministic ordering
// The timestamp is also stored in data.created_at for scheduler use
const generateNodeId = () => {
  const timestamp = Date.now();
  const id = `node_${timestamp}_${Math.random().toString(36).slice(2, 7)}`;
  return { id, createdAt: timestamp };
};

// Get default style for a node type (some nodes need specific dimensions)
function getDefaultStyle(type: string): React.CSSProperties {
  switch (type) {
    case 'PreviewImage':
      return { width: 300, height: 280 };
    case 'Group':
      return { width: 400, height: 300 };
    default:
      return { width: 300 };
  }
}

const defaultEdgeOptions = {
  type: 'colored',
  style: {
    strokeWidth: 2,
  },
};

interface ContextMenuState {
  x: number;
  y: number;
  nodeId?: string;
  nodeType?: string;
}

function NodeGraphInner() {
  const reactFlowWrapper = useRef<HTMLDivElement>(null);
  const [contextMenu, setContextMenu] = useState<ContextMenuState | null>(null);
  const { screenToFlowPosition, getNode } = useReactFlow();

  // Node specs from context (may be null during loading)
  const specsContext = useNodeSpecsContextOptional();

  // Get data type for a handle from the node specs context
  const getDataType = useCallback(
    (nodeType: string | undefined, handleId: string | null): string | undefined => {
      if (!nodeType || !handleId) return undefined;
      return specsContext?.getHandleDataType(nodeType, handleId);
    },
    [specsContext]
  );

  // Get default data for a node type from the node specs context
  const getDefaultData = useCallback(
    (type: string): Record<string, unknown> => {
      return specsContext?.getDefaultData(type) ?? {};
    },
    [specsContext]
  );

  // Command palette from UI store
  const commandPaletteOpen = useUIStore((s) => s.commandPaletteOpen);
  const openCommandPalette = useUIStore((s) => s.openCommandPalette);
  const openCommandPaletteWithConnection = useUIStore((s) => s.openCommandPaletteWithConnection);
  const pendingConnection = useUIStore((s) => s.pendingConnection);
  const closeCommandPalette = useUIStore((s) => s.closeCommandPalette);

  // Viewport lock state
  const viewportLocked = useUIStore((s) => s.viewportLocked);

  // Read nodes/edges directly from workflowStore to avoid sync issues
  // Use direct state access instead of getActiveTab() method to ensure proper subscription
  const storeNodes = useWorkflowStore((s) => {
    const tabId = s.activeTabId || s.tabs[0]?.id;
    const tab = s.tabs.find((t) => t.id === tabId);
    return tab?.nodes ?? [];
  });
  const storeEdges = useWorkflowStore((s) => {
    const tabId = s.activeTabId || s.tabs[0]?.id;
    const tab = s.tabs.find((t) => t.id === tabId);
    return tab?.edges ?? [];
  });

  // Use ReactFlow's useNodesInitialized hook to detect when handles are ready
  // This replaces the unreliable setTimeout approach that could fail on slower devices
  // When nodes change (including tab switches), useNodesInitialized returns false
  // until all nodes are measured and have their handles registered
  const nodesInitialized = useNodesInitialized({ includeHiddenNodes: false });

  // Check if specs are loaded - edges can't render until handles exist
  // AutoNodeWithConnections builds handles from specs, so specs must load first
  const specsLoaded = !!(specsContext && specsContext.specs.length > 0);

  // Track when we're ready to show edges
  // Must wait for: nodes initialized + specs loaded + handles registered (via updateNodeInternals)
  const [edgesReady, setEdgesReady] = useState(false);
  const prevNodeIdsRef = useRef<Set<string>>(new Set());
  const prevSpecsLoadedRef = useRef(false);

  // Reset edgesReady when nodes are added/removed OR when specs load (handles need time to register)
  // Using node ID comparison instead of reference equality to avoid flickering during drag
  useEffect(() => {
    // Only reset edges when nodes are added/removed, not when they move
    const currentNodeIds = new Set(storeNodes.map(n => n.id));
    const nodesAddedOrRemoved =
      currentNodeIds.size !== prevNodeIdsRef.current.size ||
      storeNodes.some(n => !prevNodeIdsRef.current.has(n.id));

    const specsJustLoaded = specsLoaded && !prevSpecsLoadedRef.current;

    if (nodesAddedOrRemoved || specsJustLoaded) {
      prevNodeIdsRef.current = currentNodeIds;
      prevSpecsLoadedRef.current = specsLoaded;
      setEdgesReady(false);
    }
  }, [storeNodes, specsLoaded]);

  // Set edges ready when nodes are initialized, specs loaded, and a frame has passed
  // The requestAnimationFrame ensures handles are registered after updateNodeInternals
  useEffect(() => {
    if (nodesInitialized && specsLoaded && !edgesReady) {
      // Wait for next frame to ensure handles are registered after updateNodeInternals
      const frameId = requestAnimationFrame(() => {
        setEdgesReady(true);
      });
      return () => cancelAnimationFrame(frameId);
    }
  }, [nodesInitialized, specsLoaded, edgesReady]);

  // Filter edges to only include those where both source and target nodes have valid specs
  // This prevents "Couldn't create edge" warnings for nodes with missing/old specs
  const validEdges = useMemo(() => {
    if (!specsLoaded || !specsContext) return [];

    // Build set of node IDs that have valid specs (either custom UI or backend spec)
    const nodeIdToType = new Map(storeNodes.map(n => [n.id, n.type]));

    return storeEdges.filter(edge => {
      const sourceType = nodeIdToType.get(edge.source);
      const targetType = nodeIdToType.get(edge.target);

      if (!sourceType || !targetType) return false;

      // Check if both source and target have valid specs
      const sourceHasSpec = specsContext.getSpec(sourceType) !== undefined;
      const targetHasSpec = specsContext.getSpec(targetType) !== undefined;

      return sourceHasSpec && targetHasSpec;
    });
  }, [storeEdges, storeNodes, specsContext, specsLoaded]);

  // Use store nodes directly, show edges only when fully ready
  // This prevents "Couldn't create edge for source handle" warnings
  const nodes = storeNodes;
  const edges = edgesReady ? validEdges : [];


  const setNodes = useGraphStore((s) => s.setNodes);
  const setEdges = useGraphStore((s) => s.setEdges);
  const updateNodeData = useGraphStore((s) => s.updateNodeData);
  const copyNodes = useGraphStore((s) => s.copyNodes);
  const pasteNodes = useGraphStore((s) => s.pasteNodes);
  const clipboard = useGraphStore((s) => s.clipboard);
  const pushHistory = useGraphStore((s) => s.pushHistory);
  const setRenamingNodeId = useGraphStore((s) => s.setRenamingNodeId);
  const toggleNodeBypassed = useWorkflowStore((s) => s.toggleNodeBypassed);

  // Settings
  const showGrid = useSettingsStore((s) => s.showGrid);
  const snapToGrid = useSettingsStore((s) => s.snapToGrid);
  const gridSize = useSettingsStore((s) => s.gridSize);
  const edgeType = useSettingsStore((s) => s.edgeType);

  // Map edge type setting to ConnectionLineType
  const connectionLineType = {
    bezier: ConnectionLineType.Bezier,
    straight: ConnectionLineType.Straight,
    step: ConnectionLineType.Step,
    smoothstep: ConnectionLineType.SmoothStep,
  }[edgeType] ?? ConnectionLineType.SmoothStep;

  // Track mouse position for paste
  const mousePositionRef = useRef({ x: 0, y: 0 });
  const lastPaneClickRef = useRef<{ time: number; x: number; y: number }>({ time: 0, x: 0, y: 0 });

  // Build spatial index for group nodes (O(1) point-in-group queries instead of O(N))
  // Rebuilds only when nodes array changes (including group position/size changes)
  const groupSpatialIndex = useMemo(() => {
    const groupRects: Rectangle[] = nodes
      .filter((n) => n.type === 'Group')
      .map((group) => ({
        id: group.id,
        x: group.position.x,
        y: group.position.y,
        width: (group.style?.width as number) || group.measured?.width || 300,
        height: (group.style?.height as number) || group.measured?.height || 200,
      }));
    return createSpatialIndex(groupRects);
  }, [nodes]);

  const onNodesChange = useCallback(
    (changes: NodeChange[]) => {
      // Check if any removals - push history before removing
      const hasRemoval = changes.some((c) => c.type === 'remove');
      if (hasRemoval) {
        pushHistory();
      }

      setNodes(applyNodeChanges(changes, nodes));
    },
    [nodes, setNodes, pushHistory]
  );

  // Push history when node drag ends and handle group membership
  // Uses spatial index for O(1) average-case group lookup instead of O(N) iteration
  const onNodeDragStop = useCallback(
    (_event: React.MouseEvent, draggedNode: Node) => {
      pushHistory();

      // Skip if the dragged node is a group itself or no groups exist
      if (draggedNode.type === 'Group') return;
      if (groupSpatialIndex.isEmpty()) return;

      // Get the absolute position of the dragged node
      let absoluteX = draggedNode.position.x;
      let absoluteY = draggedNode.position.y;

      // If the node has a parent, calculate absolute position
      if (draggedNode.parentId) {
        const parentRect = groupSpatialIndex.get(draggedNode.parentId);
        if (parentRect) {
          absoluteX += parentRect.x;
          absoluteY += parentRect.y;
        }
      }

      const nodeWidth = draggedNode.measured?.width || 200;
      const nodeHeight = draggedNode.measured?.height || 100;
      const nodeCenterX = absoluteX + nodeWidth / 2;
      const nodeCenterY = absoluteY + nodeHeight / 2;

      // O(1) average-case lookup: find group containing the node's center
      // Excludes current parent to allow re-parenting to a different group
      const targetRect = groupSpatialIndex.findContaining(
        nodeCenterX,
        nodeCenterY,
        draggedNode.parentId
      );

      // Check if the node was dragged outside its current parent group
      let leftParent = false;
      if (draggedNode.parentId) {
        const parentRect = groupSpatialIndex.get(draggedNode.parentId);
        if (parentRect) {
          // Check if center is outside parent bounds
          if (
            nodeCenterX < parentRect.x ||
            nodeCenterX > parentRect.x + parentRect.width ||
            nodeCenterY < parentRect.y ||
            nodeCenterY > parentRect.y + parentRect.height
          ) {
            leftParent = true;
          }
        }
      }

      // Update nodes if group membership changed
      if (targetRect || leftParent) {
        setNodes(
          nodes.map((n) => {
            if (n.id !== draggedNode.id) return n;

            if (targetRect) {
              // Add to new group
              return {
                ...n,
                parentId: targetRect.id,
                position: {
                  x: absoluteX - targetRect.x,
                  y: absoluteY - targetRect.y,
                },
                extent: undefined,
              };
            } else if (leftParent) {
              // Remove from group
              return {
                ...n,
                parentId: undefined,
                position: {
                  x: absoluteX,
                  y: absoluteY,
                },
              };
            }
            return n;
          })
        );
      }
    },
    [nodes, setNodes, pushHistory, groupSpatialIndex]
  );

  // Track edge being reconnected to prevent deletion during reconnect
  const reconnectingEdgeId = useRef<string | null>(null);

  const onEdgesChange = useCallback(
    (changes: EdgeChange[]) => {
      // Filter out removal of edge being reconnected (ReactFlow tries to delete it during drag)
      const filteredChanges = changes.filter((change) => {
        if (change.type === 'remove' && reconnectingEdgeId.current === change.id) {
          return false; // Skip this removal
        }
        return true;
      });

      // Check if any removals - push history before removing
      const hasRemoval = filteredChanges.some((c) => c.type === 'remove');
      if (hasRemoval) {
        pushHistory();
      }

      if (filteredChanges.length > 0) {
        // Use functional update to avoid stale closure issues
        setEdges((currentEdges) => applyEdgeChanges(filteredChanges, currentEdges));
      }
    },
    [setEdges, pushHistory]
  );

  // Type-safe connection validation
  const isValidConnection: IsValidConnection = useCallback(
    (connection) => {
      const sourceNode = getNode(connection.source);
      const targetNode = getNode(connection.target);

      if (!sourceNode || !targetNode) return false;

      const sourceType = getDataType(sourceNode.type, connection.sourceHandle ?? null);
      const targetType = getDataType(targetNode.type, connection.targetHandle ?? null);

      // Reject if either type is unknown - stricter validation
      if (!sourceType || !targetType) return false;

      // ANY type is a wildcard - connects to any type (for polymorphic nodes like Reroute, IfElse, Switch)
      if (sourceType === 'ANY' || targetType === 'ANY') return true;

      // Types must match exactly
      return sourceType === targetType;
    },
    [getNode, getDataType]
  );

  const onConnect = useCallback(
    (connection: Connection) => {
      pushHistory();

      // Single-input enforcement: remove existing connection to this target handle
      const existingEdge = edges.find(
        (e) => e.target === connection.target &&
               e.targetHandle === connection.targetHandle
      );

      let newEdges = edges;
      if (existingEdge) {
        // Remove the existing connection to this input
        newEdges = edges.filter((e) => e.id !== existingEdge.id);
      }

      // Get the data type for the edge color
      const sourceNode = getNode(connection.source);
      const dataType = sourceNode ? getDataType(sourceNode.type, connection.sourceHandle) : undefined;

      const newEdge = {
        ...connection,
        type: 'colored',
        data: { dataType },
      };

      setEdges(addEdge(newEdge, newEdges));
    },
    [edges, setEdges, getNode, pushHistory, getDataType]
  );

  // Track edge being reconnected so we can restore it if dropped on empty space
  const edgeReconnectSuccessful = useRef(true);

  // Called when user starts dragging an edge to reconnect
  const onReconnectStart = useCallback(
    (_event: React.MouseEvent, edge: Edge) => {
      edgeReconnectSuccessful.current = false;
      reconnectingEdgeId.current = edge.id;
    },
    []
  );

  // Handle edge reconnection (dragging edge to new target)
  const onReconnect = useCallback(
    (oldEdge: Edge, newConnection: Connection) => {
      edgeReconnectSuccessful.current = true;
      pushHistory();

      // Get the data type for the edge color
      const sourceNode = getNode(newConnection.source);
      const dataType = sourceNode ? getDataType(sourceNode.type, newConnection.sourceHandle) : undefined;

      // Use reconnectEdge to update the edge with new connection
      const reconnectedEdges = reconnectEdge(oldEdge, newConnection, edges);

      // Defensive check: reconnectEdge may return undefined in edge cases
      if (!Array.isArray(reconnectedEdges)) {
        console.warn('reconnectEdge returned non-array:', reconnectedEdges);
        return;
      }

      const updatedEdges = reconnectedEdges.map((e) => {
        if (e.source === newConnection.source && e.target === newConnection.target &&
            e.sourceHandle === newConnection.sourceHandle && e.targetHandle === newConnection.targetHandle) {
          return { ...e, type: 'colored', data: { dataType } };
        }
        return e;
      });
      setEdges(updatedEdges);
    },
    [edges, setEdges, getNode, pushHistory, getDataType]
  );

  // Called when reconnect ends - clear tracking state
  const onReconnectEnd = useCallback(
    (_event: MouseEvent | TouchEvent, _edge: Edge) => {
      // Clear the reconnecting edge tracking
      reconnectingEdgeId.current = null;
      edgeReconnectSuccessful.current = true;
    },
    []
  );

  // Handle connection dropped on empty space
  const onConnectEnd = useCallback(
    (event: MouseEvent | TouchEvent, connectionState: FinalConnectionState) => {
      // Only trigger if we didn't connect to a valid target
      if (!connectionState.isValid && connectionState.fromNode) {
        const fromNode = connectionState.fromNode;
        const fromHandle = connectionState.fromHandle;

        // Get the data type of the handle we're dragging from
        const dataType = getDataType(fromNode.type, fromHandle?.id ?? null);

        if (dataType) {
          // Get the drop position
          const clientX = 'clientX' in event ? event.clientX : event.changedTouches[0].clientX;
          const clientY = 'clientY' in event ? event.clientY : event.changedTouches[0].clientY;

          const position = screenToFlowPosition({ x: clientX, y: clientY });

          // Open command palette with connection info
          openCommandPaletteWithConnection({
            nodeId: fromNode.id,
            nodeType: fromNode.type ?? 'unknown',
            handleId: fromHandle?.id ?? '',
            handleType: fromHandle?.type ?? 'source',
            dataType,
            position,
          });
        }
      }
    },
    [screenToFlowPosition, openCommandPaletteWithConnection, getDataType]
  );

  // Context menu handlers - pane (canvas)
  const onPaneContextMenu = useCallback((event: React.MouseEvent | globalThis.MouseEvent) => {
    event.preventDefault();
    setContextMenu({
      x: event.clientX,
      y: event.clientY,
    });
  }, []);

  // Context menu handlers - node
  const onNodeContextMenu = useCallback((event: React.MouseEvent, node: Node) => {
    event.preventDefault();
    setContextMenu({
      x: event.clientX,
      y: event.clientY,
      nodeId: node.id,
      nodeType: node.type,
    });
  }, []);

  const onPaneClick = useCallback((event: React.MouseEvent) => {
    setContextMenu(null);

    // Detect double-click on pane
    const now = Date.now();
    const last = lastPaneClickRef.current;
    const DOUBLE_CLICK_THRESHOLD = 300; // ms
    const DOUBLE_CLICK_DISTANCE = 5; // pixels

    const distance = Math.sqrt(
      Math.pow(event.clientX - last.x, 2) + Math.pow(event.clientY - last.y, 2)
    );

    if (now - last.time < DOUBLE_CLICK_THRESHOLD && distance < DOUBLE_CLICK_DISTANCE) {
      // Double-click detected - open command palette
      mousePositionRef.current = { x: event.clientX, y: event.clientY };
      openCommandPalette();
      // Reset to prevent triple-click
      lastPaneClickRef.current = { time: 0, x: 0, y: 0 };
    } else {
      // Store this click for double-click detection
      lastPaneClickRef.current = { time: now, x: event.clientX, y: event.clientY };
    }
  }, [openCommandPalette]);

  // Delete selected nodes
  const onDeleteNode = useCallback((nodeId: string) => {
    pushHistory();
    setNodes(nodes.filter(n => n.id !== nodeId));
    setEdges(edges.filter(e => e.source !== nodeId && e.target !== nodeId));
    setContextMenu(null);
  }, [nodes, edges, setNodes, setEdges, pushHistory]);

  // Duplicate a node
  const onDuplicateNode = useCallback((nodeId: string) => {
    const node = nodes.find(n => n.id === nodeId);
    if (!node) return;

    pushHistory();

    const { id, createdAt } = generateNodeId();
    const newNode: Node = {
      id,
      type: node.type,
      position: { x: node.position.x + 30, y: node.position.y + 30 },
      data: { ...node.data, created_at: createdAt },
      style: node.style || { width: 300 },
    };

    setNodes([...nodes, newNode]);
    setContextMenu(null);
  }, [nodes, setNodes, pushHistory]);

  // Change group node color
  const onChangeGroupColor = useCallback((nodeId: string, color: string) => {
    updateNodeData(nodeId, { color });
  }, [updateNodeData]);

  // Copy selected nodes
  const onCopyNodes = useCallback(() => {
    const selectedNodeIds = nodes.filter(n => n.selected).map(n => n.id);
    if (selectedNodeIds.length > 0) {
      copyNodes(selectedNodeIds);
    }
  }, [nodes, copyNodes]);

  // Paste nodes at position
  const onPasteNodes = useCallback(() => {
    pushHistory();
    const position = screenToFlowPosition(mousePositionRef.current);
    pasteNodes(position);
  }, [pasteNodes, screenToFlowPosition, pushHistory]);

  // Delete selected nodes
  const onDeleteSelected = useCallback(() => {
    const selectedNodeIds = nodes.filter(n => n.selected).map(n => n.id);
    if (selectedNodeIds.length === 0) return;

    pushHistory();
    const selectedNodeIdSet = new Set(selectedNodeIds);
    setNodes(nodes.filter(n => !selectedNodeIdSet.has(n.id)));
    setEdges(edges.filter(e => !selectedNodeIdSet.has(e.source) && !selectedNodeIdSet.has(e.target)));
  }, [nodes, edges, setNodes, setEdges, pushHistory]);

  // Group selected nodes
  const onGroupSelected = useCallback(() => {
    const selectedNodes = nodes.filter(n => n.selected && n.type !== 'Group');
    if (selectedNodes.length === 0) return;

    pushHistory();

    // Calculate bounding box with padding
    const padding = 40;
    const minX = Math.min(...selectedNodes.map(n => n.position.x)) - padding;
    const minY = Math.min(...selectedNodes.map(n => n.position.y)) - padding;
    const maxX = Math.max(...selectedNodes.map(n => n.position.x + (n.measured?.width || 200))) + padding;
    const maxY = Math.max(...selectedNodes.map(n => n.position.y + (n.measured?.height || 100))) + padding;

    const { id: groupId, createdAt: groupCreatedAt } = generateNodeId();
    const groupWidth = maxX - minX;
    const groupHeight = maxY - minY;

    // Create the group node
    const groupNode: Node = {
      id: groupId,
      type: 'Group',
      position: { x: minX, y: minY },
      data: { label: 'Group', width: groupWidth, height: groupHeight, created_at: groupCreatedAt },
      style: { width: groupWidth, height: groupHeight },
      // Group nodes should be behind other nodes
      zIndex: -1,
    };

    // Update selected nodes to be children of the group
    // Convert their positions to be relative to the group
    const updatedNodes = nodes.map(n => {
      if (n.selected && n.type !== 'Group') {
        return {
          ...n,
          parentId: groupId,
          position: {
            x: n.position.x - minX,
            y: n.position.y - minY,
          },
          // Explicitly set extent to allow dragging outside
          extent: undefined,
          selected: false,
        };
      }
      return { ...n, selected: false };
    });

    // Add group node first (parent must exist before children)
    setNodes([groupNode, ...updatedNodes]);
    setContextMenu(null);
  }, [nodes, setNodes, pushHistory]);

  // Track mouse position for paste
  const onMouseMove = useCallback((event: React.MouseEvent) => {
    mousePositionRef.current = { x: event.clientX, y: event.clientY };
  }, []);

  // Keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      const isMod = event.metaKey || event.ctrlKey;

      // Command Palette: Cmd/Ctrl + K (works even in inputs)
      if (isMod && event.key === 'k') {
        event.preventDefault();
        openCommandPalette();
        return;
      }

      // Don't handle other shortcuts if focus is in an input
      if (
        event.target instanceof HTMLInputElement ||
        event.target instanceof HTMLTextAreaElement
      ) {
        return;
      }

      // Copy: Cmd/Ctrl + C
      if (isMod && event.key === 'c') {
        event.preventDefault();
        onCopyNodes();
      }

      // Paste: Cmd/Ctrl + V
      if (isMod && event.key === 'v') {
        event.preventDefault();
        onPasteNodes();
      }

      // Duplicate: Cmd/Ctrl + D
      if (isMod && event.key === 'd') {
        event.preventDefault();
        const selectedNodes = nodes.filter(n => n.selected);
        if (selectedNodes.length === 1) {
          onDuplicateNode(selectedNodes[0].id);
        } else if (selectedNodes.length > 1) {
          // Copy and paste for multi-selection duplicate
          onCopyNodes();
          // Small timeout to ensure clipboard is set
          setTimeout(() => {
            const centerX = selectedNodes.reduce((sum, n) => sum + n.position.x, 0) / selectedNodes.length;
            const centerY = selectedNodes.reduce((sum, n) => sum + n.position.y, 0) / selectedNodes.length;
            pasteNodes({ x: centerX + 30, y: centerY + 30 });
          }, 0);
        }
      }

      // Delete: Backspace or Delete
      if (event.key === 'Backspace' || event.key === 'Delete') {
        event.preventDefault();
        onDeleteSelected();
      }

      // Group: Cmd/Ctrl + G
      if (isMod && event.key === 'g') {
        event.preventDefault();
        onGroupSelected();
      }

      // Bypass: B key
      if (event.key === 'b' && !isMod) {
        event.preventDefault();
        const selectedNodes = nodes.filter(n => n.selected);
        for (const node of selectedNodes) {
          toggleNodeBypassed(node.id);
        }
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onCopyNodes, onPasteNodes, onDeleteSelected, onDuplicateNode, onGroupSelected, nodes, pasteNodes, toggleNodeBypassed]);

  const onAddNode = useCallback(
    (type: string, screenPosition: { x: number; y: number }) => {
      pushHistory();

      const position = screenToFlowPosition({
        x: screenPosition.x,
        y: screenPosition.y,
      });

      const { id, createdAt } = generateNodeId();
      const newNode: Node = {
        id,
        type,
        position,
        data: { ...getDefaultData(type), created_at: createdAt },
        selected: true,
        style: getDefaultStyle(type),
      };

      setNodes([...nodes, newNode]);
    },
    [nodes, setNodes, screenToFlowPosition, pushHistory, getDefaultData]
  );

  // Handler for command palette node selection - adds node and optionally connects
  const onCommandPaletteSelect = useCallback(
    (type: string, connectToHandle?: string) => {
      pushHistory();

      let position: { x: number; y: number };

      // If there's a pending connection, use its position
      if (pendingConnection) {
        position = pendingConnection.position;
      } else {
        // Otherwise use mouse position or center of viewport
        if (mousePositionRef.current.x !== 0 || mousePositionRef.current.y !== 0) {
          position = screenToFlowPosition(mousePositionRef.current);
        } else {
          const wrapper = reactFlowWrapper.current;
          if (!wrapper) return;
          const rect = wrapper.getBoundingClientRect();
          position = screenToFlowPosition({
            x: rect.left + rect.width / 2,
            y: rect.top + rect.height / 2,
          });
        }
      }

      const { id: newNodeId, createdAt } = generateNodeId();
      const newNode: Node = {
        id: newNodeId,
        type,
        position,
        data: { ...getDefaultData(type), created_at: createdAt },
        selected: true,
        style: getDefaultStyle(type),
      };

      // Add the new node
      const newNodes = [...nodes, newNode];
      setNodes(newNodes);

      // If there's a pending connection, create the edge
      if (pendingConnection && connectToHandle) {
        const dataType = pendingConnection.dataType;

        let newEdge: Edge;
        if (pendingConnection.handleType === 'source') {
          // Dragging from source to new node's target
          newEdge = {
            id: `e_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
            source: pendingConnection.nodeId,
            sourceHandle: pendingConnection.handleId,
            target: newNodeId,
            targetHandle: connectToHandle,
            type: 'colored',
            data: { dataType },
          };
        } else {
          // Dragging from target to new node's source
          newEdge = {
            id: `e_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
            source: newNodeId,
            sourceHandle: connectToHandle,
            target: pendingConnection.nodeId,
            targetHandle: pendingConnection.handleId,
            type: 'colored',
            data: { dataType },
          };
        }

        setEdges([...edges, newEdge]);
      }

      // Close the palette and clear pending connection
      closeCommandPalette();
    },
    [nodes, edges, setNodes, setEdges, screenToFlowPosition, pushHistory, pendingConnection, closeCommandPalette]
  );

  // Connection line style
  const connectionLineStyle = {
    strokeWidth: 2,
    stroke: '#6b7280',
  };

  // Force default cursor on all ReactFlow elements
  useEffect(() => {
    if (!reactFlowWrapper.current) return;

    const style = document.createElement('style');
    style.textContent = `
      .react-flow__pane,
      .react-flow__pane svg,
      .react-flow {
        cursor: default !important;
      }
    `;
    reactFlowWrapper.current.appendChild(style);

    return () => style.remove();
  }, []);

  return (
    <div
      ref={reactFlowWrapper}
      className="w-full h-full"
      onMouseMove={onMouseMove}
      style={{ cursor: 'default' }}
    >
      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onConnect={onConnect}
        onConnectEnd={onConnectEnd}
        onReconnectStart={onReconnectStart}
        onReconnect={onReconnect}
        onReconnectEnd={onReconnectEnd}
        edgesReconnectable
        onNodeDragStop={onNodeDragStop}
        onPaneContextMenu={onPaneContextMenu}
        onNodeContextMenu={onNodeContextMenu}
        onPaneClick={onPaneClick}
        nodeTypes={nodeTypes}
        edgeTypes={edgeTypes}
        defaultEdgeOptions={defaultEdgeOptions}
        isValidConnection={isValidConnection}
        connectionMode={ConnectionMode.Strict}
        connectionLineType={connectionLineType}
        connectionLineStyle={connectionLineStyle}
        fitView
        snapToGrid={snapToGrid}
        snapGrid={[gridSize, gridSize]}
        selectionOnDrag={!viewportLocked}
        selectionMode={SelectionMode.Partial}
        selectionKeyCode="Shift"
        multiSelectionKeyCode="Shift"
        zoomOnDoubleClick={false}
        zoomOnScroll={!viewportLocked}
        zoomOnPinch={!viewportLocked}
        panOnDrag={!viewportLocked}
        preventScrolling
        minZoom={0.25}
        maxZoom={3}
        style={{ background: 'var(--color-base)' }}
        proOptions={{ hideAttribution: true }}
      >
        {showGrid && (
          <Background color="var(--color-surface-2)" gap={gridSize} size={1.5} />
        )}
        <Minimap />
        <Panel position="bottom-left" style={{ bottom: '16px', left: '16px', margin: 0 }}>
          <ZoomControls />
        </Panel>
      </ReactFlow>
      <NodeContextMenu
        position={contextMenu ? { x: contextMenu.x, y: contextMenu.y } : null}
        nodeId={contextMenu?.nodeId}
        nodeType={contextMenu?.nodeType}
        onClose={() => setContextMenu(null)}
        onAddNode={onAddNode}
        onDeleteNode={onDeleteNode}
        onDuplicateNode={onDuplicateNode}
        onRenameNode={setRenamingNodeId}
        onToggleBypassed={toggleNodeBypassed}
        onChangeGroupColor={onChangeGroupColor}
        onGroupSelected={onGroupSelected}
        onCopy={onCopyNodes}
        onPaste={() => {
          if (contextMenu) {
            const position = screenToFlowPosition({ x: contextMenu.x, y: contextMenu.y });
            pasteNodes(position);
          }
        }}
        hasSelection={nodes.some(n => n.selected)}
        hasClipboard={!!clipboard && clipboard.nodes.length > 0}
        isBypassed={contextMenu?.nodeId ? nodes.find(n => n.id === contextMenu.nodeId)?.data?.bypassed as boolean : false}
      />
      <CommandPalette
        isOpen={commandPaletteOpen}
        onClose={closeCommandPalette}
        onSelectNode={onCommandPaletteSelect}
        pendingConnection={pendingConnection}
      />
    </div>
  );
}

export function NodeGraph() {
  return (
    <ReactFlowProvider>
      <NodeGraphInner />
    </ReactFlowProvider>
  );
}
