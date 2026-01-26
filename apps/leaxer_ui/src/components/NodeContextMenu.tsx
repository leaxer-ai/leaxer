import { useState, useRef, useEffect, useCallback, useMemo } from 'react';
import { ChevronRight, Search } from 'lucide-react';
import { cn } from '@/lib/utils';
import { workflowTemplates, type WorkflowTemplate } from '../data/workflowTemplates';
import { useGraphStore } from '../stores/graphStore';
import { useWorkflowStore } from '../stores/workflowStore';
import { useUIStore } from '../stores/uiStore';
import { useNodeSpecsContextOptional } from '@/contexts/NodeSpecsContext';
import { GROUP_COLORS } from './nodes/GroupNode';
import type { NodeSpec } from '@/types/nodeSpecs';

// Tree structure for infinite nesting
interface CategoryTreeNode {
  name: string;
  fullPath: string;
  children: Map<string, CategoryTreeNode>;
  nodes: { type: string; label: string }[];
}

interface NodeCategory {
  name: string;
  nodes: { type: string; label: string }[];
}

// Fallback categories when API is not available (alphabetically sorted)
const fallbackCategories: NodeCategory[] = [
  {
    name: 'Conditioning',
    nodes: [{ type: 'CLIPTextEncode', label: 'CLIP Text Encode' }]
  },
  {
    name: 'Latent',
    nodes: [{ type: 'EmptyLatentImage', label: 'Empty Latent' }]
  },
  {
    name: 'Logic',
    nodes: [
      { type: 'And', label: 'AND' },
      { type: 'Compare', label: 'Compare' },
      { type: 'IfElse', label: 'If / Else' },
      { type: 'Not', label: 'NOT' },
      { type: 'Or', label: 'OR' },
      { type: 'Switch', label: 'Switch' },
    ]
  },
  {
    name: 'Math',
    nodes: [
      { type: 'Abs', label: 'Absolute' },
      { type: 'Ceil', label: 'Ceil' },
      { type: 'Clamp', label: 'Clamp' },
      { type: 'Floor', label: 'Floor' },
      { type: 'MapRange', label: 'Map Range' },
      { type: 'MathOp', label: 'Math' },
      { type: 'Max', label: 'Max' },
      { type: 'Min', label: 'Min' },
      { type: 'OneMinus', label: 'One Minus' },
      { type: 'Round', label: 'Round' },
    ]
  },
  {
    name: 'Models',
    nodes: [{ type: 'ModelSelector', label: 'Model Selector' }]
  },
  {
    name: 'Output',
    nodes: [
      { type: 'PreviewImage', label: 'Preview Image' },
      { type: 'SaveImage', label: 'Save Image' },
    ]
  },
  {
    name: 'Primitives',
    nodes: [
      { type: 'BigInt', label: 'BigInt' },
      { type: 'Boolean', label: 'Boolean' },
      { type: 'Float', label: 'Float' },
      { type: 'Integer', label: 'Integer' },
      { type: 'String', label: 'String' },
    ]
  },
  {
    name: 'Sampling',
    nodes: [{ type: 'KSampler', label: 'KSampler' }]
  },
  {
    name: 'Utility',
    nodes: [
      { type: 'Concat', label: 'Concat' },
      { type: 'Contains', label: 'Contains' },
      { type: 'Note', label: 'Note' },
      { type: 'PreviewText', label: 'Preview Text' },
      { type: 'RandomInt', label: 'Random Int' },
      { type: 'RandomSeed', label: 'Random Seed' },
      { type: 'RegexExtract', label: 'Regex Extract' },
      { type: 'RegexMatch', label: 'Regex Match' },
      { type: 'RegexReplace', label: 'Regex Replace' },
      { type: 'StringReplace', label: 'String Replace' },
      { type: 'Substring', label: 'Substring' },
      { type: 'Trim', label: 'Trim' },
    ]
  }
];

interface NodeContextMenuProps {
  position: { x: number; y: number } | null;
  nodeId?: string;
  nodeType?: string;
  onClose: () => void;
  onAddNode: (type: string, position: { x: number; y: number }) => void;
  onDeleteNode?: (nodeId: string) => void;
  onDuplicateNode?: (nodeId: string) => void;
  onRenameNode?: (nodeId: string) => void;
  onToggleBypassed?: (nodeId: string) => void;
  onChangeGroupColor?: (nodeId: string, color: string) => void;
  onGroupSelected?: () => void;
  onCopy?: () => void;
  onPaste?: () => void;
  hasSelection?: boolean;
  hasClipboard?: boolean;
  isBypassed?: boolean;
}

