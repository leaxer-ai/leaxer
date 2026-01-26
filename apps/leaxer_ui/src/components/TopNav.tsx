import { useState, useRef, useEffect, useCallback } from 'react';
import { createPortal } from 'react-dom';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { Minus, Square, X, Copy } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useGraphStore } from '@/stores/graphStore';
import { useWorkflowStore } from '@/stores/workflowStore';
import { useQueueStore } from '@/stores/queueStore';
import { useLogStore } from '@/stores/logStore';
import { useDownloadStore } from '@/stores/downloadStore';
import { useViewStore } from '@/stores/viewStore';
import { useChatStore } from '@/stores/chatStore';
import { detectPlatform } from '@/stores/settingsStore';
import { getTemplate } from '@/data/workflowTemplates';
import { QueuePill } from './QueuePill';
import { ViewTabs } from './ViewTabs';
import type { RecentFile } from '@/stores/recentFilesStore';
import './TopNav.css';

type NavAnimationPhase = 'hidden' | 'animating' | 'visible';

interface TopNavProps {
  isExecuting: boolean;
  isStopping: boolean;
  onQueue: (count: number) => void;
  onStop: () => void;
  onStopAll: () => void;
  onOpenSettings: () => void;
  onOpenCommandPalette: () => void;
  connected: boolean;
  // File operations
  onNewFile: () => void;
  onOpenFile: () => void;
  onSaveFile: () => void;
  onSaveAsFile: () => void;
  onExportFile: () => void;
  onCloseTab: () => void;
  recentFiles: RecentFile[];
  onOpenRecentFile: (name: string) => void;
  onClearRecentFiles: () => void;
  // Window
  useFramelessWindow?: boolean;
  // Children (for TabBar)
  children?: React.ReactNode;
}

interface MenuItem {
  label: string;
  shortcut?: string;
  action?: () => void;
  disabled?: boolean;
  separator?: boolean;
  submenu?: MenuItem[];
}

interface MenuConfig {
  label: string;
  items: MenuItem[];
}

// Submenu component for nested menus - rendered via portal
function SubMenu({
  items,
  onClose,
  parentRect,
}: {
  items: MenuItem[];
  onClose: () => void;
  parentRect: DOMRect | null;
}) {
  if (!parentRect) return null;

  return createPortal(
    <div
      className="fixed z-[101] min-w-[200px] py-1.5 rounded-xl backdrop-blur-xl"
      style={{
        top: parentRect.top,
        left: parentRect.right + 4,
        background: 'rgba(255, 255, 255, 0.08)',
        boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
      }}
    >
      {items.map((item, index) =>
        item.separator ? (
          <div
            key={index}
            className="my-1.5 mx-3 h-px"
            style={{ backgroundColor: 'rgba(255, 255, 255, 0.1)' }}
          />
        ) : (
          <button
            key={index}
            className={cn(
              'w-full px-3 py-1.5 mx-1.5 flex items-center justify-between text-left rounded-lg',
              'text-xs transition-all duration-100',
              item.disabled
                ? 'opacity-50 cursor-not-allowed'
                : 'cursor-pointer hover:bg-white/10'
            )}
            style={{
              color: 'var(--color-text)',
              width: 'calc(100% - 12px)',
            }}
            onClick={() => {
              if (!item.disabled && item.action) {
                item.action();
                onClose();
              }
            }}
            disabled={item.disabled}
          >
            <span className="truncate">{item.label}</span>
          </button>
        )
      )}
    </div>,
    document.body
  );
}

