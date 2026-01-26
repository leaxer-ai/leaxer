import { memo, useState, useCallback, useEffect, useMemo } from 'react';
import { createPortal } from 'react-dom';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { Prism as SyntaxHighlighter } from 'react-syntax-highlighter';
import { X, Copy, Download, Check, ChevronDown, History } from 'lucide-react';
import type { ChatArtifact, ArtifactVersion } from '@/types/chat';

interface ArtifactModalProps {
  artifact: ChatArtifact;
  onClose: () => void;
}

// Theme-aware syntax highlighting style
const createThemeAwareStyle = (): Record<string, React.CSSProperties> => ({
  'code[class*="language-"]': {
    color: 'var(--color-text)',
    background: 'none',
    fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace',
    fontSize: '13px',
    textAlign: 'left',
    whiteSpace: 'pre',
    wordSpacing: 'normal',
    wordBreak: 'normal',
    wordWrap: 'normal',
    lineHeight: '1.6',
    tabSize: 2,
    hyphens: 'none',
  },
  'pre[class*="language-"]': {
    color: 'var(--color-text)',
    background: 'var(--color-surface-1)',
    fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace',
    fontSize: '13px',
    textAlign: 'left',
    whiteSpace: 'pre',
    wordSpacing: 'normal',
    wordBreak: 'normal',
    wordWrap: 'normal',
    lineHeight: '1.6',
    tabSize: 2,
    hyphens: 'none',
    padding: '1rem',
    margin: '1rem 0',
    overflow: 'auto',
    borderRadius: '0.75rem',
  },
  comment: { color: 'var(--color-overlay-2)' },
  punctuation: { color: 'var(--color-overlay-2)' },
  property: { color: 'var(--color-red)' },
  tag: { color: 'var(--color-red)' },
  boolean: { color: 'var(--color-peach)' },
  number: { color: 'var(--color-peach)' },
  string: { color: 'var(--color-green)' },
  operator: { color: 'var(--color-sky)' },
  keyword: { color: 'var(--color-mauve)' },
  function: { color: 'var(--color-blue)' },
  'class-name': { color: 'var(--color-yellow)' },
  variable: { color: 'var(--color-text)' },
});