interface MenuItemProps {
  label: string;
  shortcut?: string;
  hasSubmenu?: boolean;
  onSelect?: () => void;
  onMouseEnter?: () => void;
  selected?: boolean;
  disabled?: boolean;
  danger?: boolean;
}

function MenuItem({
  label,
  shortcut,
  hasSubmenu,
  onSelect,
  onMouseEnter,
  selected,
  disabled,
  danger
}: MenuItemProps) {
  return (
    <button
      className={cn(
        'w-full px-3 py-1.5 flex items-center justify-between text-left',
        'text-[12px] transition-colors duration-100',
        disabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer',
        selected && !disabled && 'bg-[var(--color-accent)]'
      )}
      style={{
        color: selected
          ? 'var(--color-crust)'
          : danger
            ? 'var(--color-error)'
            : 'var(--color-text)',
      }}
      onClick={disabled ? undefined : onSelect}
      onMouseEnter={onMouseEnter}
      disabled={disabled}
    >
      <span>{label}</span>
      <span className="flex items-center gap-2">
        {shortcut && (
          <span
            className="text-[11px]"
            style={{
              color: selected ? 'var(--color-crust)' : 'var(--color-text-muted)'
            }}
          >
            {shortcut}
          </span>
        )}
        {hasSubmenu && <ChevronRight className="w-3.5 h-3.5" />}
      </span>
    </button>
  );
}

function Divider() {
  return (
    <div
      className="my-1 mx-2 h-px"
      style={{ backgroundColor: 'var(--color-overlay-0)' }}
    />
  );
}

// Build a tree structure from flat node specs using category_path
function buildCategoryTree(specs: NodeSpec[], isCustom: boolean): CategoryTreeNode {
  const root: CategoryTreeNode = {
    name: 'root',
    fullPath: '',
    children: new Map(),
    nodes: [],
  };

  for (const spec of specs) {
    const category = spec.category || 'Uncategorized';
    const specIsCustom = category.startsWith('Custom');

    if (specIsCustom !== isCustom) continue;

    // Use category_path if available, otherwise parse from category string
    let path = spec.category_path;
    if (!path || path.length === 0) {
      path = category.split('/').filter(Boolean);
    }

    // For custom nodes, skip the "Custom" prefix in the tree
    if (isCustom && path[0] === 'Custom') {
      path = path.slice(1);
    }

    // If path is empty after processing, put in "General"
    if (path.length === 0) {
      path = ['General'];
    }

    // Navigate/create the tree path
    let current = root;
    let fullPath = '';
    for (const segment of path) {
      fullPath = fullPath ? `${fullPath}/${segment}` : segment;
      if (!current.children.has(segment)) {
        current.children.set(segment, {
          name: segment,
          fullPath,
          children: new Map(),
          nodes: [],
        });
      }
      current = current.children.get(segment)!;
    }

    // Add the node to the deepest category
    current.nodes.push({
      type: spec.type,
      label: spec.label,
    });
  }

  // Sort children and nodes recursively
  const sortTree = (node: CategoryTreeNode) => {
    // Sort nodes alphabetically
    node.nodes.sort((a, b) => a.label.localeCompare(b.label));

    // Sort children alphabetically and recurse
    const sortedChildren = new Map(
      [...node.children.entries()].sort((a, b) => a[0].localeCompare(b[0]))
    );
    node.children = sortedChildren;

    for (const child of node.children.values()) {
      sortTree(child);
    }
  };

  sortTree(root);
  return root;
}

// Recursive submenu component for infinite nesting
interface RecursiveSubMenuProps {
  treeNode: CategoryTreeNode;
  position: { x: number; y: number };
  depth: number;
  onAddNode: (type: string) => void;
  onClose: () => void;
}