function DropdownMenu({
  menu,
  isOpen,
  onClose,
  buttonRef,
}: {
  menu: MenuConfig;
  isOpen: boolean;
  onClose: () => void;
  buttonRef: React.RefObject<HTMLButtonElement | null>;
}) {
  const menuRef = useRef<HTMLDivElement>(null);
  const [hoveredSubmenu, setHoveredSubmenu] = useState<number | null>(null);
  const [submenuParentRect, setSubmenuParentRect] = useState<DOMRect | null>(null);
  const [position, setPosition] = useState({ top: 0, left: 0 });
  const submenuButtonRefs = useRef<Record<number, HTMLButtonElement | null>>({});

  // Calculate position when menu opens
  useEffect(() => {
    if (isOpen && buttonRef.current) {
      const rect = buttonRef.current.getBoundingClientRect();
      setPosition({
        top: rect.bottom + 12, // 12px gap below button
        left: rect.left,
      });
    }
  }, [isOpen, buttonRef]);

  useEffect(() => {
    if (!isOpen) return;

    const handleClickOutside = (e: MouseEvent) => {
      // Close if clicked outside the menu AND outside the button (if button exists)
      const clickedOutsideMenu = menuRef.current && !menuRef.current.contains(e.target as Node);
      const clickedOutsideButton = !buttonRef.current || !buttonRef.current.contains(e.target as Node);

      if (clickedOutsideMenu && clickedOutsideButton) {
        onClose();
      }
    };

    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        onClose();
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    document.addEventListener('keydown', handleEscape);

    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
      document.removeEventListener('keydown', handleEscape);
    };
  }, [isOpen, onClose, buttonRef]);

  // Reset hovered submenu when menu closes
  useEffect(() => {
    if (!isOpen) {
      setHoveredSubmenu(null);
      setSubmenuParentRect(null);
    }
  }, [isOpen]);

  // Update submenu parent rect when hovering
  useEffect(() => {
    if (hoveredSubmenu !== null && submenuButtonRefs.current[hoveredSubmenu]) {
      setSubmenuParentRect(submenuButtonRefs.current[hoveredSubmenu]!.getBoundingClientRect());
    } else {
      setSubmenuParentRect(null);
    }
  }, [hoveredSubmenu]);

  if (!isOpen) return null;

  return createPortal(
    <div
      ref={menuRef}
      className="fixed z-[100] min-w-[200px] py-1.5 rounded-xl backdrop-blur-xl"
      style={{
        top: position.top,
        left: position.left,
        background: 'rgba(255, 255, 255, 0.08)',
        boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
      }}
    >
      {menu.items.map((item, index) =>
        item.separator ? (
          <div
            key={index}
            className="my-1.5 mx-3 h-px"
            style={{ backgroundColor: 'rgba(255, 255, 255, 0.1)' }}
          />
        ) : item.submenu ? (
          <div
            key={index}
            className="relative"
            onMouseEnter={() => setHoveredSubmenu(index)}
            onMouseLeave={() => setHoveredSubmenu(null)}
          >
            <button
              ref={(el) => { submenuButtonRefs.current[index] = el; }}
              className={cn(
                'w-full px-3 py-1.5 mx-1.5 flex items-center justify-between text-left rounded-lg',
                'text-xs transition-all duration-100',
                item.disabled
                  ? 'opacity-50 cursor-not-allowed'
                  : 'cursor-pointer hover:bg-white/10'
              )}
              style={{
                color: 'var(--color-text)',
                width: 'calc(100% - 12px)',
              }}
              disabled={item.disabled}
            >
              <span>{item.label}</span>
              <svg
                className="w-3 h-3"
                style={{ color: 'var(--color-text-muted)' }}
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
              >
                <path d="M9 18l6-6-6-6" />
              </svg>
            </button>
            {hoveredSubmenu === index && item.submenu.length > 0 && (
              <SubMenu items={item.submenu} onClose={onClose} parentRect={submenuParentRect} />
            )}
          </div>
        ) : (
          <button
            key={index}
            className={cn(
              'w-full px-3 py-1.5 mx-1.5 flex items-center justify-between text-left rounded-lg',
              'text-xs transition-all duration-100',
              item.disabled
                ? 'opacity-50 cursor-not-allowed'
                : 'cursor-pointer hover:bg-white/10'
            )}
            style={{
              color: 'var(--color-text)',
              width: 'calc(100% - 12px)',
            }}
            onClick={() => {
              if (!item.disabled && item.action) {
                item.action();
              }
              if (!item.disabled && !item.submenu) {
                onClose();
              }
            }}
            disabled={item.disabled}
          >
            <span>{item.label}</span>
            {item.shortcut && (
              <span
                className="text-[11px] ml-4"
                style={{ color: 'var(--color-text-muted)' }}
              >
                {item.shortcut}
              </span>
            )}
          </button>
        )
      )}
    </div>,
    document.body
  );
}

