import { useCallback, useState, useEffect, useRef } from 'react';
import { NodeGraph } from './components/NodeGraph';
import { TopNav } from './components/TopNav';
import { TabBar } from './components/TabBar';
import { CloseConfirmDialog } from './components/CloseConfirmDialog';
import { SaveAsDialog } from './components/SaveAsDialog';
import { ProgressPill } from './components/ProgressPill';
import { NotificationCenter } from './components/NotificationCenter';
import { HardwareMonitor } from './components/HardwareMonitor';
import { ChatView } from './components/chat';
import { notify } from './lib/notify';
import { createLogger } from './lib/logger';

const log = createLogger('App');
import { QueueDropdown } from './components/QueueDropdown';
import { SettingsModal } from './components/SettingsModal';
import { LogViewer } from './components/LogViewer';
import { ModelManager } from './components/ModelManager';
import { ErrorBoundary, NodeGraphErrorBoundary } from './components/ErrorBoundary';
import { useWebSocket } from './hooks/useWebSocket';
import { useGraphStore } from './stores/graphStore';
import { useWorkflowStore } from './stores/workflowStore';
import { useRecentFilesStore } from './stores/recentFilesStore';
import { useQueueStore } from './stores/queueStore';
import { useSettingsStore } from './stores/settingsStore';
import { useLogStore } from './stores/logStore';
import { useUIStore } from './stores/uiStore';
import { useViewStore } from './stores/viewStore';
import { NodeSpecsProvider } from './contexts/NodeSpecsContext';
import { unlockAudio, playStartSound, playCompleteSound, playStopSound, playSound } from './lib/sounds';
import {
  saveWorkflow,
  loadWorkflow,
  importWorkflowFromFile,
  exportWorkflowToFile,
} from './lib/fileSystem';
import { useAutosave } from './hooks/useAutosave';
import { createWorkflowMetadata } from './types/workflow';
import type { WorkflowSnapshot } from './types/queue';

