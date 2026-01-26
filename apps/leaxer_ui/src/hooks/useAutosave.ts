import { useEffect, useRef, useCallback } from 'react';
import { useSettingsStore } from '@/stores/settingsStore';
import { useWorkflowStore } from '@/stores/workflowStore';
import { saveWorkflow } from '@/lib/fileSystem';
import { createLogger } from '@/lib/logger';

const log = createLogger('Autosave');

/**
 * Autosave hook that periodically saves workflows via backend API
 * Only saves tabs that have been saved before (have a filePath/name set)
 */
export function useAutosave() {
  const autosaveEnabled = useSettingsStore((s) => s.autosaveEnabled);
  const autosaveInterval = useSettingsStore((s) => s.autosaveInterval);
  const tabs = useWorkflowStore((s) => s.tabs);
  const exportWorkflow = useWorkflowStore((s) => s.exportWorkflow);
  const setTabDirty = useWorkflowStore((s) => s.setTabDirty);

  const intervalRef = useRef<number | null>(null);
  const lastSaveRef = useRef<Record<string, string>>({});

  const performAutosave = useCallback(async () => {
    // Get tabs that have been saved before (filePath is set) and are dirty
    const tabsToSave = tabs.filter((tab) => tab.filePath && tab.isDirty);

    if (tabsToSave.length === 0) return;

    for (const tab of tabsToSave) {
      try {
        const workflow = exportWorkflow(tab.id);
        if (!workflow) continue;

        const content = JSON.stringify(workflow, null, 2);

        // Check if content has changed since last save
        if (lastSaveRef.current[tab.id] === content) continue;

        // Save to backend using workflow name
        await saveWorkflow(tab.metadata.name, workflow);
        lastSaveRef.current[tab.id] = content;
        setTabDirty(tab.id, false);

        log.debug(`Saved ${tab.metadata.name}`);
      } catch (e) {
        log.error(`Failed to save ${tab.metadata.name}:`, e);
      }
    }
  }, [tabs, exportWorkflow, setTabDirty]);

  // Store performAutosave in a ref so the interval callback always uses the
  // latest version without needing to recreate the interval
  const autosaveRef = useRef(performAutosave);
  useEffect(() => {
    autosaveRef.current = performAutosave;
  }, [performAutosave]);

  useEffect(() => {
    // Clear existing interval
    if (intervalRef.current) {
      clearInterval(intervalRef.current);
      intervalRef.current = null;
    }

    // Don't set up interval if autosave is disabled
    if (!autosaveEnabled) return;

    // Set up new interval (convert seconds to milliseconds)
    // Use ref to call latest performAutosave without recreating interval
    intervalRef.current = window.setInterval(() => {
      autosaveRef.current();
    }, autosaveInterval * 1000);

    // Cleanup on unmount or when settings change
    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
    };
  }, [autosaveEnabled, autosaveInterval]);

  // Return a manual save function if needed
  return { triggerAutosave: performAutosave };
}
