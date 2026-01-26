import { useState, useEffect, useRef, useMemo, useCallback } from 'react';
import { Search, Link } from 'lucide-react';
import { cn } from '@/lib/utils';
import { type PendingConnection } from '@/stores/uiStore';
import { useNodeSpecsContextOptional } from '@/contexts/NodeSpecsContext';
import { nodeSpecToHandles } from '@/types/nodeSpecs';
import { createLogger } from '@/lib/logger';

const log = createLogger('CommandPalette');

interface HandleInfo {
  id: string;
  type: 'source' | 'target';
  dataType: string;
  label: string;
}

interface NodeItem {
  type: string;
  label: string;
  category: string;
  handles: HandleInfo[];
}

// Static fallback nodes - used when context is not available
const staticAllNodes: NodeItem[] = [
  // Primitives - only have outputs
  { type: 'String', label: 'String', category: 'Primitives', handles: [
    { id: 'value', type: 'source', dataType: 'STRING', label: 'VALUE' },
  ]},
  { type: 'Integer', label: 'Integer', category: 'Primitives', handles: [
    { id: 'value', type: 'source', dataType: 'INTEGER', label: 'VALUE' },
  ]},
  { type: 'Float', label: 'Float', category: 'Primitives', handles: [
    { id: 'value', type: 'source', dataType: 'FLOAT', label: 'VALUE' },
  ]},
  { type: 'Boolean', label: 'Boolean', category: 'Primitives', handles: [
    { id: 'value', type: 'source', dataType: 'BOOLEAN', label: 'VALUE' },
  ]},
  { type: 'BigInt', label: 'BigInt', category: 'Primitives', handles: [
    { id: 'value', type: 'source', dataType: 'BIGINT', label: 'VALUE' },
  ]},
  // Math
  { type: 'MathOp', label: 'Math', category: 'Math', handles: [
    { id: 'a', type: 'target', dataType: 'FLOAT', label: 'A' },
    { id: 'b', type: 'target', dataType: 'FLOAT', label: 'B' },
    { id: 'result', type: 'source', dataType: 'FLOAT', label: 'RESULT' },
  ]},
  { type: 'Abs', label: 'Absolute', category: 'Math', handles: [
    { id: 'value', type: 'target', dataType: 'FLOAT', label: 'VALUE' },
    { id: 'result', type: 'source', dataType: 'FLOAT', label: 'RESULT' },
  ]},
  { type: 'OneMinus', label: 'One Minus', category: 'Math', handles: [
    { id: 'value', type: 'target', dataType: 'FLOAT', label: 'VALUE' },
    { id: 'result', type: 'source', dataType: 'FLOAT', label: 'RESULT' },
  ]},
  { type: 'Clamp', label: 'Clamp', category: 'Math', handles: [
    { id: 'value', type: 'target', dataType: 'FLOAT', label: 'VALUE' },
    { id: 'min', type: 'target', dataType: 'FLOAT', label: 'MIN' },
    { id: 'max', type: 'target', dataType: 'FLOAT', label: 'MAX' },
    { id: 'result', type: 'source', dataType: 'FLOAT', label: 'RESULT' },
  ]},
  { type: 'Min', label: 'Min', category: 'Math', handles: [
    { id: 'a', type: 'target', dataType: 'FLOAT', label: 'A' },
    { id: 'b', type: 'target', dataType: 'FLOAT', label: 'B' },
    { id: 'result', type: 'source', dataType: 'FLOAT', label: 'RESULT' },
  ]},
  { type: 'Max', label: 'Max', category: 'Math', handles: [
    { id: 'a', type: 'target', dataType: 'FLOAT', label: 'A' },
    { id: 'b', type: 'target', dataType: 'FLOAT', label: 'B' },
    { id: 'result', type: 'source', dataType: 'FLOAT', label: 'RESULT' },
  ]},
  { type: 'Floor', label: 'Floor', category: 'Math', handles: [
    { id: 'value', type: 'target', dataType: 'FLOAT', label: 'VALUE' },
    { id: 'result', type: 'source', dataType: 'INTEGER', label: 'RESULT' },
  ]},
  { type: 'Ceil', label: 'Ceil', category: 'Math', handles: [
    { id: 'value', type: 'target', dataType: 'FLOAT', label: 'VALUE' },
    { id: 'result', type: 'source', dataType: 'INTEGER', label: 'RESULT' },
  ]},
  { type: 'Round', label: 'Round', category: 'Math', handles: [
    { id: 'value', type: 'target', dataType: 'FLOAT', label: 'VALUE' },
    { id: 'result', type: 'source', dataType: 'INTEGER', label: 'RESULT' },
  ]},
  { type: 'MapRange', label: 'Map Range', category: 'Math', handles: [
    { id: 'value', type: 'target', dataType: 'FLOAT', label: 'VALUE' },
    { id: 'in_min', type: 'target', dataType: 'FLOAT', label: 'IN MIN' },
    { id: 'in_max', type: 'target', dataType: 'FLOAT', label: 'IN MAX' },
    { id: 'out_min', type: 'target', dataType: 'FLOAT', label: 'OUT MIN' },
    { id: 'out_max', type: 'target', dataType: 'FLOAT', label: 'OUT MAX' },
    { id: 'result', type: 'source', dataType: 'FLOAT', label: 'RESULT' },
  ]},
  // Logic
  { type: 'Compare', label: 'Compare', category: 'Logic', handles: [
    { id: 'a', type: 'target', dataType: 'ANY', label: 'A' },
    { id: 'b', type: 'target', dataType: 'ANY', label: 'B' },
    { id: 'result', type: 'source', dataType: 'BOOLEAN', label: 'RESULT' },
  ]},
  { type: 'And', label: 'AND', category: 'Logic', handles: [
    { id: 'a', type: 'target', dataType: 'BOOLEAN', label: 'A' },
    { id: 'b', type: 'target', dataType: 'BOOLEAN', label: 'B' },
    { id: 'result', type: 'source', dataType: 'BOOLEAN', label: 'RESULT' },
  ]},
  { type: 'Or', label: 'OR', category: 'Logic', handles: [
    { id: 'a', type: 'target', dataType: 'BOOLEAN', label: 'A' },
    { id: 'b', type: 'target', dataType: 'BOOLEAN', label: 'B' },
    { id: 'result', type: 'source', dataType: 'BOOLEAN', label: 'RESULT' },
  ]},
  { type: 'Not', label: 'NOT', category: 'Logic', handles: [
    { id: 'value', type: 'target', dataType: 'BOOLEAN', label: 'VALUE' },
    { id: 'result', type: 'source', dataType: 'BOOLEAN', label: 'RESULT' },
  ]},
  { type: 'IfElse', label: 'If / Else', category: 'Logic', handles: [
    { id: 'condition', type: 'target', dataType: 'BOOLEAN', label: 'CONDITION' },
    { id: 'if_true', type: 'target', dataType: 'ANY', label: 'IF TRUE' },
    { id: 'if_false', type: 'target', dataType: 'ANY', label: 'IF FALSE' },
    { id: 'result', type: 'source', dataType: 'ANY', label: 'RESULT' },
  ]},
  { type: 'Switch', label: 'Switch', category: 'Logic', handles: [
    { id: 'index', type: 'target', dataType: 'INTEGER', label: 'INDEX' },
    { id: 'case_0', type: 'target', dataType: 'ANY', label: 'CASE 0' },
    { id: 'case_1', type: 'target', dataType: 'ANY', label: 'CASE 1' },
    { id: 'case_2', type: 'target', dataType: 'ANY', label: 'CASE 2' },
    { id: 'case_3', type: 'target', dataType: 'ANY', label: 'CASE 3' },
    { id: 'result', type: 'source', dataType: 'ANY', label: 'RESULT' },
  ]},
  // Utility
  { type: 'Note', label: 'Note', category: 'Utility', handles: [] },
  { type: 'RandomInt', label: 'Random Int', category: 'Utility', handles: [
    { id: 'min', type: 'target', dataType: 'INTEGER', label: 'MIN' },
    { id: 'max', type: 'target', dataType: 'INTEGER', label: 'MAX' },
    { id: 'value', type: 'source', dataType: 'INTEGER', label: 'VALUE' },
  ]},
  { type: 'RandomSeed', label: 'Random Seed', category: 'Utility', handles: [
    { id: 'seed', type: 'source', dataType: 'BIGINT', label: 'SEED' },
  ]},
  { type: 'Concat', label: 'Concat', category: 'Utility', handles: [
    { id: 'a', type: 'target', dataType: 'STRING', label: 'A' },
    { id: 'b', type: 'target', dataType: 'STRING', label: 'B' },
    { id: 'result', type: 'source', dataType: 'STRING', label: 'RESULT' },
  ]},
  { type: 'StringReplace', label: 'String Replace', category: 'Utility', handles: [
    { id: 'text', type: 'target', dataType: 'STRING', label: 'TEXT' },
    { id: 'find', type: 'target', dataType: 'STRING', label: 'FIND' },
    { id: 'replace', type: 'target', dataType: 'STRING', label: 'REPLACE' },
    { id: 'result', type: 'source', dataType: 'STRING', label: 'RESULT' },
  ]},
  { type: 'Substring', label: 'Substring', category: 'Utility', handles: [
    { id: 'text', type: 'target', dataType: 'STRING', label: 'TEXT' },
    { id: 'start', type: 'target', dataType: 'INTEGER', label: 'START' },
    { id: 'end', type: 'target', dataType: 'INTEGER', label: 'END' },
    { id: 'result', type: 'source', dataType: 'STRING', label: 'RESULT' },
  ]},
  { type: 'Trim', label: 'Trim', category: 'Utility', handles: [
    { id: 'text', type: 'target', dataType: 'STRING', label: 'TEXT' },
    { id: 'result', type: 'source', dataType: 'STRING', label: 'RESULT' },
  ]},
  { type: 'Contains', label: 'Contains', category: 'Utility', handles: [
    { id: 'text', type: 'target', dataType: 'STRING', label: 'TEXT' },
    { id: 'search', type: 'target', dataType: 'STRING', label: 'SEARCH' },
    { id: 'result', type: 'source', dataType: 'BOOLEAN', label: 'RESULT' },
  ]},
  { type: 'RegexMatch', label: 'Regex Match', category: 'Utility', handles: [
    { id: 'text', type: 'target', dataType: 'STRING', label: 'TEXT' },
    { id: 'pattern', type: 'target', dataType: 'STRING', label: 'PATTERN' },
    { id: 'result', type: 'source', dataType: 'BOOLEAN', label: 'RESULT' },
  ]},
  { type: 'RegexExtract', label: 'Regex Extract', category: 'Utility', handles: [
    { id: 'text', type: 'target', dataType: 'STRING', label: 'TEXT' },
    { id: 'pattern', type: 'target', dataType: 'STRING', label: 'PATTERN' },
    { id: 'result', type: 'source', dataType: 'STRING', label: 'RESULT' },
  ]},
  { type: 'RegexReplace', label: 'Regex Replace', category: 'Utility', handles: [
    { id: 'text', type: 'target', dataType: 'STRING', label: 'TEXT' },
    { id: 'pattern', type: 'target', dataType: 'STRING', label: 'PATTERN' },
    { id: 'replace', type: 'target', dataType: 'STRING', label: 'REPLACE' },
    { id: 'result', type: 'source', dataType: 'STRING', label: 'RESULT' },
  ]},
  { type: 'PreviewText', label: 'Preview Text', category: 'Utility', handles: [
    { id: 'text', type: 'target', dataType: 'STRING', label: 'TEXT' },
  ]},
  // Models
  { type: 'ModelSelector', label: 'Model Selector', category: 'Models', handles: [
    { id: 'model', type: 'source', dataType: 'MODEL', label: 'MODEL' },
  ]},
  // Conditioning
  { type: 'CLIPTextEncode', label: 'CLIP Text Encode', category: 'Conditioning', handles: [
    { id: 'text', type: 'target', dataType: 'STRING', label: 'TEXT' },
    { id: 'negative_text', type: 'target', dataType: 'STRING', label: 'NEG TEXT' },
    { id: 'positive', type: 'source', dataType: 'POSITIVE', label: 'POSITIVE' },
    { id: 'negative', type: 'source', dataType: 'NEGATIVE', label: 'NEGATIVE' },
  ]},
  // Latent
  { type: 'EmptyLatentImage', label: 'Empty Latent', category: 'Latent', handles: [
    { id: 'width', type: 'target', dataType: 'INTEGER', label: 'WIDTH' },
    { id: 'height', type: 'target', dataType: 'INTEGER', label: 'HEIGHT' },
    { id: 'latent', type: 'source', dataType: 'LATENT', label: 'LATENT' },
  ]},
  // Sampling
  { type: 'KSampler', label: 'KSampler', category: 'Sampling', handles: [
    { id: 'model', type: 'target', dataType: 'MODEL', label: 'MODEL' },
    { id: 'positive', type: 'target', dataType: 'POSITIVE', label: 'POSITIVE' },
    { id: 'negative', type: 'target', dataType: 'NEGATIVE', label: 'NEGATIVE' },
    { id: 'latent', type: 'target', dataType: 'LATENT', label: 'LATENT' },
    { id: 'steps', type: 'target', dataType: 'INTEGER', label: 'STEPS' },
    { id: 'cfg', type: 'target', dataType: 'FLOAT', label: 'CFG' },
    { id: 'seed', type: 'target', dataType: 'BIGINT', label: 'SEED' },
    { id: 'image', type: 'source', dataType: 'IMAGE', label: 'IMAGE' },
  ]},
  // Output
  { type: 'SaveImage', label: 'Save Image', category: 'Output', handles: [
    { id: 'filename_prefix', type: 'target', dataType: 'STRING', label: 'PREFIX' },
    { id: 'image', type: 'target', dataType: 'IMAGE', label: 'IMAGE' },
  ]},
  { type: 'PreviewImage', label: 'Preview Image', category: 'Output', handles: [
    { id: 'image', type: 'target', dataType: 'IMAGE', label: 'IMAGE' },
  ]},
];

