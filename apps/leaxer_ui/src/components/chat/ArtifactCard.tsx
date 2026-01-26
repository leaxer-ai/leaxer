import { memo, useState, useCallback } from 'react';
import { FileText, Copy, Download, Check, Loader2, History } from 'lucide-react';
import type { ChatArtifact } from '@/types/chat';
import { ArtifactModal } from './ArtifactModal';

interface ArtifactCardProps {
  artifact: ChatArtifact;
}

export const ArtifactCard = memo(({ artifact }: ArtifactCardProps) => {
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [copied, setCopied] = useState(false);

  const isGenerating = artifact.status === 'pending' || artifact.status === 'generating';
  const isComplete = artifact.status === 'complete';
  const isError = artifact.status === 'error';

  // Calculate line count
  const lineCount = artifact.content ? artifact.content.split('\n').length : 0;
  const sourceCount = artifact.sources?.length || 0;
  const versionCount = (artifact.versions?.length || 0) + 1; // Current + previous versions
  const hasVersions = artifact.versions && artifact.versions.length > 0;

  const handleCopy = useCallback((e: React.MouseEvent) => {
    e.stopPropagation();
    navigator.clipboard.writeText(artifact.content);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }, [artifact.content]);

  const handleDownload = useCallback((e: React.MouseEvent) => {
    e.stopPropagation();
    // Sanitize title for filename
    const filename = artifact.title
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-|-$/g, '') + '.md';

    const blob = new Blob([artifact.content], { type: 'text/markdown' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }, [artifact.title, artifact.content]);

  const handleCardClick = useCallback(() => {
    // Allow opening modal during generation to see streaming content
    if (isComplete || isGenerating) {
      setIsModalOpen(true);
    }
  }, [isComplete, isGenerating]);

  return (
    <>
      <div
        onClick={handleCardClick}
        className={`group flex items-center gap-3 p-3 rounded-xl transition-all duration-200 ${
          isComplete || isGenerating ? 'cursor-pointer hover:bg-white/10' : ''
        }`}
        style={{
          background: 'rgba(255, 255, 255, 0.06)',
          boxShadow: 'inset 0 1px 0 rgba(255, 255, 255, 0.05)',
        }}
      >
        {/* Icon */}
        <div
          className="flex items-center justify-center w-10 h-10 rounded-lg flex-shrink-0"
          style={{
            background: isGenerating
              ? 'rgba(255, 255, 255, 0.1)'
              : 'rgba(var(--color-accent-rgb), 0.15)',
          }}
        >
          {isGenerating ? (
            <Loader2
              className="w-5 h-5 animate-spin"
              style={{ color: 'var(--color-text-secondary)' }}
            />
          ) : (
            <FileText
              className="w-5 h-5"
              style={{ color: 'var(--color-accent)' }}
            />
          )}
        </div>

        {/* Content */}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-0.5">
            <span
              className="text-sm font-medium truncate"
              style={{ color: 'var(--color-text)' }}
            >
              {isGenerating ? 'Creating document...' : artifact.title}
            </span>
            {isError && (
              <span
                className="px-1.5 py-0.5 rounded text-[10px] font-medium"
                style={{
                  background: 'rgba(var(--color-red-rgb), 0.2)',
                  color: 'var(--color-red)',
                }}
              >
                Error
              </span>
            )}
          </div>
          <div
            className="text-xs flex items-center gap-1"
            style={{ color: 'var(--color-text-muted)' }}
          >
            {isGenerating ? (
              lineCount > 0 ? (
                <>{lineCount} lines · Generating...</>
              ) : (
                'Compiling research...'
              )
            ) : isError ? (
              'Failed to generate document'
            ) : (
              <>
                {lineCount} lines
                {sourceCount > 0 && <> · {sourceCount} sources</>}
                {hasVersions && (
                  <span className="inline-flex items-center gap-0.5 ml-1">
                    <History className="w-3 h-3" />
                    <span>v{versionCount}</span>
                  </span>
                )}
              </>
            )}
          </div>
        </div>

        {/* Action buttons - visible on hover when complete */}
        {isComplete && (
          <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
            <button
              onClick={handleCopy}
              className="p-1.5 rounded-md transition-colors hover:bg-white/10"
              style={{ color: 'var(--color-text-secondary)' }}
              title={copied ? 'Copied!' : 'Copy markdown'}
            >
              {copied ? (
                <Check className="w-4 h-4" />
              ) : (
                <Copy className="w-4 h-4" />
              )}
            </button>
            <button
              onClick={handleDownload}
              className="p-1.5 rounded-md transition-colors hover:bg-white/10"
              style={{ color: 'var(--color-text-secondary)' }}
              title="Download as .md"
            >
              <Download className="w-4 h-4" />
            </button>
          </div>
        )}
      </div>

      {/* Modal */}
      {isModalOpen && (
        <ArtifactModal
          artifact={artifact}
          onClose={() => setIsModalOpen(false)}
        />
      )}
    </>
  );
});

ArtifactCard.displayName = 'ArtifactCard';
