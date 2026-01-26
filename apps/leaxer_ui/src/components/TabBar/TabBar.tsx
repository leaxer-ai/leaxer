import { useState, useCallback, useRef, useEffect, type DragEvent } from 'react';
import { Tab } from './Tab';
import { useWorkflowStore } from '@/stores/workflowStore';
import { createWorkflowMetadata } from '@/types/workflow';
import './TabBar.css';

interface TabBarProps {
  onCloseTabRequest: (tabId: string) => void;
}

export function TabBar({ onCloseTabRequest }: TabBarProps) {
  const tabs = useWorkflowStore((s) => s.tabs);
  const activeTabId = useWorkflowStore((s) => s.activeTabId);
  const setActiveTab = useWorkflowStore((s) => s.setActiveTab);
  const createNewTab = useWorkflowStore((s) => s.createNewTab);
  const reorderTabs = useWorkflowStore((s) => s.reorderTabs);
  const updateTabMetadata = useWorkflowStore((s) => s.updateTabMetadata);

  const [dragIndex, setDragIndex] = useState<number | null>(null);
  const [dropIndex, setDropIndex] = useState<number | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const prevTabCountRef = useRef(tabs.length);

  // Get actual active tab ID (fallback to first tab)
  const effectiveActiveTabId = activeTabId || tabs[0]?.id;

  // Auto-scroll to new tab when added
  useEffect(() => {
    if (tabs.length > prevTabCountRef.current && scrollRef.current) {
      // New tab was added, scroll to end
      scrollRef.current.scrollTo({
        left: scrollRef.current.scrollWidth,
        behavior: 'smooth',
      });
    }
    prevTabCountRef.current = tabs.length;
  }, [tabs.length]);

  const handleNewTab = useCallback(() => {
    createNewTab([], [], createWorkflowMetadata('Untitled'));
  }, [createNewTab]);

  const handleRename = useCallback(
    (tabId: string, newName: string) => {
      updateTabMetadata(tabId, { name: newName });
    },
    [updateTabMetadata]
  );

  const handleDragStart = useCallback((_e: DragEvent, index: number) => {
    setDragIndex(index);
  }, []);

  const handleDragOver = useCallback(
    (_e: DragEvent, index: number) => {
      if (dragIndex !== null && dragIndex !== index) {
        setDropIndex(index);
      }
    },
    [dragIndex]
  );

  const handleDragEnd = useCallback(() => {
    if (dragIndex !== null && dropIndex !== null && dragIndex !== dropIndex) {
      reorderTabs(dragIndex, dropIndex);
    }
    setDragIndex(null);
    setDropIndex(null);
  }, [dragIndex, dropIndex, reorderTabs]);

  return (
    <div className="workflow-tabs-pill">
      {/* Scrollable tab list */}
      <div className="tabs-scroll-area" ref={scrollRef}>
        {tabs.map((tab, index) => (
          <Tab
            key={tab.id}
            id={tab.id}
            name={tab.metadata.name}
            isActive={tab.id === effectiveActiveTabId}
            isDirty={tab.isDirty}
            index={index}
            onActivate={() => setActiveTab(tab.id)}
            onClose={() => onCloseTabRequest(tab.id)}
            onRename={(newName) => handleRename(tab.id, newName)}
            onDragStart={handleDragStart}
            onDragOver={handleDragOver}
            onDragEnd={handleDragEnd}
            isDragTarget={dropIndex === index}
          />
        ))}
      </div>

      {/* Separator */}
      <div className="tabs-separator" />

      {/* Add button (right side) */}
      <button
        className="tabs-add-button"
        onClick={handleNewTab}
        title="New Tab (⌘N)"
      >
        <svg
          className="w-4 h-4"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
        >
          <path d="M12 5v14M5 12h14" />
        </svg>
      </button>
    </div>
  );
}