// Check if two types are compatible
function isTypeCompatible(sourceType: string, targetType: string): boolean {
  if (sourceType === targetType) return true;
  if (sourceType === 'ANY' || targetType === 'ANY') return true;
  return false;
}

// Find compatible handle for a node given a pending connection
function findCompatibleHandle(node: NodeItem, pendingConnection: PendingConnection): HandleInfo | null {
  // If we're dragging from a source, we need a target (and vice versa)
  const needHandleType = pendingConnection.handleType === 'source' ? 'target' : 'source';

  for (const handle of node.handles) {
    if (handle.type === needHandleType && isTypeCompatible(pendingConnection.dataType, handle.dataType)) {
      return handle;
    }
  }
  return null;
}

interface FilteredNode extends NodeItem {
  matchingHandle: HandleInfo | null;
}

interface CommandPaletteProps {
  isOpen: boolean;
  onClose: () => void;
  onSelectNode: (type: string, connectToHandle?: string) => void;
  pendingConnection?: PendingConnection | null;
}

export function CommandPalette({ isOpen, onClose, onSelectNode, pendingConnection }: CommandPaletteProps) {
  const [query, setQuery] = useState('');
  const [selectedIndex, setSelectedIndex] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLDivElement>(null);

  // Get nodes from context or use static fallback
  const specsContext = useNodeSpecsContextOptional();
  const specs = specsContext?.specs;
  const allNodes = useMemo((): NodeItem[] => {
    if (specs && specs.length > 0) {
      // Convert specs to NodeItem format
      return specs.map(spec => ({
        type: spec.type,
        label: spec.label,
        category: spec.category,
        handles: nodeSpecToHandles(spec),
      }));
    }
    // Fall back to static nodes
    return staticAllNodes;
  }, [specs]);

  // Filter nodes based on query and pending connection
  const filteredNodes = useMemo(() => {
    let nodes: FilteredNode[] = allNodes.map(node => ({
      ...node,
      matchingHandle: pendingConnection ? findCompatibleHandle(node, pendingConnection) : null,
    }));

    // If there's a pending connection, only show compatible nodes
    if (pendingConnection) {
      nodes = nodes.filter(node => node.matchingHandle !== null);
    }

    // Apply text query filter
    if (query.trim()) {
      const lowerQuery = query.toLowerCase();
      nodes = nodes.filter(
        (node) =>
          node.label.toLowerCase().includes(lowerQuery) ||
          node.type.toLowerCase().includes(lowerQuery) ||
          node.category.toLowerCase().includes(lowerQuery)
      );
    }

    // Sort nodes by label within their categories
    nodes.sort((a, b) => a.label.localeCompare(b.label));

    return nodes;
  }, [query, pendingConnection, allNodes]);

  // Group nodes by category and sort categories alphabetically
  const groupedNodes = useMemo(() => {
    const groups = new Map<string, FilteredNode[]>();

    filteredNodes.forEach(node => {
      const category = node.category || 'Uncategorized';
      if (!groups.has(category)) {
        groups.set(category, []);
      }
      groups.get(category)!.push(node);
    });

    // Convert to array and sort categories alphabetically
    const sorted = Array.from(groups.entries())
      .sort((a, b) => {
        const categoryA = a[0].toLowerCase();
        const categoryB = b[0].toLowerCase();
        return categoryA.localeCompare(categoryB);
      })
      .map(([category, nodes]) => ({ category, nodes }));

    // Debug: log the sorted categories
    log.debug('Sorted categories:', sorted.map(g => g.category));

    return sorted;
  }, [filteredNodes]);

  // Reset state when opening
  useEffect(() => {
    if (isOpen) {
      setQuery('');
      setSelectedIndex(0);
      // Focus input after a small delay to ensure it's mounted
      setTimeout(() => inputRef.current?.focus(), 10);
    }
  }, [isOpen]);

  // Create flat list for keyboard navigation
  const flatNodes = useMemo(() => {
    return groupedNodes.flatMap(group => group.nodes);
  }, [groupedNodes]);

  // Reset selected index when filtered results change
  useEffect(() => {
    setSelectedIndex(0);
  }, [flatNodes.length]);

  // Scroll selected item into view
  useEffect(() => {
    if (listRef.current && flatNodes.length > 0) {
      // Find the actual DOM element corresponding to the selected flat index
      const allButtons = listRef.current.querySelectorAll('button[data-node-button]');
      const selectedEl = allButtons[selectedIndex] as HTMLElement;
      if (selectedEl) {
        selectedEl.scrollIntoView({ block: 'nearest' });
      }
    }
  }, [selectedIndex, flatNodes.length]);

  // Handle keyboard navigation
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      switch (e.key) {
        case 'ArrowDown':
          e.preventDefault();
          setSelectedIndex((i) => Math.min(i + 1, flatNodes.length - 1));
          break;
        case 'ArrowUp':
          e.preventDefault();
          setSelectedIndex((i) => Math.max(i - 1, 0));
          break;
        case 'Enter':
          e.preventDefault();
          if (flatNodes[selectedIndex]) {
            const node = flatNodes[selectedIndex];
            onSelectNode(node.type, node.matchingHandle?.id);
            onClose();
          }
          break;
        case 'Escape':
          e.preventDefault();
          onClose();
          break;
      }
    },
    [flatNodes, selectedIndex, onSelectNode, onClose]
  );

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-[200] flex items-start justify-center pt-[20vh]">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/40 backdrop-blur-sm"
        onClick={onClose}
      />

      {/* Palette */}
      <div
        className="relative w-full max-w-lg rounded-xl shadow-2xl overflow-hidden"
        style={{
          backgroundColor: 'var(--color-surface-0)',
          border: '1px solid var(--color-overlay-0)',
        }}
      >
        {/* Connection indicator */}
        {pendingConnection && (
          <div
            className="px-4 py-2 flex items-center gap-2 text-xs"
            style={{
              backgroundColor: 'var(--color-surface-1)',
              borderBottom: '1px solid var(--color-overlay-0)',
            }}
          >
            <Link className="w-3.5 h-3.5 text-accent" />
            <span className="text-text-muted">
              Connect from <span className="text-text font-medium">{pendingConnection.dataType}</span>
            </span>
          </div>
        )}

        {/* Search input */}
        <div
          className="flex items-center gap-3 px-4 py-3"
          style={{ borderBottom: '1px solid var(--color-overlay-0)' }}
        >
          <Search className="w-5 h-5 text-text-muted flex-shrink-0" />
          <input
            ref={inputRef}
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder={pendingConnection ? "Search compatible nodes..." : "Search nodes..."}
            className="flex-1 bg-transparent text-sm text-text placeholder-text-muted outline-none"
            autoComplete="off"
            spellCheck={false}
          />
          <kbd
            className="px-1.5 py-0.5 text-[10px] rounded"
            style={{
              backgroundColor: 'var(--color-surface-1)',
              color: 'var(--color-text-muted)',
            }}
          >
            ESC
          </kbd>
        </div>

        {/* Results */}
        <div
          ref={listRef}
          className="max-h-[50vh] overflow-y-auto py-2"
        >
          {flatNodes.length === 0 ? (
            <div className="px-4 py-8 text-center text-sm text-text-muted">
              {pendingConnection ? 'No compatible nodes found' : 'No nodes found'}
            </div>
          ) : (
            groupedNodes.map((group, groupIndex) => (
              <div key={group.category}>
                {/* Category header */}
                <div
                  className="px-4 py-1.5 text-[10px] font-semibold uppercase tracking-wider"
                  style={{
                    color: 'var(--color-text-muted)',
                    backgroundColor: 'var(--color-surface-1)',
                    ...(groupIndex > 0 && { marginTop: '4px' })
                  }}
                >
                  {group.category}
                </div>
                {/* Nodes in this category */}
                {group.nodes.map((node) => {
                  const flatIndex = flatNodes.indexOf(node);
                  return (
                    <button
                      key={node.type}
                      data-node-button
                      onClick={() => {
                        onSelectNode(node.type, node.matchingHandle?.id);
                        onClose();
                      }}
                      onMouseEnter={() => setSelectedIndex(flatIndex)}
                      className={cn(
                        'w-full px-4 py-2 flex items-center justify-between text-left transition-colors',
                        selectedIndex === flatIndex && 'bg-[var(--color-accent)]'
                      )}
                    >
                      <div className="flex items-center gap-2">
                        <span
                          className="text-sm"
                          style={{
                            color: selectedIndex === flatIndex ? 'var(--color-crust)' : 'var(--color-text)',
                          }}
                        >
                          {node.label}
                        </span>
                        {node.matchingHandle && (
                          <span
                            className="text-[10px] px-1.5 py-0.5 rounded"
                            style={{
                              backgroundColor: selectedIndex === flatIndex
                                ? 'rgba(0,0,0,0.2)'
                                : 'var(--color-surface-1)',
                              color: selectedIndex === flatIndex
                                ? 'var(--color-crust)'
                                : 'var(--color-text-muted)',
                            }}
                          >
                            → {node.matchingHandle.label}
                          </span>
                        )}
                      </div>
                    </button>
                  );
                })}
              </div>
            ))
          )}
        </div>

        {/* Footer hint */}
        <div
          className="px-4 py-2 flex items-center gap-4 text-[10px] text-text-muted"
          style={{ borderTop: '1px solid var(--color-overlay-0)' }}
        >
          <span className="flex items-center gap-1">
            <kbd className="px-1 py-0.5 rounded bg-surface-1">↑↓</kbd>
            navigate
          </span>
          <span className="flex items-center gap-1">
            <kbd className="px-1 py-0.5 rounded bg-surface-1">↵</kbd>
            select
          </span>
          <span className="flex items-center gap-1">
            <kbd className="px-1 py-0.5 rounded bg-surface-1">esc</kbd>
            close
          </span>
        </div>
      </div>
    </div>
  );
}