function RecursiveSubMenu({ treeNode, position, depth, onAddNode, onClose }: RecursiveSubMenuProps) {
  const [hoveredChild, setHoveredChild] = useState<string | null>(null);
  const [childPosition, setChildPosition] = useState<{ x: number; y: number } | null>(null);
  const [hoveredNodeIndex, setHoveredNodeIndex] = useState(-1);
  const childRefs = useRef<Record<string, HTMLDivElement | null>>({});
  const menuRef = useRef<HTMLDivElement>(null);

  const handleChildHover = useCallback((childName: string, el: HTMLDivElement | null) => {
    setHoveredChild(childName);
    setHoveredNodeIndex(-1);

    if (el) {
      const rect = el.getBoundingClientRect();
      const viewportWidth = window.innerWidth;
      const submenuWidth = 160;

      // Check if submenu would overflow right edge
      let x = rect.right - 4;
      if (x + submenuWidth > viewportWidth - 10) {
        // Position to the left instead
        x = rect.left - submenuWidth + 4;
      }

      setChildPosition({ x, y: rect.top - 4 });
    }
  }, []);

  const handleNodeHover = useCallback((index: number) => {
    setHoveredNodeIndex(index);
    setHoveredChild(null);
  }, []);

  const children = Array.from(treeNode.children.values());
  const hasChildren = children.length > 0;
  const hasNodes = treeNode.nodes.length > 0;
  const hoveredChildNode = hoveredChild ? treeNode.children.get(hoveredChild) : null;

  return (
    <>
      <div
        ref={menuRef}
        className="fixed min-w-[160px] py-1 rounded-md shadow-lg"
        style={{
          left: position.x,
          top: position.y,
          backgroundColor: 'var(--color-surface-0)',
          zIndex: 51 + depth,
        }}
      >
        {/* Render subcategories first */}
        {children.map((child) => (
          <div
            key={child.fullPath}
            ref={(el) => { childRefs.current[child.name] = el; }}
          >
            <MenuItem
              label={child.name}
              hasSubmenu
              selected={hoveredChild === child.name}
              onMouseEnter={() => handleChildHover(child.name, childRefs.current[child.name])}
            />
          </div>
        ))}

        {/* Divider between subcategories and nodes */}
        {hasChildren && hasNodes && <Divider />}

        {/* Render nodes */}
        {treeNode.nodes.map((node, index) => (
          <MenuItem
            key={node.type}
            label={node.label}
            selected={hoveredNodeIndex === index}
            onMouseEnter={() => handleNodeHover(index)}
            onSelect={() => {
              onAddNode(node.type);
              onClose();
            }}
          />
        ))}
      </div>

      {/* Render child submenu recursively */}
      {hoveredChildNode && childPosition && (
        <RecursiveSubMenu
          treeNode={hoveredChildNode}
          position={childPosition}
          depth={depth + 1}
          onAddNode={onAddNode}
          onClose={onClose}
        />
      )}
    </>
  );
}