export const ArtifactModal = memo(({ artifact, onClose }: ArtifactModalProps) => {
  const [copied, setCopied] = useState(false);
  const [isVisible, setIsVisible] = useState(false);
  const [showVersionDropdown, setShowVersionDropdown] = useState(false);

  // Build all versions including current
  const allVersions = useMemo(() => {
    const versions: Array<ArtifactVersion & { isCurrent?: boolean }> = [];

    // Add previous versions
    if (artifact.versions) {
      versions.push(...artifact.versions);
    }

    // Add current version
    versions.push({
      version: artifact.currentVersion || versions.length + 1,
      title: artifact.title,
      content: artifact.content,
      created_at: artifact.created_at,
      isCurrent: true,
    });

    return versions;
  }, [artifact]);

  const [selectedVersionIndex, setSelectedVersionIndex] = useState(allVersions.length - 1);

  // Reset to latest version when artifact changes
  useEffect(() => {
    setSelectedVersionIndex(allVersions.length - 1);
  }, [allVersions.length]);

  const selectedVersion = allVersions[selectedVersionIndex];
  const hasVersions = allVersions.length > 1;

  // Animate entrance
  useEffect(() => {
    requestAnimationFrame(() => setIsVisible(true));
  }, []);

  // Handle escape key
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        handleClose();
      }
    };
    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, []);

  const handleClose = useCallback(() => {
    setIsVisible(false);
    setTimeout(onClose, 200);
  }, [onClose]);

  const handleBackdropClick = useCallback((e: React.MouseEvent) => {
    if (e.target === e.currentTarget) {
      handleClose();
    }
  }, [handleClose]);

  const handleCopy = useCallback(() => {
    navigator.clipboard.writeText(selectedVersion?.content || artifact.content);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }, [selectedVersion, artifact.content]);

  const handleDownload = useCallback(() => {
    const title = selectedVersion?.title || artifact.title;
    const content = selectedVersion?.content || artifact.content;
    const versionSuffix = selectedVersion && !('isCurrent' in selectedVersion && selectedVersion.isCurrent)
      ? `-v${selectedVersion.version}`
      : '';

    const filename = title
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-|-$/g, '') + versionSuffix + '.md';

    const blob = new Blob([content], { type: 'text/markdown' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }, [selectedVersion, artifact.title, artifact.content]);

  const syntaxStyle = createThemeAwareStyle();

  return createPortal(
    <div
      className={`fixed inset-0 z-50 flex items-center justify-center p-4 md:p-8 transition-all duration-200 ${
        isVisible ? 'opacity-100' : 'opacity-0'
      }`}
      style={{ background: 'rgba(0, 0, 0, 0.8)' }}
      onClick={handleBackdropClick}
    >
      <div
        className={`relative w-full max-w-4xl max-h-[90vh] flex flex-col rounded-2xl overflow-hidden transition-all duration-200 ${
          isVisible ? 'scale-100 translate-y-0' : 'scale-95 translate-y-4'
        }`}
        style={{
          background: 'var(--color-base)',
          boxShadow: '0 25px 50px -12px rgba(0, 0, 0, 0.5)',
        }}
      >
        {/* Header */}
        <div
          className="flex items-center gap-3 px-6 py-4 border-b flex-shrink-0"
          style={{ borderColor: 'var(--color-surface-2)' }}
        >
          <div className="flex-1 min-w-0">
            <h2
              className="text-lg font-semibold truncate flex items-center gap-2"
              style={{ color: 'var(--color-text)' }}
            >
              {artifact.status === 'generating' || artifact.status === 'pending' ? (
                <>
                  <span className="animate-pulse">Generating document...</span>
                </>
              ) : (
                selectedVersion?.title || artifact.title
              )}
            </h2>
          </div>

          {/* Version selector */}
          {hasVersions && artifact.status === 'complete' && (
            <div className="relative">
              <button
                onClick={() => setShowVersionDropdown(!showVersionDropdown)}
                className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg transition-colors hover:bg-white/10 text-sm"
                style={{ color: 'var(--color-text-secondary)' }}
              >
                <History className="w-4 h-4" />
                <span>v{selectedVersion?.version || allVersions.length}</span>
                <ChevronDown className="w-3.5 h-3.5" />
              </button>

              {showVersionDropdown && (
                <>
                  <div
                    className="fixed inset-0 z-10"
                    onClick={() => setShowVersionDropdown(false)}
                  />
                  <div
                    className="absolute right-0 top-full mt-1 py-1 rounded-lg shadow-xl z-20 min-w-[160px]"
                    style={{
                      background: 'var(--color-surface-0)',
                      border: '1px solid var(--color-surface-2)',
                    }}
                  >
                    {allVersions.map((version, index) => (
                      <button
                        key={version.version}
                        onClick={() => {
                          setSelectedVersionIndex(index);
                          setShowVersionDropdown(false);
                        }}
                        className={`w-full px-3 py-2 text-left text-sm transition-colors hover:bg-white/10 flex items-center justify-between gap-2 ${
                          index === selectedVersionIndex ? 'bg-white/5' : ''
                        }`}
                        style={{ color: 'var(--color-text)' }}
                      >
                        <span className="truncate">
                          {version.title}
                        </span>
                        <span
                          className="flex-shrink-0 text-xs px-1.5 py-0.5 rounded"
                          style={{
                            background: 'isCurrent' in version && version.isCurrent
                              ? 'rgba(var(--color-accent-rgb), 0.2)'
                              : 'var(--color-surface-1)',
                            color: 'isCurrent' in version && version.isCurrent
                              ? 'var(--color-accent)'
                              : 'var(--color-text-muted)',
                          }}
                        >
                          v{version.version}
                        </span>
                      </button>
                    ))}
                  </div>
                </>
              )}
            </div>
          )}

          <div className="flex items-center gap-1">
            <button
              onClick={handleCopy}
              className="p-2 rounded-lg transition-colors hover:bg-white/10"
              style={{ color: 'var(--color-text-secondary)' }}
              title={copied ? 'Copied!' : 'Copy markdown'}
            >
              {copied ? (
                <Check className="w-5 h-5" />
              ) : (
                <Copy className="w-5 h-5" />
              )}
            </button>
            <button
              onClick={handleDownload}
              className="p-2 rounded-lg transition-colors hover:bg-white/10"
              style={{ color: 'var(--color-text-secondary)' }}
              title="Download as .md"
            >
              <Download className="w-5 h-5" />
            </button>
            <button
              onClick={handleClose}
              className="p-2 rounded-lg transition-colors hover:bg-white/10"
              style={{ color: 'var(--color-text-secondary)' }}
              title="Close"
            >
              <X className="w-5 h-5" />
            </button>
          </div>
        </div>

        {/* Content */}
        <div
          className="flex-1 overflow-y-auto px-6 py-6"
          style={{ color: 'var(--color-text)' }}
        >
          <div className="prose prose-invert max-w-none">
            <ReactMarkdown
              remarkPlugins={[remarkGfm]}
              key={selectedVersionIndex}
              components={{
                code({ className, children, ...props }) {
                  const match = /language-(\w+)/.exec(className || '');
                  const isInline = !match && !className;

                  if (isInline) {
                    return (
                      <code
                        className="px-1.5 py-0.5 rounded text-[13px] font-mono"
                        style={{
                          backgroundColor: 'var(--color-surface-2)',
                          color: 'var(--color-peach)',
                        }}
                        {...props}
                      >
                        {children}
                      </code>
                    );
                  }

                  return (
                    <SyntaxHighlighter
                      style={syntaxStyle}
                      language={match ? match[1] : 'text'}
                      PreTag="div"
                    >
                      {String(children).replace(/\n$/, '')}
                    </SyntaxHighlighter>
                  );
                },
                p({ children }) {
                  return <p className="mb-4 leading-relaxed">{children}</p>;
                },
                ul({ children }) {
                  return <ul className="list-disc pl-6 mb-4 space-y-2">{children}</ul>;
                },
                ol({ children }) {
                  return <ol className="list-decimal pl-6 mb-4 space-y-2">{children}</ol>;
                },
                li({ children }) {
                  return <li className="pl-1">{children}</li>;
                },
                h1({ children }) {
                  return <h1 className="text-2xl font-bold mb-4 mt-8 first:mt-0">{children}</h1>;
                },
                h2({ children }) {
                  return <h2 className="text-xl font-semibold mb-3 mt-6 first:mt-0">{children}</h2>;
                },
                h3({ children }) {
                  return <h3 className="text-lg font-semibold mb-2 mt-5 first:mt-0">{children}</h3>;
                },
                a({ href, children }) {
                  return (
                    <a
                      href={href}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="underline underline-offset-2"
                      style={{ color: 'var(--color-blue)' }}
                    >
                      {children}
                    </a>
                  );
                },
                blockquote({ children }) {
                  return (
                    <blockquote
                      className="border-l-4 pl-4 my-4 py-1"
                      style={{
                        borderColor: 'var(--color-overlay-1)',
                        color: 'var(--color-text-secondary)',
                      }}
                    >
                      {children}
                    </blockquote>
                  );
                },
                hr() {
                  return (
                    <hr
                      className="my-6"
                      style={{ borderColor: 'var(--color-overlay-0)' }}
                    />
                  );
                },
                table({ children }) {
                  return (
                    <div className="overflow-x-auto my-4">
                      <table
                        className="w-full text-sm"
                        style={{
                          border: '1px solid var(--color-surface-2)',
                          borderRadius: '8px',
                          borderCollapse: 'separate',
                          borderSpacing: 0,
                          overflow: 'hidden',
                        }}
                      >
                        {children}
                      </table>
                    </div>
                  );
                },
                th({ children }) {
                  return (
                    <th
                      className="px-3 py-2 text-left font-medium"
                      style={{
                        backgroundColor: 'var(--color-surface-1)',
                        borderBottom: '1px solid var(--color-surface-2)',
                      }}
                    >
                      {children}
                    </th>
                  );
                },
                td({ children }) {
                  return (
                    <td className="px-3 py-2 border-b border-[var(--color-surface-2)]">
                      {children}
                    </td>
                  );
                },
              }}
            >
              {selectedVersion?.content || artifact.content}
            </ReactMarkdown>
          </div>
        </div>

      </div>
    </div>,
    document.body
  );
});

ArtifactModal.displayName = 'ArtifactModal';