function App() {
  const {
    isExecuting,
    setExecuting,
    setCurrentNode,
    setLastJobStatus,
    setGraphProgress,
    setNodeProgress,
    clearProgress,
    clearExecutingNodes,
    updateNodeData,
  } = useGraphStore();

  // Read nodes/edges directly from workflowStore (source of truth)
  // Use direct state access instead of getActiveTab() method to ensure proper subscription
  const nodes = useWorkflowStore((s) => {
    const tabId = s.activeTabId || s.tabs[0]?.id;
    const tab = s.tabs.find((t) => t.id === tabId);
    return tab?.nodes ?? [];
  });
  const edges = useWorkflowStore((s) => {
    const tabId = s.activeTabId || s.tabs[0]?.id;
    const tab = s.tabs.find((t) => t.id === tabId);
    return tab?.edges ?? [];
  });
  const getBackendWsUrl = useSettingsStore((s) => s.getBackendWsUrl);
  const getApiBaseUrl = useSettingsStore((s) => s.getApiBaseUrl);
  const computeBackend = useSettingsStore((s) => s.computeBackend);
  const modelCachingStrategy = useSettingsStore((s) => s.modelCachingStrategy);
  const useFramelessWindow = useSettingsStore((s) => s.useFramelessWindow);
  const addLogs = useLogStore((s) => s.addLogs);
  const openCommandPalette = useUIStore((s) => s.openCommandPalette);
  const setQueueState = useQueueStore((s) => s.setQueueState);
  const setServerRestarting = useQueueStore((s) => s.setServerRestarting);
  const currentView = useViewStore((s) => s.currentView);

  // Workflow store
  const getActiveTab = useWorkflowStore((s) => s.getActiveTab);
  const tabs = useWorkflowStore((s) => s.tabs);
  const createNewTab = useWorkflowStore((s) => s.createNewTab);
  const closeTab = useWorkflowStore((s) => s.closeTab);
  const setTabFilePath = useWorkflowStore((s) => s.setTabFilePath);
  const setTabDirty = useWorkflowStore((s) => s.setTabDirty);
  const updateTabMetadata = useWorkflowStore((s) => s.updateTabMetadata);
  const exportWorkflow = useWorkflowStore((s) => s.exportWorkflow);
  const loadWorkflowFromContent = useWorkflowStore((s) => s.loadWorkflowFromContent);

  // Recent files
  const addRecentFile = useRecentFilesStore((s) => s.addRecentFile);
  const recentFiles = useRecentFilesStore((s) => s.files);
  const clearRecentFiles = useRecentFilesStore((s) => s.clearRecentFiles);

  const [settingsOpen, setSettingsOpen] = useState(false);

  // Close confirmation dialog state
  const [closeConfirmState, setCloseConfirmState] = useState<{
    isOpen: boolean;
    tabId: string | null;
    workflowName: string;
  }>({ isOpen: false, tabId: null, workflowName: '' });

  // Save As dialog state
  const [saveAsDialogOpen, setSaveAsDialogOpen] = useState(false);

  // Stopping state - tracks when stop is in progress
  const [isStopping, setIsStopping] = useState(false);

  // Track disconnect notification ID for dismissal on reconnect
  const disconnectNotificationRef = useRef<string | null>(null);

  // Autosave hook - automatically saves workflows with local file paths
  useAutosave();

  // Unlock audio on first user interaction
  useEffect(() => {
    const handleFirstInteraction = () => {
      unlockAudio();
      document.removeEventListener('click', handleFirstInteraction);
    };
    document.addEventListener('click', handleFirstInteraction);
    return () => document.removeEventListener('click', handleFirstInteraction);
  }, []);

  const { connected, queueJobs, cancelJob, clearQueue } = useWebSocket({
    url: getBackendWsUrl(),
    onProgress: (data) => {
      // Update current node
      setCurrentNode(data.node_progress.node_id);

      // Update graph progress
      setGraphProgress({
        currentIndex: data.graph_progress.current_index,
        totalNodes: data.graph_progress.total_nodes,
        percentage: data.graph_progress.percentage,
      });

      // Update node progress
      setNodeProgress(data.node_progress.node_id, {
        currentStep: data.node_progress.current_step,
        totalSteps: data.node_progress.total_steps,
        percentage: data.node_progress.percentage,
        status: data.node_progress.status,
      });
    },
    onStepProgress: (data) => {
      // Update step-level progress (from sd.cpp worker)
      // Ensure currentNode is set for the progress pill to work
      if (data.node_id) {
        setCurrentNode(data.node_id);
        setNodeProgress(data.node_id, {
          currentStep: data.current_step,
          totalSteps: data.total_steps,
          percentage: data.percentage,
          status: 'running',
          phase: data.phase || 'inference',
        });
      }
    },
    onComplete: (data) => {
      setLastJobStatus('completed');
      setExecuting(false);
      clearExecutingNodes();
      clearProgress();
      setIsStopping(false);
      playCompleteSound();
      log.debug('Execution complete', data);
      log.debug('Outputs:', data.outputs);

      // Update nodes with their outputs
      const outputs = data.outputs ;
      for (const [nodeId, output] of Object.entries(outputs)) {
        log.debug('Processing output for node:', nodeId, output);
        const updates: Record<string, unknown> = {};
        if (output?.preview) {
          updates._preview = output.preview;
        }
        if (output?.before_url) {
          updates._before_url = output.before_url;
        }
        if (output?.after_url) {
          updates._after_url = output.after_url;
        }
        if (Object.keys(updates).length > 0) {
          log.debug('Setting outputs for node:', nodeId, updates);
          updateNodeData(nodeId, updates);
        }
      }
    },
    onError: (data) => {
      setLastJobStatus('error');
      setExecuting(false);
      clearExecutingNodes();
      clearProgress();
      setIsStopping(false);
      notify.error(`Error in node ${data.node_id}: ${data.error}`);
      console.error('Execution error', data);
    },
    onAbort: () => {
      setLastJobStatus('stopped');
      setExecuting(false);
      clearExecutingNodes();
      clearProgress();
      setIsStopping(false);
      playStopSound();
      log.debug('Execution aborted');
    },
    onLogBatch: (logs) => {
      log.debug('Adding logs:', logs?.length);
      addLogs(logs);
    },
    onResumed: (data) => {
      // Restore execution state after browser refresh
      log.debug('Execution resumed:', data);
      if (data.is_executing) {
        setExecuting(true);
        if (data.current_node) {
          setCurrentNode(data.current_node);
          // Update graph progress
          setGraphProgress({
            currentIndex: data.current_index,
            totalNodes: data.total_nodes,
            percentage: Math.round((data.current_index / data.total_nodes) * 100),
          });
          // Update step progress if available
          if (data.step_progress) {
            setNodeProgress(data.current_node, {
              currentStep: data.step_progress.current_step,
              totalSteps: data.step_progress.total_steps,
              percentage: data.step_progress.percentage,
              status: 'running',
            });
          }
        }
      }
    },
    // Queue event handlers
    onQueueUpdated: (data) => {
      log.debug('Queue updated:', data);
      setQueueState(data);
      // Update isExecuting based on queue state
      setExecuting(data.is_processing);
      // Reset UI state when queue is no longer processing
      if (!data.is_processing) {
        setIsStopping(false);
        clearExecutingNodes();
        clearProgress();
      }
    },
    onJobCompleted: (data) => {
      log.debug('Job completed:', data.job_id);
      log.debug('Job outputs:', data.outputs);
      // Set status before clearing
      setLastJobStatus('completed');
      clearExecutingNodes();
      clearProgress();
      setIsStopping(false);
      playCompleteSound();
      // Update nodes with their outputs
      const outputs = data.outputs ;
      for (const [nodeId, output] of Object.entries(outputs)) {
        log.debug('Processing output for node:', nodeId, output);
        const updates: Record<string, unknown> = {};
        if (output?.preview) {
          updates._preview = output.preview;
        }
        if (output?.before_url) {
          updates._before_url = output.before_url;
        }
        if (output?.after_url) {
          updates._after_url = output.after_url;
        }
        if (Object.keys(updates).length > 0) {
          log.debug('Setting outputs for node:', nodeId, updates);
          updateNodeData(nodeId, updates);
        }
      }
    },
    onJobError: (data) => {
      log.debug('Job error:', data.job_id, data.error);
      // Set status before clearing
      setLastJobStatus('error');
      clearExecutingNodes();
      clearProgress();
      setIsStopping(false);
      notify.error(`Job ${data.job_id.slice(0, 8)}: ${data.error}`);
    },
    // Real-time node output for incremental preview updates
    onNodeOutput: (data) => {
      log.debug('Node output:', data.node_id, data.output);
      // Update node data immediately when output is available
      const updates: Record<string, unknown> = {};
      if (data.output?.preview) {
        updates._preview = data.output.preview;
      }
      if (data.output?.before_url) {
        updates._before_url = data.output.before_url;
      }
      if (data.output?.after_url) {
        updates._after_url = data.output.after_url;
      }
      if (Object.keys(updates).length > 0) {
        log.debug('Setting outputs for node:', data.node_id, updates);
        updateNodeData(data.node_id, updates);
      }
    },
    // Connection state handlers
    onConnected: () => {
      log.debug('WebSocket connected');
      // Clear restarting state when server is back online
      setServerRestarting(false);
      // Dismiss disconnect notification if one exists and play success sound
      const disconnectNotifId = disconnectNotificationRef.current;
      if (disconnectNotifId) {
        disconnectNotificationRef.current = null;
        notify.dismiss(disconnectNotifId);
        // Play success sound on reconnect
        const settings = useSettingsStore.getState();
        if (settings.soundsEnabled) {
          playSound(settings.soundSuccess);
        }
        notify.success('Connection restored', { description: 'Reconnected to backend server', silent: true });
      }
    },
    onDisconnected: () => {
      log.debug('WebSocket disconnected');
      // Play error sound directly from settings store (more reliable than module state)
      const settings = useSettingsStore.getState();
      if (settings.soundsEnabled) {
        playSound(settings.soundError);
      }
      // Show persistent notification (useWebSocket already prevents duplicate calls)
      const notificationId = notify.error('Connection lost', {
        description: 'Lost connection to backend. Attempting to reconnect...',
        duration: 0, // Persistent until manually dismissed or reconnected
        silent: true, // Sound already played above
      });
      disconnectNotificationRef.current = notificationId;
      // Clear executing nodes visual state to avoid stuck rainbow borders
      // The isExecuting state is kept so we know execution may still be running
      // State will be recovered via execution_resumed when reconnected
      clearExecutingNodes();
    },
  });

  const handleQueue = useCallback(async (count: number) => {
    if (nodes.length === 0) {
      notify.warning('No nodes in graph');
      return;
    }

    playStartSound();

    // Convert ReactFlow format to backend format
    const graphNodes: WorkflowSnapshot['nodes'] = {};
    nodes.forEach((node) => {
      graphNodes[node.id] = {
        id: node.id,
        type: node.type || 'unknown',
        data: node.data as Record<string, unknown>,
      };
    });

    const graphEdges = edges.map((edge) => ({
      source: edge.source,
      sourceHandle: edge.sourceHandle || 'output',
      target: edge.target,
      targetHandle: edge.targetHandle || 'input',
    }));

    // Create workflow snapshot
    const snapshot: WorkflowSnapshot = {
      nodes: graphNodes,
      edges: graphEdges,
      compute_backend: computeBackend,
      model_caching_strategy: modelCachingStrategy,
    };

    // Queue N copies of the workflow
    const jobs = Array(count).fill(snapshot);

    try {
      await queueJobs(jobs);
    } catch {
      notify.error('Failed to queue jobs');
    }
  }, [nodes, edges, queueJobs, computeBackend, modelCachingStrategy]);

  const handleStop = useCallback(() => {
    // Immediately update UI state
    setIsStopping(true);
    playStopSound();
    // Cancel the currently running job (if any)
    const runningJob = useQueueStore.getState().runningJob();
    if (runningJob) {
      cancelJob(runningJob.id).catch(console.error);
    }
  }, [cancelJob]);

  const handleStopAll = useCallback(() => {
    // Stop current job AND clear all pending jobs
    setIsStopping(true);
    playStopSound();
    // First clear all pending jobs
    clearQueue();
    // Then cancel the currently running job (if any)
    const runningJob = useQueueStore.getState().runningJob();
    if (runningJob) {
      cancelJob(runningJob.id).catch(console.error);
    }
  }, [cancelJob, clearQueue]);

  const handleClearQueue = useCallback(() => {
    clearQueue();
  }, [clearQueue]);

  // File operations
  const handleNewFile = useCallback(() => {
    createNewTab([], [], createWorkflowMetadata('Untitled'));
  }, [createNewTab]);

  const handleOpenFile = useCallback(async () => {
    try {
      // Import from local file (uses browser file picker)
      const result = await importWorkflowFromFile();
      if (!result) return;

      const loadResult = loadWorkflowFromContent(JSON.stringify(result.workflow), result.name);

      if (loadResult.success) {
        addRecentFile(result.name, result.name);
      } else {
        notify.error(loadResult.error || 'Failed to open file');
      }
    } catch (e) {
      notify.error(`Failed to open file: ${e instanceof Error ? e.message : 'Unknown error'}`);
    }
  }, [loadWorkflowFromContent, addRecentFile]);

  const handleOpenRecentFile = useCallback(async (name: string) => {
    try {
      // Load from backend by name
      const workflow = await loadWorkflow(name);
      const loadResult = loadWorkflowFromContent(JSON.stringify(workflow), name);

      if (loadResult.success) {
        addRecentFile(name, name);
      } else {
        notify.error(loadResult.error || 'Failed to open file');
      }
    } catch (e) {
      notify.error(`Failed to open file: ${e instanceof Error ? e.message : 'Unknown error'}`);
    }
  }, [loadWorkflowFromContent, addRecentFile]);

  const handleSaveFile = useCallback(async () => {
    const tab = getActiveTab();
    if (!tab) return;

    try {
      const workflow = exportWorkflow();
      if (!workflow) {
        notify.error('Failed to export workflow');
        return;
      }

      // Save to backend using workflow name
      const name = tab.metadata.name;
      const result = await saveWorkflow(name, workflow);

      if (result.success) {
        // Mark as saved (use name as filePath indicator)
        setTabFilePath(tab.id, result.name);
        setTabDirty(tab.id, false);
        addRecentFile(result.name, result.name);
      }
    } catch (e) {
      notify.error(`Failed to save file: ${e instanceof Error ? e.message : 'Unknown error'}`);
    }
  }, [getActiveTab, exportWorkflow, setTabDirty, setTabFilePath, addRecentFile]);

  const handleSaveAsFile = useCallback(() => {
    const tab = getActiveTab();
    if (!tab) return;
    setSaveAsDialogOpen(true);
  }, [getActiveTab]);

  const handleSaveAsConfirm = useCallback(async (newName: string) => {
    const tab = getActiveTab();
    if (!tab) return;

    setSaveAsDialogOpen(false);

    try {
      const workflow = exportWorkflow();
      if (!workflow) {
        notify.error('Failed to export workflow');
        return;
      }

      const result = await saveWorkflow(newName, workflow);

      if (result.success) {
        setTabFilePath(tab.id, result.name);
        updateTabMetadata(tab.id, { name: result.name });
        addRecentFile(result.name, result.name);
        setTabDirty(tab.id, false);
      }
    } catch (e) {
      notify.error(`Failed to save file: ${e instanceof Error ? e.message : 'Unknown error'}`);
    }
  }, [getActiveTab, exportWorkflow, setTabFilePath, updateTabMetadata, addRecentFile, setTabDirty]);

  const handleExportFile = useCallback(() => {
    const tab = getActiveTab();
    if (!tab) return;

    const workflow = exportWorkflow();
    if (!workflow) {
      notify.error('Failed to export workflow');
      return;
    }

    // Download as file
    exportWorkflowToFile(`${tab.metadata.name}.lxr`, workflow);
  }, [getActiveTab, exportWorkflow]);

  const handleCloseTabRequest = useCallback((tabId: string) => {
    const tab = tabs.find((t) => t.id === tabId);
    if (!tab) return;

    if (tab.isDirty) {
      setCloseConfirmState({
        isOpen: true,
        tabId,
        workflowName: tab.metadata.name,
      });
    } else {
      closeTab(tabId);
    }
  }, [tabs, closeTab]);

  const handleCloseConfirmSave = useCallback(async () => {
    const { tabId } = closeConfirmState;
    if (!tabId) return;

    // Save the tab
    await handleSaveFile();

    // Close the tab after saving
    closeTab(tabId);
    setCloseConfirmState({ isOpen: false, tabId: null, workflowName: '' });
  }, [closeConfirmState, handleSaveFile, closeTab]);

  const handleCloseConfirmDontSave = useCallback(() => {
    const { tabId } = closeConfirmState;
    if (!tabId) return;

    closeTab(tabId);
    setCloseConfirmState({ isOpen: false, tabId: null, workflowName: '' });
  }, [closeConfirmState, closeTab]);

  const handleCloseConfirmCancel = useCallback(() => {
    setCloseConfirmState({ isOpen: false, tabId: null, workflowName: '' });
  }, []);

  // Get API base URL (dynamically handles LAN access)
  const apiBaseUrl = getApiBaseUrl();

  return (
    <NodeSpecsProvider baseUrl={apiBaseUrl}>
      <div
        className="w-screen h-screen relative overflow-hidden"
        style={{ backgroundColor: 'var(--color-base)' }}
      >
          {/* Top navigation */}
          <ErrorBoundary componentName="Top Navigation">
            <TopNav
              isExecuting={isExecuting}
              isStopping={isStopping}
              onQueue={handleQueue}
              onStop={handleStop}
              onStopAll={handleStopAll}
              onOpenSettings={() => setSettingsOpen(true)}
              onOpenCommandPalette={openCommandPalette}
              connected={connected}
              onNewFile={handleNewFile}
              onOpenFile={handleOpenFile}
              onSaveFile={handleSaveFile}
              onSaveAsFile={handleSaveAsFile}
              onExportFile={handleExportFile}
              onCloseTab={() => {
                const tab = getActiveTab();
                if (tab) handleCloseTabRequest(tab.id);
              }}
              recentFiles={recentFiles}
              onOpenRecentFile={handleOpenRecentFile}
              onClearRecentFiles={clearRecentFiles}
              useFramelessWindow={useFramelessWindow}
            >
              <TabBar onCloseTabRequest={handleCloseTabRequest} />
            </TopNav>
        </ErrorBoundary>

        {/* Main content area */}
        <div className="w-full h-full">
          {currentView === 'chat' && (
            <ErrorBoundary componentName="Chat View">
              <ChatView />
            </ErrorBoundary>
          )}
          {currentView === 'node' && (
            <NodeGraphErrorBoundary>
              <NodeGraph />
            </NodeGraphErrorBoundary>
          )}
        </div>

        {/* Node-only UI elements */}
        {currentView === 'node' && (
          <>
            {/* Progress pill */}
            <ProgressPill />

            {/* Hardware monitor */}
            <HardwareMonitor />

            {/* Log viewer */}
            <ErrorBoundary componentName="Log Viewer">
              <LogViewer />
            </ErrorBoundary>

            {/* Queue dropdown */}
            <QueueDropdown onClearQueue={handleClearQueue} />
          </>
        )}

        {/* Notification center - always visible */}
        <NotificationCenter />

        {/* Settings modal - always accessible */}
        <ErrorBoundary componentName="Settings">
          <SettingsModal
            isOpen={settingsOpen}
            onClose={() => setSettingsOpen(false)}
          />
        </ErrorBoundary>

        {/* Model Manager modal - always accessible */}
        <ErrorBoundary componentName="Model Manager">
          <ModelManager />
        </ErrorBoundary>

        {/* Close confirmation dialog */}
        <CloseConfirmDialog
          isOpen={closeConfirmState.isOpen}
          workflowName={closeConfirmState.workflowName}
          onSave={handleCloseConfirmSave}
          onDontSave={handleCloseConfirmDontSave}
          onCancel={handleCloseConfirmCancel}
        />

        {/* Save As dialog */}
        <SaveAsDialog
          isOpen={saveAsDialogOpen}
          defaultName={getActiveTab()?.metadata.name || 'Untitled'}
          onSave={handleSaveAsConfirm}
          onCancel={() => setSaveAsDialogOpen(false)}
        />
      </div>
    </NodeSpecsProvider>
  );
}

export default App;