export function NodeContextMenu({
  position,
  nodeId,
  nodeType,
  onClose,
  onAddNode,
  onDeleteNode,
  onDuplicateNode,
  onRenameNode,
  onToggleBypassed,
  onChangeGroupColor,
  onGroupSelected,
  onCopy,
  onPaste,
  hasSelection,
  hasClipboard,
  isBypassed,
}: NodeContextMenuProps) {
  const [selectedItem, setSelectedItem] = useState<string | null>(null);
  const [showAddNodeSubmenu, setShowAddNodeSubmenu] = useState(false);
  const [addNodeSubmenuPos, setAddNodeSubmenuPos] = useState<{ x: number; y: number } | null>(null);
  const [hoveredTopCategory, setHoveredTopCategory] = useState<string | null>(null);
  const [topCategoryPos, setTopCategoryPos] = useState<{ x: number; y: number } | null>(null);
  const [, setHoveredNodeIndex] = useState(-1);

  // Template submenu state
  const [showTemplateSubmenu, setShowTemplateSubmenu] = useState(false);
  const [templateSubmenuPos, setTemplateSubmenuPos] = useState<{ x: number; y: number } | null>(null);
  const [selectedTemplateIndex, setSelectedTemplateIndex] = useState(-1);
  const [confirmTemplate, setConfirmTemplate] = useState<WorkflowTemplate | null>(null);

  // Color submenu state (for Group nodes)
  const [showColorSubmenu, setShowColorSubmenu] = useState(false);
  const [colorSubmenuPos, setColorSubmenuPos] = useState<{ x: number; y: number } | null>(null);
  const colorItemRef = useRef<HTMLDivElement>(null);
  const colorSubmenuRef = useRef<HTMLDivElement>(null);

  const loadTemplate = useGraphStore((s) => s.loadTemplate);
  const nodes = useWorkflowStore((s) => {
    const tabId = s.activeTabId || s.tabs[0]?.id;
    const tab = s.tabs.find((t) => t.id === tabId);
    return tab?.nodes ?? [];
  });
  const openCommandPalette = useUIStore((s) => s.openCommandPalette);

  // Get node specs from context
  const specsContext = useNodeSpecsContextOptional();
  const specs = specsContext?.specs;

  // Build category trees from specs, separating Core and Custom
  const { coreTree, customTree } = useMemo(() => {
    if (!specs || specs.length === 0) {
      // Build fallback tree from fallbackCategories
      const fallbackTree: CategoryTreeNode = {
        name: 'root',
        fullPath: '',
        children: new Map(),
        nodes: [],
      };
      for (const cat of fallbackCategories) {
        fallbackTree.children.set(cat.name, {
          name: cat.name,
          fullPath: cat.name,
          children: new Map(),
          nodes: cat.nodes,
        });
      }
      const emptyTree: CategoryTreeNode = {
        name: 'root',
        fullPath: '',
        children: new Map(),
        nodes: [],
      };
      return { coreTree: fallbackTree, customTree: emptyTree };
    }

    return {
      coreTree: buildCategoryTree(specs, false),
      customTree: buildCategoryTree(specs, true),
    };
  }, [specs]);

  const menuRef = useRef<HTMLDivElement>(null);
  const addNodeSubmenuRef = useRef<HTMLDivElement>(null);
  const addNodeItemRef = useRef<HTMLDivElement>(null);
  const templateItemRef = useRef<HTMLDivElement>(null);
  const templateSubmenuRef = useRef<HTMLDivElement>(null);
  const topCategoryRefs = useRef<Record<string, HTMLDivElement | null>>({});

  const isNodeContext = !!nodeId;

  // Handle click outside - close menu when clicking anywhere outside
  useEffect(() => {
    if (!position || confirmTemplate) return;

    const handleClickOutside = (e: MouseEvent) => {
      const target = e.target as Node;
      // Check if click is inside main menu
      const isOutsideMenu = !menuRef.current?.contains(target);
      // Check if click is inside template submenu
      const isOutsideTemplateSubmenu = !templateSubmenuRef.current?.contains(target);
      // Check if click is inside color submenu
      const isOutsideColorSubmenu = !colorSubmenuRef.current?.contains(target);

      // For recursive submenus, we check by z-index classes
      const clickedSubmenu = (e.target as HTMLElement).closest('[style*="z-index: 5"]');

      if (isOutsideMenu && isOutsideTemplateSubmenu && isOutsideColorSubmenu && !clickedSubmenu) {
        onClose();
      }
    };

    const timer = setTimeout(() => {
      document.addEventListener('mousedown', handleClickOutside);
    }, 0);

    return () => {
      clearTimeout(timer);
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [position, onClose, confirmTemplate]);

  // Handle keyboard
  useEffect(() => {
    if (!position) return;

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        onClose();
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [position, onClose]);

  // Reset state when menu closes
  useEffect(() => {
    if (!position) {
      setSelectedItem(null);
      setShowAddNodeSubmenu(false);
      setAddNodeSubmenuPos(null);
      setHoveredTopCategory(null);
      setTopCategoryPos(null);
      setHoveredNodeIndex(-1);
      setShowTemplateSubmenu(false);
      setTemplateSubmenuPos(null);
      setShowColorSubmenu(false);
      setColorSubmenuPos(null);
      setSelectedTemplateIndex(-1);
      setConfirmTemplate(null);
    }
  }, [position]);

  const handleAddNodeHover = useCallback(() => {
    setSelectedItem('addnode');
    setShowAddNodeSubmenu(true);
    setShowTemplateSubmenu(false);

    if (addNodeItemRef.current) {
      const rect = addNodeItemRef.current.getBoundingClientRect();
      setAddNodeSubmenuPos({
        x: rect.right - 4,
        y: rect.top - 4,
      });
    }
  }, []);

  const handleTemplateHover = useCallback(() => {
    setSelectedItem('template');
    setShowTemplateSubmenu(true);
    setShowAddNodeSubmenu(false);
    setHoveredTopCategory(null);

    if (templateItemRef.current) {
      const rect = templateItemRef.current.getBoundingClientRect();
      setTemplateSubmenuPos({
        x: rect.right - 4,
        y: rect.top - 4,
      });
    }
  }, []);

  const handleTopCategoryHover = useCallback((categoryKey: string, el: HTMLDivElement | null) => {
    setHoveredTopCategory(categoryKey);
    setHoveredNodeIndex(-1);

    if (el) {
      const rect = el.getBoundingClientRect();
      const viewportWidth = window.innerWidth;
      const submenuWidth = 160;

      // Check if submenu would overflow right edge
      let x = rect.right - 4;
      if (x + submenuWidth > viewportWidth - 10) {
        x = rect.left - submenuWidth + 4;
      }

      setTopCategoryPos({ x, y: rect.top - 4 });
    }
  }, []);

  const handleMainItemHover = useCallback((item: string) => {
    setSelectedItem(item);
    setShowAddNodeSubmenu(false);
    setShowTemplateSubmenu(false);
    setHoveredTopCategory(null);
  }, []);

  const handleTemplateSelect = useCallback((template: WorkflowTemplate) => {
    // If workflow is empty, load directly. Otherwise show confirmation.
    if (nodes.length === 0) {
      loadTemplate(template);
      onClose();
    } else {
      setConfirmTemplate(template);
    }
  }, [nodes.length, loadTemplate, onClose]);

  const handleConfirmTemplate = useCallback(() => {
    if (confirmTemplate) {
      loadTemplate(confirmTemplate);
      onClose();
    }
  }, [confirmTemplate, loadTemplate, onClose]);

  const handleOpenSearch = useCallback(() => {
    onClose();
    openCommandPalette();
  }, [onClose, openCommandPalette]);

  const handleAddNode = useCallback((type: string) => {
    if (position) {
      onAddNode(type, position);
      onClose();
    }
  }, [position, onAddNode, onClose]);

  const handleColorHover = useCallback(() => {
    setSelectedItem('color');
    setShowColorSubmenu(true);

    if (colorItemRef.current) {
      const rect = colorItemRef.current.getBoundingClientRect();
      setColorSubmenuPos({
        x: rect.right - 4,
        y: rect.top - 4,
      });
    }
  }, []);

  const handleColorSelect = useCallback((color: string) => {
    if (nodeId && onChangeGroupColor) {
      onChangeGroupColor(nodeId, color);
    }
    onClose();
  }, [nodeId, onChangeGroupColor, onClose]);

  // Helper to get a more visible version of the color for swatches
  const getSwatchColor = (rgba: string) => {
    return rgba.replace(/[\d.]+\)$/, '0.8)');
  };

  if (!position) {
    return null;
  }

  // Get top-level categories from trees
  const coreTopCategories = Array.from(coreTree.children.values());
  const customTopCategories = Array.from(customTree.children.values());

  // Find hovered category tree node
  const getHoveredTreeNode = (): CategoryTreeNode | null => {
    if (!hoveredTopCategory) return null;
    const isCustom = hoveredTopCategory.startsWith('custom:');
    const catName = isCustom ? hoveredTopCategory.slice(7) : hoveredTopCategory;
    const tree = isCustom ? customTree : coreTree;
    return tree.children.get(catName) || null;
  };
  const hoveredTreeNode = getHoveredTreeNode();

  // Node context menu (right-clicked on a node)
  if (isNodeContext) {
    const isGroupNode = nodeType === 'Group';

    return (
      <>
        <div
          ref={menuRef}
          className="fixed z-50 min-w-[160px] py-1 rounded-md shadow-lg"
          style={{
            left: position.x,
            top: position.y,
            backgroundColor: 'var(--color-surface-0)',
          }}
        >
          <MenuItem
            label="Rename"
            selected={selectedItem === 'rename'}
            onMouseEnter={() => { setSelectedItem('rename'); setShowColorSubmenu(false); }}
            onSelect={() => {
              onRenameNode?.(nodeId);
              onClose();
            }}
          />
          <MenuItem
            label="Duplicate"
            shortcut="⌘D"
            selected={selectedItem === 'duplicate'}
            onMouseEnter={() => { setSelectedItem('duplicate'); setShowColorSubmenu(false); }}
            onSelect={() => {
              onDuplicateNode?.(nodeId);
              onClose();
            }}
          />
          <MenuItem
            label={isBypassed ? "Enable Node" : "Bypass Node"}
            shortcut="B"
            selected={selectedItem === 'bypass'}
            onMouseEnter={() => { setSelectedItem('bypass'); setShowColorSubmenu(false); }}
            onSelect={() => {
              onToggleBypassed?.(nodeId);
              onClose();
            }}
          />
          <MenuItem
            label="Copy"
            shortcut="⌘C"
            selected={selectedItem === 'copy'}
            onMouseEnter={() => { setSelectedItem('copy'); setShowColorSubmenu(false); }}
            onSelect={() => {
              onCopy?.();
              onClose();
            }}
          />
          <MenuItem
            label="Group Selected"
            shortcut="⌘G"
            selected={selectedItem === 'group'}
            onMouseEnter={() => { setSelectedItem('group'); setShowColorSubmenu(false); }}
            disabled={!hasSelection}
            onSelect={() => {
              onGroupSelected?.();
              onClose();
            }}
          />

          {/* Color option for Group nodes */}
          {isGroupNode && (
            <div ref={colorItemRef}>
              <MenuItem
                label="Color"
                hasSubmenu
                selected={selectedItem === 'color'}
                onMouseEnter={handleColorHover}
              />
            </div>
          )}

          <Divider />

          <MenuItem
            label="Delete"
            shortcut="⌫"
            selected={selectedItem === 'delete'}
            onMouseEnter={() => { setSelectedItem('delete'); setShowColorSubmenu(false); }}
            onSelect={() => {
              onDeleteNode?.(nodeId);
              onClose();
            }}
          />
        </div>

        {/* Color submenu for Group nodes */}
        {isGroupNode && showColorSubmenu && colorSubmenuPos && (
          <div
            ref={colorSubmenuRef}
            className="fixed z-[51] p-2 rounded-md shadow-lg"
            style={{
              left: colorSubmenuPos.x,
              top: colorSubmenuPos.y,
              backgroundColor: 'var(--color-surface-0)',
            }}
          >
            <div className="flex gap-1.5 flex-wrap" style={{ width: 140 }}>
              {GROUP_COLORS.map((color) => (
                <button
                  key={color.name}
                  onClick={() => handleColorSelect(color.value)}
                  className="w-5 h-5 rounded-sm border border-white/20 hover:scale-110 transition-transform"
                  style={{ backgroundColor: getSwatchColor(color.value) }}
                  title={color.name}
                />
              ))}
            </div>
          </div>
        )}
      </>
    );
  }

  // Canvas context menu
  return (
    <>
      {/* Main menu */}
      <div
        ref={menuRef}
        className="fixed z-50 min-w-[180px] py-1 rounded-md shadow-lg"
        style={{
          left: position.x,
          top: position.y,
          backgroundColor: 'var(--color-surface-0)',
        }}
      >
        <div ref={addNodeItemRef}>
          <MenuItem
            label="Add node"
            hasSubmenu
            selected={selectedItem === 'addnode'}
            onMouseEnter={handleAddNodeHover}
          />
        </div>
        <div ref={templateItemRef}>
          <MenuItem
            label="Add template"
            hasSubmenu
            selected={selectedItem === 'template'}
            onMouseEnter={handleTemplateHover}
          />
        </div>

        <Divider />

        <MenuItem
          label="Group selected"
          shortcut="⌘G"
          selected={selectedItem === 'group'}
          onMouseEnter={() => handleMainItemHover('group')}
          disabled={!hasSelection}
          onSelect={() => {
            onGroupSelected?.();
            onClose();
          }}
        />
        <MenuItem
          label="Copy"
          shortcut="⌘C"
          selected={selectedItem === 'copy'}
          onMouseEnter={() => handleMainItemHover('copy')}
          disabled={!hasSelection}
          onSelect={() => {
            onCopy?.();
            onClose();
          }}
        />
        <MenuItem
          label="Paste"
          shortcut="⌘V"
          selected={selectedItem === 'paste'}
          onMouseEnter={() => handleMainItemHover('paste')}
          disabled={!hasClipboard}
          onSelect={() => {
            onPaste?.();
            onClose();
          }}
        />
      </div>

      {/* Categories submenu (level 2) - now with infinite nesting support */}
      {showAddNodeSubmenu && addNodeSubmenuPos && (
        <div
          ref={addNodeSubmenuRef}
          className="fixed z-[51] min-w-[140px] py-1 rounded-md shadow-lg"
          style={{
            left: addNodeSubmenuPos.x,
            top: addNodeSubmenuPos.y,
            backgroundColor: 'var(--color-surface-0)',
          }}
        >
          <button
            className={cn(
              'w-full px-3 py-1.5 flex items-center gap-2 text-left',
              'text-[12px] transition-colors duration-100 cursor-pointer',
              'hover:bg-[var(--color-accent)] hover:text-[var(--color-crust)]'
            )}
            style={{ color: 'var(--color-text)' }}
            onClick={handleOpenSearch}
          >
            <Search className="w-3.5 h-3.5" />
            <span>Search...</span>
            <span className="ml-auto text-[10px] text-text-muted">⌘K</span>
          </button>
          <div
            className="my-1 mx-2 h-px"
            style={{ backgroundColor: 'var(--color-overlay-0)' }}
          />

          {/* Core section label */}
          <div
            className="px-3 py-1 text-[10px] font-medium uppercase tracking-wider"
            style={{ color: 'var(--color-text-muted)' }}
          >
            Core
          </div>

          {coreTopCategories.map((category) => (
            <div
              key={category.fullPath}
              ref={(el) => { topCategoryRefs.current[category.name] = el; }}
            >
              <MenuItem
                label={category.name}
                hasSubmenu
                selected={hoveredTopCategory === category.name}
                onMouseEnter={() => handleTopCategoryHover(category.name, topCategoryRefs.current[category.name])}
              />
            </div>
          ))}

          {/* Custom section - only show if there are custom nodes */}
          {customTopCategories.length > 0 && (
            <>
              <div
                className="my-1 mx-2 h-px"
                style={{ backgroundColor: 'var(--color-overlay-0)' }}
              />
              <div
                className="px-3 py-1 text-[10px] font-medium uppercase tracking-wider"
                style={{ color: 'var(--color-text-muted)' }}
              >
                Custom
              </div>
              {customTopCategories.map((category) => (
                <div
                  key={`custom-${category.fullPath}`}
                  ref={(el) => { topCategoryRefs.current[`custom:${category.name}`] = el; }}
                >
                  <MenuItem
                    label={category.name}
                    hasSubmenu
                    selected={hoveredTopCategory === `custom:${category.name}`}
                    onMouseEnter={() => handleTopCategoryHover(`custom:${category.name}`, topCategoryRefs.current[`custom:${category.name}`])}
                  />
                </div>
              ))}
            </>
          )}
        </div>
      )}

      {/* Recursive submenu for categories - supports infinite nesting */}
      {hoveredTopCategory && hoveredTreeNode && topCategoryPos && (
        <RecursiveSubMenu
          treeNode={hoveredTreeNode}
          position={topCategoryPos}
          depth={1}
          onAddNode={handleAddNode}
          onClose={onClose}
        />
      )}

      {/* Template submenu */}
      {showTemplateSubmenu && templateSubmenuPos && (
        <div
          ref={templateSubmenuRef}
          className="fixed z-[51] min-w-[160px] py-1 rounded-md shadow-lg"
          style={{
            left: templateSubmenuPos.x,
            top: templateSubmenuPos.y,
            backgroundColor: 'var(--color-surface-0)',
          }}
        >
          {workflowTemplates.filter(t => t.id !== 'empty').map((template, index) => (
            <MenuItem
              key={template.id}
              label={template.name}
              selected={selectedTemplateIndex === index}
              onMouseEnter={() => setSelectedTemplateIndex(index)}
              onSelect={() => handleTemplateSelect(template)}
            />
          ))}
        </div>
      )}

      {/* Confirmation dialog */}
      {confirmTemplate && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/50">
          <div
            className="p-4 rounded-lg shadow-xl max-w-sm"
            style={{
              backgroundColor: 'var(--color-surface-0)',
            }}
          >
            <h3 className="text-sm font-medium text-text mb-2">Load Template</h3>
            <p className="text-xs text-text-muted mb-4">
              This will replace your current workflow with "{confirmTemplate.name}".
              Any unsaved changes will be lost.
            </p>
            <div className="flex gap-2 justify-end">
              <button
                onClick={() => setConfirmTemplate(null)}
                className="px-3 py-1.5 text-xs rounded text-text hover:bg-surface-1 transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={handleConfirmTemplate}
                className="px-3 py-1.5 text-xs rounded bg-accent text-crust hover:opacity-90 transition-opacity"
              >
                Load Template
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}

export default NodeContextMenu;