export function TopNav({
  isExecuting,
  isStopping,
  onQueue,
  onStop,
  onStopAll,
  onOpenSettings,
  onOpenCommandPalette,
  connected,
  onNewFile,
  onOpenFile,
  onSaveFile,
  onSaveAsFile,
  onExportFile,
  onCloseTab,
  recentFiles,
  onOpenRecentFile,
  onClearRecentFiles,
  useFramelessWindow = false,
  children,
}: TopNavProps) {
  const [openMenu, setOpenMenu] = useState<string | null>(null);
  const [leftNavPhase, setLeftNavPhase] = useState<NavAnimationPhase>('hidden');
  const [rightNavPhase, setRightNavPhase] = useState<NavAnimationPhase>('hidden');
  const [confirmNewWorkflow, setConfirmNewWorkflow] = useState(false);
  const [isMenuHovered, setIsMenuHovered] = useState(false);
  const menuHoverTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const buttonRefs = useRef<Record<string, HTMLButtonElement | null>>({});
  const navRef = useRef<HTMLDivElement>(null);

  // Menu hover handlers with delay for smoother UX
  const handleMenuAreaEnter = useCallback(() => {
    if (menuHoverTimeoutRef.current) {
      clearTimeout(menuHoverTimeoutRef.current);
      menuHoverTimeoutRef.current = null;
    }
    setIsMenuHovered(true);
  }, []);

  const handleMenuAreaLeave = useCallback(() => {
    // Delay hiding to allow moving between elements
    menuHoverTimeoutRef.current = setTimeout(() => {
      // Don't hide if a dropdown is open
      if (!openMenu) {
        setIsMenuHovered(false);
      }
    }, 150);
  }, [openMenu]);

  // Keep menu visible while dropdown is open
  useEffect(() => {
    if (openMenu) {
      setIsMenuHovered(true);
    }
  }, [openMenu]);

  // Cleanup timeout on unmount
  useEffect(() => {
    return () => {
      if (menuHoverTimeoutRef.current) {
        clearTimeout(menuHoverTimeoutRef.current);
      }
    };
  }, []);

  // Window controls state
  const [isMaximized, setIsMaximized] = useState(false);
  const platform = detectPlatform();
  const isMac = platform === 'mac';
  // Tauri 2.0 uses __TAURI_INTERNALS__ instead of __TAURI__
  const isTauri = typeof window !== 'undefined' && ('__TAURI_INTERNALS__' in window || '__TAURI__' in window);

  // Window control handlers
  useEffect(() => {
    if (!isTauri || !useFramelessWindow) return;

    const appWindow = getCurrentWindow();
    appWindow.isMaximized().then(setIsMaximized).catch(() => {});

    const unlistenResize = appWindow.onResized(() => {
      appWindow.isMaximized().then(setIsMaximized).catch(() => {});
    });

    return () => {
      unlistenResize.then((fn) => fn()).catch(() => {});
    };
  }, [isTauri, useFramelessWindow]);

  const handleWindowMinimize = useCallback(async () => {
    console.log('[TopNav] Minimize clicked');
    const inTauri = '__TAURI_INTERNALS__' in window || '__TAURI__' in window;
    if (!inTauri) {
      console.log('[TopNav] Not in Tauri');
      return;
    }
    try {
      const win = getCurrentWindow();
      console.log('[TopNav] Calling minimize on window:', win.label);
      await win.minimize();
      console.log('[TopNav] Minimize success');
    } catch (err) {
      console.error('[TopNav] Minimize error:', err);
    }
  }, []);

  const handleWindowMaximize = useCallback(async () => {
    console.log('[TopNav] Maximize clicked');
    const inTauri = '__TAURI_INTERNALS__' in window || '__TAURI__' in window;
    if (!inTauri) {
      console.log('[TopNav] Not in Tauri');
      return;
    }
    try {
      const win = getCurrentWindow();
      const maximized = await win.isMaximized();
      console.log('[TopNav] isMaximized:', maximized);
      if (maximized) {
        await win.unmaximize();
        setIsMaximized(false);
      } else {
        await win.maximize();
        setIsMaximized(true);
      }
      console.log('[TopNav] Maximize/Unmaximize success');
    } catch (err) {
      console.error('[TopNav] Maximize error:', err);
    }
  }, []);

  const handleWindowClose = useCallback(async () => {
    console.log('[TopNav] Close clicked');
    const inTauri = '__TAURI_INTERNALS__' in window || '__TAURI__' in window;
    if (!inTauri) {
      console.log('[TopNav] Not in Tauri');
      return;
    }
    try {
      const win = getCurrentWindow();
      console.log('[TopNav] Calling close on window:', win.label);
      await win.close();
      console.log('[TopNav] Close success');
    } catch (err) {
      console.error('[TopNav] Close error:', err);
    }
  }, []);

  // Graph store actions
  const undo = useGraphStore((s) => s.undo);
  const redo = useGraphStore((s) => s.redo);
  const canUndo = useGraphStore((s) => s.canUndo);
  const canRedo = useGraphStore((s) => s.canRedo);
  const selectAll = useGraphStore((s) => s.selectAll);
  const deselectAll = useGraphStore((s) => s.deselectAll);
  const loadTemplate = useGraphStore((s) => s.loadTemplate);
  const nodes = useWorkflowStore((s) => {
    const tabId = s.activeTabId || s.tabs[0]?.id;
    const tab = s.tabs.find((t) => t.id === tabId);
    return tab?.nodes ?? [];
  });

  // Log store actions
  const toggleServerLogs = useLogStore((s) => s.toggleOpen);
  const isServerLogsOpen = useLogStore((s) => s.isOpen);

  // Download store actions
  const openModelManager = useDownloadStore((s) => s.openModal);

  // View store
  const currentView = useViewStore((s) => s.currentView);

  // Chat store actions
  const startNewChat = useChatStore((s) => s.startNewChat);
  const triggerFileAttach = useChatStore((s) => s.triggerFileAttach);
  const handleNewChat = useCallback(() => {
    startNewChat();
  }, [startNewChat]);
  const handleAttachFile = useCallback(() => {
    triggerFileAttach();
  }, [triggerFileAttach]);

  const handleNewWorkflow = useCallback(() => {
    // If there are nodes, show confirmation
    if (nodes.length > 0) {
      setConfirmNewWorkflow(true);
      setOpenMenu(null);
    } else {
      const emptyTemplate = getTemplate('empty');
      if (emptyTemplate) {
        loadTemplate(emptyTemplate);
      }
    }
  }, [nodes.length, loadTemplate]);

  const handleConfirmNewWorkflow = useCallback(() => {
    const emptyTemplate = getTemplate('empty');
    if (emptyTemplate) {
      loadTemplate(emptyTemplate);
    }
    setConfirmNewWorkflow(false);
  }, [loadTemplate]);

  // Entrance animation on mount
  useEffect(() => {
    // Left nav enters first
    setTimeout(() => setLeftNavPhase('animating'), 100);
    setTimeout(() => setLeftNavPhase('visible'), 600);

    // Right nav enters with slight delay (stagger)
    setTimeout(() => setRightNavPhase('animating'), 200);
    setTimeout(() => setRightNavPhase('visible'), 700);
  }, []);

  const handleMenuClick = useCallback((menuLabel: string) => {
    setOpenMenu((prev) => (prev === menuLabel ? null : menuLabel));
  }, []);

  const handleMenuHover = useCallback(
    (menuLabel: string) => {
      if (openMenu !== null) {
        setOpenMenu(menuLabel);
      }
    },
    [openMenu]
  );

  const handleCloseMenu = useCallback(() => {
    setOpenMenu(null);
    // Start hide timeout since dropdown closed
    menuHoverTimeoutRef.current = setTimeout(() => {
      setIsMenuHovered(false);
    }, 150);
  }, []);

  // Keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Don't handle if focus is in an input
      if (
        e.target instanceof HTMLInputElement ||
        e.target instanceof HTMLTextAreaElement
      ) {
        return;
      }

      const isMod = e.metaKey || e.ctrlKey;
      const queueCount = useQueueStore.getState().queueCount;
      const toggleDrawer = useQueueStore.getState().toggleDrawer;

      // Shift + Enter: Queue (always available)
      if (e.shiftKey && e.key === 'Enter') {
        e.preventDefault();
        if (connected) {
          onQueue(queueCount);
        }
      }

      // Escape: Stop current job
      if (e.key === 'Escape' && isExecuting) {
        e.preventDefault();
        onStop();
      }

      // CMD/CTRL + Shift + Q: Toggle queue drawer
      if (isMod && e.shiftKey && e.key === 'q') {
        e.preventDefault();
        toggleDrawer();
      }

      // CMD/CTRL + Z: Undo
      if (isMod && !e.shiftKey && e.key === 'z') {
        e.preventDefault();
        undo();
      }

      // CMD/CTRL + Shift + Z: Redo
      if (isMod && e.shiftKey && e.key === 'z') {
        e.preventDefault();
        redo();
      }

      // CMD/CTRL + A: Select All
      if (isMod && e.key === 'a') {
        e.preventDefault();
        selectAll();
      }

      // Escape: Deselect All
      if (e.key === 'Escape') {
        e.preventDefault();
        deselectAll();
      }

      // CMD/CTRL + N: New file
      if (isMod && e.key === 'n') {
        e.preventDefault();
        onNewFile();
      }

      // CMD/CTRL + O: Open file
      if (isMod && e.key === 'o') {
        e.preventDefault();
        onOpenFile();
      }

      // CMD/CTRL + S: Save file
      if (isMod && !e.shiftKey && e.key === 's') {
        e.preventDefault();
        onSaveFile();
      }

      // CMD/CTRL + Shift + S: Save As
      if (isMod && e.shiftKey && e.key === 's') {
        e.preventDefault();
        onSaveAsFile();
      }

      // CMD/CTRL + W: Close tab
      if (isMod && e.key === 'w') {
        e.preventDefault();
        onCloseTab();
      }

      // CMD/CTRL + L: Toggle Server Logs
      if (isMod && e.key === 'l') {
        e.preventDefault();
        toggleServerLogs();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isExecuting, connected, onQueue, onStop, undo, redo, selectAll, deselectAll, onNewFile, onOpenFile, onSaveFile, onSaveAsFile, onCloseTab, toggleServerLogs]);

  // Build recent files submenu
  const recentFilesSubmenu: MenuItem[] = recentFiles.length > 0
    ? [
        ...recentFiles.map((file) => ({
          label: file.name,
          action: () => onOpenRecentFile(file.name),
        })),
        { separator: true, label: '' },
        { label: 'Clear Recent', action: onClearRecentFiles },
      ]
    : [{ label: 'No Recent Files', disabled: true }];

  // Platform-aware keyboard shortcut modifiers
  const mod = isMac ? '⌘' : 'Ctrl+';
  const shift = isMac ? '⇧' : 'Shift+';

  // View-specific menu configurations
  const menuConfig: MenuConfig[] = currentView === 'node'
    ? [
        {
          label: 'File',
          items: [
            { label: 'New', shortcut: `${mod}N`, action: onNewFile },
            { label: 'Open...', shortcut: `${mod}O`, action: onOpenFile },
            { label: 'Open Recent', submenu: recentFilesSubmenu },
            { separator: true, label: '' },
            { label: 'Save', shortcut: `${mod}S`, action: onSaveFile },
            { label: 'Save As...', shortcut: `${shift}${mod}S`, action: onSaveAsFile },
            { separator: true, label: '' },
            { label: 'Close Tab', shortcut: `${mod}W`, action: onCloseTab },
            { separator: true, label: '' },
            { label: 'Export Workflow...', action: onExportFile },
            ...(isTauri ? [
              { separator: true, label: '' },
              { label: 'Exit', shortcut: isMac ? '⌘Q' : 'Alt+F4', action: handleWindowClose },
            ] : []),
          ],
        },
        {
          label: 'Edit',
          items: [
            { label: 'Empty Workflow', action: handleNewWorkflow },
            { separator: true, label: '' },
            { label: 'Undo', shortcut: `${mod}Z`, action: undo, disabled: !canUndo() },
            { label: 'Redo', shortcut: `${shift}${mod}Z`, action: redo, disabled: !canRedo() },
            { separator: true, label: '' },
            { label: 'Cut', shortcut: `${mod}X`, disabled: true },
            { label: 'Copy', shortcut: `${mod}C`, disabled: true },
            { label: 'Paste', shortcut: `${mod}V`, disabled: true },
            { label: 'Delete', shortcut: '⌫', disabled: true },
            { separator: true, label: '' },
            { label: 'Select All', shortcut: `${mod}A`, action: selectAll },
            { label: 'Deselect All', shortcut: 'Esc', action: deselectAll },
            { separator: true, label: '' },
            { label: 'Settings...', shortcut: `${mod},`, action: onOpenSettings },
          ],
        },
        {
          label: 'View',
          items: [
            { label: 'Command Palette', shortcut: `${mod}K`, action: onOpenCommandPalette },
            { label: isServerLogsOpen ? '✓ Server Logs' : 'Server Logs', shortcut: `${mod}L`, action: toggleServerLogs },
            { label: 'Model Manager', action: openModelManager },
            { separator: true, label: '' },
            { label: 'Zoom In', shortcut: `${mod}+`, disabled: true },
            { label: 'Zoom Out', shortcut: `${mod}-`, disabled: true },
            { label: 'Zoom to Fit', shortcut: `${mod}0`, disabled: true },
            { label: 'Zoom to 100%', shortcut: `${mod}1`, disabled: true },
            { separator: true, label: '' },
            { label: 'Toggle Grid', shortcut: `${mod}G`, disabled: true },
            { label: 'Toggle Snap to Grid', shortcut: `${shift}${mod}G`, disabled: true },
            { separator: true, label: '' },
            { label: 'Reset View', disabled: true },
          ],
        },
      ]
    : [
        // Chat view menus
        {
          label: 'File',
          items: [
            { label: 'New Chat', shortcut: `${mod}N`, action: handleNewChat },
            { separator: true, label: '' },
            { label: 'Attach File...', shortcut: `${mod}O`, action: handleAttachFile },
            ...(isTauri ? [
              { separator: true, label: '' },
              { label: 'Exit', shortcut: isMac ? '⌘Q' : 'Alt+F4', action: handleWindowClose },
            ] : []),
          ],
        },
        {
          label: 'Edit',
          items: [
            { label: 'Settings...', shortcut: `${mod},`, action: onOpenSettings },
          ],
        },
        {
          label: 'View',
          items: [
            { label: 'Model Manager', action: openModelManager },
          ],
        },
      ];

  return (
    <>
    <nav className="fixed top-4 left-0 right-0 z-50 flex items-center px-4 pointer-events-none">
      {/* Left side - macOS controls + menu pill */}
      <div className="flex items-center">
        {/* macOS traffic lights */}
        {useFramelessWindow && isTauri && isMac && (
          <div
            className={cn(
              "flex items-center pointer-events-auto mr-2",
              leftNavPhase === 'hidden' && 'opacity-0',
              leftNavPhase === 'animating' && 'nav-entrance-left',
              leftNavPhase === 'visible' && 'opacity-100'
            )}
          >
            <MacWindowControls
              onClose={handleWindowClose}
              onMinimize={handleWindowMinimize}
              onMaximize={handleWindowMaximize}
            />
          </div>
        )}

        {/* View tabs + Menu - shared hover zone */}
        <div
          className={cn(
            "flex items-center pointer-events-auto",
            leftNavPhase === 'hidden' && 'opacity-0',
            leftNavPhase === 'animating' && 'nav-entrance-left',
            leftNavPhase === 'visible' && 'opacity-100'
          )}
          onMouseEnter={handleMenuAreaEnter}
          onMouseLeave={handleMenuAreaLeave}
        >
          <ViewTabs isExpanded={isMenuHovered || openMenu !== null} />

          {/* Left pill - Menu items */}
          <div
            ref={navRef}
            className={cn(
              "flex items-center rounded-full px-2 h-[44px] backdrop-blur-xl ml-2 transition-all duration-200 ease-out overflow-hidden",
              (isMenuHovered || openMenu !== null) ? 'max-w-[300px] opacity-100' : 'max-w-0 opacity-0 px-0 ml-0'
            )}
            style={{
              background: 'rgba(255, 255, 255, 0.08)',
              boxShadow: (isMenuHovered || openMenu !== null) ? '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)' : 'none',
            }}
          >
            {/* Menu items */}
            <div className="flex items-center">
              {menuConfig.map((menu) => (
                <div key={menu.label} className="relative">
                  <button
                    ref={(el) => {
                      buttonRefs.current[menu.label] = el;
                    }}
                    className={cn(
                      'px-3 py-1.5 text-xs rounded-full transition-colors duration-75 cursor-pointer whitespace-nowrap',
                      openMenu === menu.label
                        ? 'bg-surface-1'
                        : 'hover:bg-surface-1/50'
                    )}
                    style={{ color: 'var(--color-text-secondary)' }}
                    onClick={() => handleMenuClick(menu.label)}
                    onMouseEnter={() => handleMenuHover(menu.label)}
                  >
                    {menu.label}
                  </button>
                  <DropdownMenu
                    menu={menu}
                    isOpen={openMenu === menu.label}
                    onClose={handleCloseMenu}
                    buttonRef={{ current: buttonRefs.current[menu.label] }}
                  />
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* TabBar (children) - only show in Node view */}
        {children && currentView === 'node' && (
          <div
            className={cn(
              "pointer-events-auto ml-2",
              leftNavPhase === 'hidden' && 'opacity-0',
              leftNavPhase === 'animating' && 'nav-entrance-left',
              leftNavPhase === 'visible' && 'opacity-100'
            )}
          >
            {children}
          </div>
        )}
      </div>

      {/* Drag region spacer - only in Tauri frameless mode */}
      {useFramelessWindow && isTauri ? (
        <div
          className="flex-1 h-[44px] pointer-events-auto"
          data-tauri-drag-region
          style={{ cursor: 'default' }}
        />
      ) : (
        <div className="flex-1" />
      )}

      {/* Right side - Queue controls + Windows controls */}
      <div className="flex items-center gap-2">
        {/* QueuePill - only show in Node view */}
        {currentView === 'node' && (
          <div
            className={cn(
              "pointer-events-auto",
              rightNavPhase === 'hidden' && 'opacity-0',
              rightNavPhase === 'animating' && 'nav-entrance-right',
              rightNavPhase === 'visible' && 'opacity-100'
            )}
          >
            <QueuePill
              connected={connected}
              isExecuting={isExecuting}
              isStopping={isStopping}
              onQueue={onQueue}
              onStop={onStop}
              onStopAll={onStopAll}
              onOpenDrawer={useQueueStore.getState().toggleDrawer}
            />
          </div>
        )}

        {/* Windows/Linux window controls */}
        {useFramelessWindow && isTauri && !isMac && (
          <div
            className={cn(
              "pointer-events-auto",
              rightNavPhase === 'hidden' && 'opacity-0',
              rightNavPhase === 'animating' && 'nav-entrance-right',
              rightNavPhase === 'visible' && 'opacity-100'
            )}
          >
            <WindowsWindowControls
              isMaximized={isMaximized}
              onClose={handleWindowClose}
              onMinimize={handleWindowMinimize}
              onMaximize={handleWindowMaximize}
            />
          </div>
        )}
      </div>
    </nav>

    {/* Confirmation dialog for new workflow - outside nav to avoid pointer-events-none */}
    {confirmNewWorkflow && (
      <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/50">
        <div
          className="p-4 rounded-lg shadow-xl max-w-sm"
          style={{
            backgroundColor: 'var(--color-surface-0)',
          }}
        >
          <h3 className="text-sm font-medium text-text mb-2">Empty Workflow</h3>
          <p className="text-xs text-text-muted mb-4">
            This will discard your current workflow. Any unsaved changes will be lost.
          </p>
          <div className="flex gap-2 justify-end">
            <button
              onClick={() => setConfirmNewWorkflow(false)}
              className="px-3 py-1.5 text-xs rounded text-text hover:bg-surface-1 transition-colors cursor-pointer"
            >
              Cancel
            </button>
            <button
              onClick={handleConfirmNewWorkflow}
              className="px-3 py-1.5 text-xs rounded bg-accent text-crust hover:opacity-90 transition-opacity cursor-pointer"
            >
              Discard
            </button>
          </div>
        </div>
      </div>
    )}
    </>
  );
}

// macOS-style traffic light controls
function MacWindowControls({
  onClose,
  onMinimize,
  onMaximize,
}: {
  onClose: () => void;
  onMinimize: () => void;
  onMaximize: () => void;
}) {
  const [isHovered, setIsHovered] = useState(false);

  return (
    <div
      className="flex items-center gap-2 px-3 h-[44px] rounded-full backdrop-blur-xl"
      style={{
        background: 'rgba(255, 255, 255, 0.08)',
        boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
      }}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
    >
      {/* Close */}
      <button
        onClick={(e) => {
          e.preventDefault();
          e.stopPropagation();
          onClose();
        }}
        className="w-3 h-3 rounded-full flex items-center justify-center transition-all duration-100"
        style={{ backgroundColor: '#ff5f57' }}
        title="Close"
      >
        {isHovered && (
          <X className="w-2 h-2" stroke="rgba(0,0,0,0.6)" strokeWidth={2} />
        )}
      </button>

      {/* Minimize */}
      <button
        onClick={(e) => {
          e.preventDefault();
          e.stopPropagation();
          onMinimize();
        }}
        className="w-3 h-3 rounded-full flex items-center justify-center transition-all duration-100"
        style={{ backgroundColor: '#febc2e' }}
        title="Minimize"
      >
        {isHovered && (
          <Minus className="w-2 h-2" stroke="rgba(0,0,0,0.6)" strokeWidth={2} />
        )}
      </button>

      {/* Maximize */}
      <button
        onClick={(e) => {
          e.preventDefault();
          e.stopPropagation();
          onMaximize();
        }}
        className="w-3 h-3 rounded-full flex items-center justify-center transition-all duration-100"
        style={{ backgroundColor: '#28c840' }}
        title="Maximize"
      >
        {isHovered && (
          <svg className="w-2 h-2" viewBox="0 0 12 12" fill="none" stroke="rgba(0,0,0,0.6)" strokeWidth="2" strokeLinecap="round">
            <path d="M2 5l4-3 4 3M2 7l4 3 4-3" />
          </svg>
        )}
      </button>
    </div>
  );
}

// Windows/Linux-style window controls - integrated pill design
function WindowsWindowControls({
  isMaximized,
  onClose,
  onMinimize,
  onMaximize,
}: {
  isMaximized: boolean;
  onClose: () => void;
  onMinimize: () => void;
  onMaximize: () => void;
}) {
  return (
    <div
      className="flex items-center h-[44px] rounded-full backdrop-blur-xl overflow-hidden"
      style={{
        background: 'rgba(255, 255, 255, 0.08)',
        boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
      }}
    >
      {/* Minimize */}
      <button
        onClick={(e) => {
          e.preventDefault();
          e.stopPropagation();
          onMinimize();
        }}
        className="h-full w-11 flex items-center justify-center transition-colors duration-75 hover:bg-white/10 rounded-l-full"
        title="Minimize"
      >
        <Minus className="w-4 h-4" style={{ color: 'var(--color-text-secondary)' }} strokeWidth={1.5} />
      </button>

      {/* Maximize/Restore */}
      <button
        onClick={(e) => {
          e.preventDefault();
          e.stopPropagation();
          onMaximize();
        }}
        className="h-full w-11 flex items-center justify-center transition-colors duration-75 hover:bg-white/10"
        title={isMaximized ? 'Restore' : 'Maximize'}
      >
        {isMaximized ? (
          <Copy className="w-3.5 h-3.5" style={{ color: 'var(--color-text-secondary)' }} strokeWidth={1.5} />
        ) : (
          <Square className="w-3.5 h-3.5" style={{ color: 'var(--color-text-secondary)' }} strokeWidth={1.5} />
        )}
      </button>

      {/* Close */}
      <button
        onClick={(e) => {
          e.preventDefault();
          e.stopPropagation();
          onClose();
        }}
        className="h-full w-11 flex items-center justify-center transition-colors duration-75 hover:bg-red-500/80 rounded-r-full"
        title="Close"
      >
        <X className="w-4 h-4" style={{ color: 'var(--color-text-secondary)' }} strokeWidth={1.5} />
      </button>
    </div>
  );
}
