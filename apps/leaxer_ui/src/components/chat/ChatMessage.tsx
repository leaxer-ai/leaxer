/* eslint-disable react-hooks/rules-of-hooks */
// Note: This component has role-specific hook usage which ESLint flags.
// The hooks after the early returns are role-specific and intentional.
import { memo, useState, useCallback, useMemo, useEffect, useRef } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { Prism as SyntaxHighlighter } from 'react-syntax-highlighter';
import { Copy, Check, Volume2, VolumeX, RotateCcw, ChevronDown, ChevronRight, ChevronUp, GitBranch, Loader2, ExternalLink, FileText, Pencil } from 'lucide-react';
import { cn } from '@/lib/utils';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { useSettingsStore } from '@/stores/settingsStore';
import type { ChatMessage as ChatMessageType, ChatAttachment } from '@/types/chat';
import { formatFileSize } from '@/types/chat';
import { ArtifactCard } from './ArtifactCard';

interface LLMModel {
  name: string;
  path: string;
  size?: string;
}

// Theme-aware syntax highlighting style using CSS variables
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
  prolog: { color: 'var(--color-overlay-2)' },
  doctype: { color: 'var(--color-overlay-2)' },
  cdata: { color: 'var(--color-overlay-2)' },
  punctuation: { color: 'var(--color-overlay-2)' },
  property: { color: 'var(--color-red)' },
  tag: { color: 'var(--color-red)' },
  boolean: { color: 'var(--color-peach)' },
  number: { color: 'var(--color-peach)' },
  constant: { color: 'var(--color-peach)' },
  symbol: { color: 'var(--color-peach)' },
  deleted: { color: 'var(--color-red)' },
  selector: { color: 'var(--color-green)' },
  'attr-name': { color: 'var(--color-green)' },
  string: { color: 'var(--color-green)' },
  char: { color: 'var(--color-green)' },
  builtin: { color: 'var(--color-green)' },
  inserted: { color: 'var(--color-green)' },
  operator: { color: 'var(--color-sky)' },
  entity: { color: 'var(--color-sky)', cursor: 'help' },
  url: { color: 'var(--color-sky)' },
  '.language-css .token.string': { color: 'var(--color-sky)' },
  '.style .token.string': { color: 'var(--color-sky)' },
  atrule: { color: 'var(--color-blue)' },
  'attr-value': { color: 'var(--color-blue)' },
  keyword: { color: 'var(--color-mauve)' },
  function: { color: 'var(--color-blue)' },
  'class-name': { color: 'var(--color-yellow)' },
  regex: { color: 'var(--color-peach)' },
  important: { color: 'var(--color-peach)', fontWeight: 'bold' },
  variable: { color: 'var(--color-text)' },
  bold: { fontWeight: 'bold' },
  italic: { fontStyle: 'italic' },
});

interface ChatMessageProps {
  message: ChatMessageType;
  onFollowUp?: (message: string) => void;
  onRegenerate?: (messageId: string) => void;
  onEdit?: (messageId: string) => void;
  onBranch?: (messageId: string, model: string) => void;
  isLastMessage?: boolean;
  isLastUserMessage?: boolean;
  /** Current selected model - used to filter branch options (can't branch with same model) */
  currentModel?: string | null;
}

export const ChatMessage = ({ message, onFollowUp, onRegenerate, onEdit, onBranch, isLastMessage, isLastUserMessage, currentModel }: ChatMessageProps) => {
  const isUser = message.role === 'user';
  const isSystem = message.role === 'system';
  const isAssistant = message.role === 'assistant';
  const [copied, setCopied] = useState(false);
  const [isSpeaking, setIsSpeaking] = useState(false);
  const [hidingContent, setHidingContent] = useState<string | null>(null);
  const hideIntervalRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Branch dropdown state
  const [isBranchOpen, setIsBranchOpen] = useState(false);
  const [branchModels, setBranchModels] = useState<LLMModel[]>([]);
  const [loadingModels, setLoadingModels] = useState(false);
  const branchDropdownRef = useRef<HTMLDivElement>(null);
  const getApiBaseUrl = useSettingsStore((s) => s.getApiBaseUrl);

  // Fetch models when branch dropdown opens
  useEffect(() => {
    if (isBranchOpen && branchModels.length === 0) {
      const fetchModels = async () => {
        setLoadingModels(true);
        try {
          const apiBaseUrl = getApiBaseUrl();
          const response = await fetch(`${apiBaseUrl}/api/models/llms`);
          if (response.ok) {
            const data = await response.json();
            const models: LLMModel[] = (data.models || []).map((m: { name: string; path: string; size_human?: string }) => ({
              name: m.name,
              path: m.path,
              size: m.size_human,
            }));
            setBranchModels(models);
          }
        } catch (err) {
          console.error('Failed to fetch models for branch:', err);
        } finally {
          setLoadingModels(false);
        }
      };
      fetchModels();
    }
  }, [isBranchOpen, branchModels.length, getApiBaseUrl]);

  // Close branch dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (branchDropdownRef.current && !branchDropdownRef.current.contains(event.target as Node)) {
        setIsBranchOpen(false);
      }
    };
    if (isBranchOpen) {
      document.addEventListener('mousedown', handleClickOutside);
      return () => document.removeEventListener('mousedown', handleClickOutside);
    }
  }, [isBranchOpen]);

  const handleBranchSelect = useCallback((model: LLMModel) => {
    setIsBranchOpen(false);
    onBranch?.(message.id, model.path);
  }, [message.id, onBranch]);

  // Character-by-character deletion animation
  useEffect(() => {
    if (message.isHiding && hidingContent === null) {
      // Start the hiding animation
      setHidingContent(message.content);
    }

    if (message.isHiding && hidingContent !== null) {
      if (hidingContent.length === 0) {
        // Animation complete
        if (hideIntervalRef.current) {
          clearInterval(hideIntervalRef.current);
        }
        return;
      }

      // Calculate speed: longer content = faster deletion
      // Min 1ms, max 20ms per character
      const contentLength = message.content.length;
      const charsPerTick = Math.max(1, Math.ceil(contentLength / 50)); // Remove more chars at once for long content
      const interval = Math.max(1, Math.min(20, 1000 / contentLength));

      hideIntervalRef.current = setTimeout(() => {
        setHidingContent((prev) => {
          if (!prev) return '';
          return prev.slice(0, -charsPerTick);
        });
      }, interval);
    }

    return () => {
      if (hideIntervalRef.current) {
        clearTimeout(hideIntervalRef.current);
      }
    };
  }, [message.isHiding, message.content, hidingContent]);

  // Show follow-ups only for the last assistant message that's not streaming or hiding
  const showFollowUps = isAssistant && isLastMessage && !message.isStreaming && !message.isHiding && message.followUps && message.followUps.length > 0;

  // Copy handler for user messages
  const handleUserCopy = useCallback(() => {
    navigator.clipboard.writeText(message.content);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }, [message.content]);

  // Branch select handler for user messages
  const handleUserBranchSelect = useCallback((model: LLMModel) => {
    setIsBranchOpen(false);
    onBranch?.(message.id, model.path);
  }, [message.id, onBranch]);

  // User messages: bubble style, right-aligned
  if (isUser) {
    return (
      <div className="group flex w-full mb-6 justify-end">
        <div className="max-w-[80%] flex flex-col items-end gap-2">
          {/* Attachments preview */}
          {message.attachments && message.attachments.length > 0 && (
            <div className="flex flex-wrap gap-2 justify-end">
              {message.attachments.map((attachment) => (
                <MessageAttachment key={attachment.id} attachment={attachment} />
              ))}
            </div>
          )}

          {/* Message text */}
          {message.content && (
            <div
              className="rounded-2xl rounded-br-md px-4 py-2.5 text-[15px] leading-[1.8]"
              style={{
                background: 'rgba(255, 255, 255, 0.08)',
                boxShadow: 'inset 0 1px 0 rgba(255, 255, 255, 0.1)',
                color: 'var(--color-text)',
              }}
            >
              <p className="whitespace-pre-wrap">{message.content}</p>
            </div>
          )}

          {/* Action buttons for user messages - copy and branch for all, edit only for last */}
          <div className="flex items-center gap-1">
            <TooltipProvider delayDuration={300}>
              <Tooltip>
                <TooltipTrigger asChild>
                  <button
                    onClick={handleUserCopy}
                    className="p-1.5 rounded-md transition-colors hover:bg-white/10 cursor-pointer"
                    style={{ color: 'var(--color-text-secondary)' }}
                  >
                    {copied ? (
                      <Check className="w-4 h-4" />
                    ) : (
                      <Copy className="w-4 h-4" />
                    )}
                  </button>
                </TooltipTrigger>
                <TooltipContent side="bottom">
                  {copied ? 'Copied!' : 'Copy message'}
                </TooltipContent>
              </Tooltip>

              {/* Edit - only for last user message */}
              {isLastUserMessage && (
                <Tooltip>
                  <TooltipTrigger asChild>
                    <button
                      onClick={() => onEdit?.(message.id)}
                      className="p-1.5 rounded-md transition-colors hover:bg-white/10 cursor-pointer"
                      style={{ color: 'var(--color-text-secondary)' }}
                    >
                      <Pencil className="w-4 h-4" />
                    </button>
                  </TooltipTrigger>
                  <TooltipContent side="bottom">
                    Edit message
                  </TooltipContent>
                </Tooltip>
              )}

              {/* Branch with different model */}
              <div ref={branchDropdownRef} className="relative">
                <Tooltip>
                  <TooltipTrigger asChild>
                    <button
                      onClick={() => setIsBranchOpen(!isBranchOpen)}
                      className="p-1.5 rounded-md transition-colors hover:bg-white/10 cursor-pointer"
                      style={{ color: 'var(--color-text-secondary)' }}
                    >
                      <GitBranch className="w-4 h-4" />
                    </button>
                  </TooltipTrigger>
                  <TooltipContent side="bottom">
                    Branch with different model
                  </TooltipContent>
                </Tooltip>

                {/* Model dropdown */}
                {isBranchOpen && (
                  <div
                    className="absolute bottom-full right-0 mb-2 py-1.5 rounded-xl min-w-[220px] max-h-64 overflow-y-auto backdrop-blur-xl z-50"
                    style={{
                      background: 'rgba(255, 255, 255, 0.08)',
                      boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
                    }}
                  >
                    {loadingModels ? (
                      <div
                        className="flex items-center justify-center gap-2 px-3 py-4 text-xs"
                        style={{ color: 'var(--color-text-secondary)' }}
                      >
                        <Loader2 className="w-4 h-4 animate-spin" />
                        Loading models...
                      </div>
                    ) : branchModels.filter(m => m.path !== currentModel).length === 0 ? (
                      <div
                        className="px-3 py-4 text-xs text-center"
                        style={{ color: 'var(--color-text-secondary)' }}
                      >
                        No other models available
                      </div>
                    ) : (
                      branchModels
                        .filter(m => m.path !== currentModel)
                        .map((model) => (
                          <button
                            key={model.path}
                            onClick={() => handleUserBranchSelect(model)}
                            className={cn(
                              'flex items-center gap-2 w-[calc(100%-12px)] mx-1.5 px-3 py-1.5 text-xs text-left rounded-lg transition-colors',
                              'hover:bg-white/10'
                            )}
                            style={{ color: 'var(--color-text)' }}
                          >
                            <div className="flex-1 min-w-0">
                              <div className="truncate">{model.name}</div>
                              {model.size && (
                                <div
                                  className="text-[11px]"
                                  style={{ color: 'var(--color-text-secondary)' }}
                                >
                                  {model.size}
                                </div>
                              )}
                            </div>
                          </button>
                        ))
                    )}
                  </div>
                )}
              </div>
            </TooltipProvider>
          </div>
        </div>
      </div>
    );
  }

  // Content to display (use hidingContent during animation)
  const displayContent = message.isHiding && hidingContent !== null ? hidingContent : message.content;

  // Parse thinking blocks from content (supports <think> tags from reasoning models)
  // This must be parsed before handlers so copy/speak use the response only
  const { thinking, response, isThinkingStreaming } = useMemo(() => {
    // Check for complete thinking block
    const thinkMatch = displayContent.match(/<think>([\s\S]*?)<\/think>/);
    if (thinkMatch) {
      const thinkContent = thinkMatch[1].trim();
      const responseContent = displayContent.replace(/<think>[\s\S]*?<\/think>/, '').trim();
      return { thinking: thinkContent || '', response: responseContent, isThinkingStreaming: false };
    }
    // Handle unclosed thinking tag (still streaming)
    const unclosedMatch = displayContent.match(/<think>([\s\S]*)$/);
    if (unclosedMatch) {
      return { thinking: unclosedMatch[1].trim(), response: '', isThinkingStreaming: true };
    }
    // Check if just started with <think> tag
    if (displayContent.includes('<think>')) {
      return { thinking: '', response: '', isThinkingStreaming: true };
    }
    return { thinking: null, response: displayContent, isThinkingStreaming: false };
  }, [displayContent]);

  const [isThinkingExpanded, setIsThinkingExpanded] = useState(false);

  // Copy only the response (not thinking content)
  const handleCopy = useCallback(() => {
    navigator.clipboard.writeText(response);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }, [response]);

  // Text-to-speech for response only (not thinking content)
  const handleSpeak = useCallback(() => {
    if (isSpeaking) {
      window.speechSynthesis.cancel();
      setIsSpeaking(false);
      return;
    }

    // Strip markdown for cleaner speech
    const textToSpeak = response
      .replace(/```[\s\S]*?```/g, 'code block')
      .replace(/`([^`]+)`/g, '$1')
      .replace(/\*\*([^*]+)\*\*/g, '$1')
      .replace(/\*([^*]+)\*/g, '$1')
      .replace(/#{1,6}\s/g, '')
      .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
      .replace(/[-*]\s/g, '');

    const utterance = new SpeechSynthesisUtterance(textToSpeak);
    utterance.onend = () => setIsSpeaking(false);
    utterance.onerror = () => setIsSpeaking(false);

    setIsSpeaking(true);
    window.speechSynthesis.speak(utterance);
  }, [response, isSpeaking]);

  // Assistant/system messages: logo on left, content indented
  return (
    <div
      className="group w-full mb-6 flex gap-4"
      style={{ color: 'var(--color-text)' }}
    >
      {/* Leaxer icon for assistant messages */}
      {isAssistant && !message.isHiding && (
        <div className="flex-shrink-0 pt-1">
          <LeaxerLogo className="w-5 h-5" isAnimating={message.isStreaming} />
        </div>
      )}

      {/* Message content */}
      <div className="flex-1 min-w-0">
        {isSystem && <span className="italic opacity-70 text-sm">[System] </span>}

        {/* Thinking block */}
        {(thinking !== null || isThinkingStreaming) && (
          <ThinkingBlock
            content={thinking || ''}
            isExpanded={isThinkingExpanded}
            onToggle={() => setIsThinkingExpanded(!isThinkingExpanded)}
            isStreaming={isThinkingStreaming && message.isStreaming}
          />
        )}

        {/* Divider between thinking and response - only visible when expanded */}
        {(thinking !== null || isThinkingStreaming) && isThinkingExpanded && response && (
          <hr
            className="my-16"
            style={{ borderColor: 'var(--color-overlay-0)', borderTopWidth: '1px' }}
          />
        )}

        {/* Response content */}
        <div className="text-[16px] leading-[2]">
          {response ? (
            <MarkdownContent content={response} />
          ) : !thinking && !message.isHiding && !message.isStreaming ? (
            <p className="text-[var(--color-text-muted)] italic">Empty message</p>
          ) : null}
        </div>

        {/* Action buttons - always visible when not streaming or hiding */}
        {message.content && !message.isStreaming && !message.isHiding && (
          <div className="mt-5 mb-5 flex items-center gap-1">
            <TooltipProvider delayDuration={300}>
              <Tooltip>
                <TooltipTrigger asChild>
                  <button
                    onClick={handleCopy}
                    className="p-1.5 rounded-md transition-colors hover:bg-white/10 cursor-pointer"
                    style={{ color: 'var(--color-text-secondary)' }}
                  >
                    {copied ? (
                      <Check className="w-5 h-5" />
                    ) : (
                      <Copy className="w-5 h-5" />
                    )}
                  </button>
                </TooltipTrigger>
                <TooltipContent side="bottom">
                  {copied ? 'Copied!' : 'Copy message'}
                </TooltipContent>
              </Tooltip>

              <Tooltip>
                <TooltipTrigger asChild>
                  <button
                    onClick={handleSpeak}
                    className="p-1.5 rounded-md transition-colors hover:bg-white/10 cursor-pointer"
                    style={{ color: 'var(--color-text-secondary)' }}
                  >
                    {isSpeaking ? (
                      <VolumeX className="w-5 h-5" />
                    ) : (
                      <Volume2 className="w-5 h-5" />
                    )}
                  </button>
                </TooltipTrigger>
                <TooltipContent side="bottom">
                  {isSpeaking ? 'Stop speaking' : 'Read aloud'}
                </TooltipContent>
              </Tooltip>

              {isLastMessage && (
                <Tooltip>
                  <TooltipTrigger asChild>
                    <button
                      onClick={() => onRegenerate?.(message.id)}
                      className="p-1.5 rounded-md transition-colors hover:bg-white/10 cursor-pointer"
                      style={{ color: 'var(--color-text-secondary)' }}
                    >
                      <RotateCcw className="w-5 h-5" />
                    </button>
                  </TooltipTrigger>
                  <TooltipContent side="bottom">
                    Regenerate response
                  </TooltipContent>
                </Tooltip>
              )}

              {/* Branch with different model */}
              {isLastMessage && (
                <div ref={branchDropdownRef} className="relative">
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <button
                        onClick={() => setIsBranchOpen(!isBranchOpen)}
                        className="p-1.5 rounded-md transition-colors hover:bg-white/10 cursor-pointer"
                        style={{ color: 'var(--color-text-secondary)' }}
                      >
                        <GitBranch className="w-5 h-5" />
                      </button>
                    </TooltipTrigger>
                    <TooltipContent side="bottom">
                      Branch with different model
                    </TooltipContent>
                  </Tooltip>

                  {/* Model dropdown */}
                  {isBranchOpen && (
                    <div
                      className="absolute bottom-full left-0 mb-2 py-1.5 rounded-xl min-w-[220px] max-h-64 overflow-y-auto backdrop-blur-xl z-50"
                      style={{
                        background: 'rgba(255, 255, 255, 0.08)',
                        boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
                      }}
                    >
                      {loadingModels ? (
                        <div
                          className="flex items-center justify-center gap-2 px-3 py-4 text-xs"
                          style={{ color: 'var(--color-text-secondary)' }}
                        >
                          <Loader2 className="w-4 h-4 animate-spin" />
                          Loading models...
                        </div>
                      ) : branchModels.filter(m => m.path !== currentModel).length === 0 ? (
                        <div
                          className="px-3 py-4 text-xs text-center"
                          style={{ color: 'var(--color-text-secondary)' }}
                        >
                          No other models available
                        </div>
                      ) : (
                        branchModels
                          .filter(m => m.path !== currentModel)
                          .map((model) => (
                            <button
                              key={model.path}
                              onClick={() => handleBranchSelect(model)}
                              className={cn(
                                'flex items-center gap-2 w-[calc(100%-12px)] mx-1.5 px-3 py-1.5 text-xs text-left rounded-lg transition-colors',
                                'hover:bg-white/10'
                              )}
                              style={{ color: 'var(--color-text)' }}
                            >
                              <div className="flex-1 min-w-0">
                                <div className="truncate">{model.name}</div>
                                {model.size && (
                                  <div
                                    className="text-[11px]"
                                    style={{ color: 'var(--color-text-secondary)' }}
                                  >
                                    {model.size}
                                  </div>
                                )}
                              </div>
                            </button>
                          ))
                      )}
                    </div>
                  )}
                </div>
              )}
            </TooltipProvider>

            {/* Model name */}
            {message.model && (
              <span
                className="ml-auto text-xs"
                style={{ color: 'var(--color-text-secondary)', opacity: 0.6 }}
                title={message.model}
              >
                {message.model.split(/[/\\]/).pop()?.replace(/\.gguf$/i, '')}
              </span>
            )}
          </div>
        )}

        {/* Search references - Rich media cards with embeds */}
        {message.references && message.references.length > 0 && !message.isStreaming && (
          <div className="mt-4 pt-4 border-t" style={{ borderColor: 'var(--color-surface-2)' }}>
            <div className="text-xs font-medium mb-3" style={{ color: 'var(--color-text-muted)' }}>
              Sources
            </div>
            <div className="grid gap-3" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))' }}>
              {message.references.map((ref) => (
                <EmbedCard key={ref.index} reference={ref} />
              ))}
            </div>
          </div>
        )}

        {/* Artifact document card - show even during streaming if artifact exists */}
        {message.artifact && (
          <div className="mt-4 pt-4 border-t" style={{ borderColor: 'var(--color-surface-2)' }}>
            <div className="text-xs font-medium mb-3" style={{ color: 'var(--color-text-muted)' }}>
              Document
            </div>
            <ArtifactCard artifact={message.artifact} />
          </div>
        )}

        {/* Follow-up suggestions */}
        {showFollowUps && (
          <div className="mt-4">
            <div className="text-xs font-medium mb-3" style={{ color: 'var(--color-text-muted)' }}>
              Dive deeper
            </div>
            <div className="flex flex-wrap gap-2">
              {message.followUps!.map((followUp, index) => (
                <button
                  key={index}
                  onClick={() => onFollowUp?.(followUp)}
                  className="px-3 py-1.5 rounded-full text-xs transition-colors duration-200 cursor-pointer hover:bg-white/10"
                  style={{
                    background: 'rgba(255, 255, 255, 0.06)',
                    color: 'var(--color-text-secondary)',
                  }}
                >
                  {followUp}
                </button>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

ChatMessage.displayName = 'ChatMessage';

/**
 * Clean up malformed markdown that can result from LLM outputs.
 * Handles double code blocks, empty code blocks, unclosed code blocks, etc.
 * Be careful not to break valid code blocks.
 */
function cleanMarkdownContent(content: string): string {
  let cleaned = content;

  // Remove "undefined" that appears at the start (from tool/streaming issues)
  cleaned = cleaned.replace(/^undefined\s*/i, '');

  // Fix malformed opening fence with "undefined" as language tag
  // Pattern: ```undefined followed by newline and content that's clearly not code
  // This is common when web search tool has issues
  if (/^```undefined\s*\n/i.test(cleaned)) {
    const afterFence = cleaned.replace(/^```undefined\s*\n/i, '');
    // If content after looks like markdown, remove the fence
    if (/(\*\*[^*]+\*\*|^#{1,6}\s|^\s*[-*]\s|^\s*\d+\.\s)/m.test(afterFence)) {
      cleaned = afterFence;
    }
  }

  // Fix malformed opening fence: ``` followed directly by text (no newline)
  // Example: "```JavaScript and TypeScript are..." - the text is NOT a language tag
  // Only remove if what follows doesn't look like a valid code block
  if (/^```[A-Z][a-z]/.test(cleaned)) {
    // Starts with ``` followed by capitalized word (likely prose, not a language tag)
    cleaned = cleaned.replace(/^```/, '');
  }

  // Remove truly empty code blocks (with optional language tag but no content)
  // Matches: ```\n``` or ```json\n``` (empty blocks)
  cleaned = cleaned.replace(/```\w*\n```/g, '');

  // Fix double-wrapped code blocks: ```\n```python\ncode\n```\n```
  // This unwraps the outer empty wrapper while preserving the inner valid block
  cleaned = cleaned.replace(/```\s*\n(```\w+\n[\s\S]*?\n```)\s*\n```/g, '$1');

  // Fix cases where there's a stray ``` before a code block: ```\n```python
  // But only if the ``` is immediately followed by another code fence
  cleaned = cleaned.replace(/```\s*\n(```\w+\n)/g, '$1');

  // Fix cases where there's a stray ``` after a code block: ```\n```
  // But only if it comes right after a closing fence
  cleaned = cleaned.replace(/(```)\s*\n```(\s*\n|$)/g, '$1$2');

  // Handle unclosed code blocks - common with web search results
  // Count code fences that are on their own line (proper fences)
  const fenceMatches = cleaned.match(/^```\w*$/gm);
  const fenceCount = fenceMatches ? fenceMatches.length : 0;

  if (fenceCount % 2 !== 0) {
    // Odd number of fences means unclosed block
    // Check if content starts with ``` on its own line
    const startsWithFence = /^```\w*\s*\n/.test(cleaned);
    if (startsWithFence) {
      // Get content after the opening fence
      const afterFence = cleaned.replace(/^```\w*\s*\n/, '');
      // Check if it looks like regular markdown (has bold, headers, bullets, links)
      const looksLikeMarkdown = /(\*\*[^*]+\*\*|^#{1,6}\s|^\s*[-*]\s|^\s*\d+\.\s|\[[^\]]+\]\([^)]+\))/m.test(afterFence);
      // Check if it looks like code (has common code patterns)
      const looksLikeCode = /(^(import|export|const|let|var|function|class|def|fn|pub|async|return)\s|[{};]$|^\s*(if|for|while)\s*\()/m.test(afterFence);

      if (looksLikeMarkdown && !looksLikeCode) {
        // Remove the erroneous opening fence
        cleaned = afterFence;
      } else {
        // It might be actual code, add closing fence
        cleaned = cleaned + '\n```';
      }
    }
  }

  // Final cleanup: remove any remaining stray ``` at the very start if followed by non-code content
  // This catches cases like "```\n**Bold text**" where fence is followed by markdown
  if (/^```\s*\n\s*\*\*/.test(cleaned)) {
    cleaned = cleaned.replace(/^```\s*\n/, '');
  }

  // Remove any remaining empty lines at start/end
  cleaned = cleaned.trim();

  return cleaned;
}

/**
 * Markdown renderer with syntax highlighting for code blocks.
 */
const MarkdownContent = ({ content }: { content: string }) => {
  // Memoize the theme-aware style
  const syntaxStyle = useMemo(() => createThemeAwareStyle(), []);

  // Clean up malformed markdown
  const cleanedContent = useMemo(() => cleanMarkdownContent(content), [content]);

  return (
    <div className="markdown-content" style={{ color: 'inherit' }}>
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
        // Code blocks with syntax highlighting
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
        // Paragraphs
        p({ children }) {
          return <p className="mb-6 last:mb-0" style={{ color: 'inherit' }}>{children}</p>;
        },
        // Lists
        ul({ children }) {
          return <ul className="list-disc pl-6 mb-4 space-y-2" style={{ color: 'inherit' }}>{children}</ul>;
        },
        ol({ children }) {
          return <ol className="list-decimal pl-6 mb-4 space-y-2" style={{ color: 'inherit' }}>{children}</ol>;
        },
        li({ children }) {
          return <li className="pl-1" style={{ color: 'inherit' }}>{children}</li>;
        },
        // Headings
        h1({ children }) {
          return <h1 className="text-xl font-semibold mb-3 mt-6 first:mt-0" style={{ color: 'inherit' }}>{children}</h1>;
        },
        h2({ children }) {
          return <h2 className="text-lg font-semibold mb-3 mt-5 first:mt-0" style={{ color: 'inherit' }}>{children}</h2>;
        },
        h3({ children }) {
          return <h3 className="text-base font-semibold mb-2 mt-4 first:mt-0" style={{ color: 'inherit' }}>{children}</h3>;
        },
        // Links
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
        // Blockquotes
        blockquote({ children }) {
          return (
            <blockquote
              className="border-l-3 pl-4 my-4 py-1"
              style={{
                borderColor: 'var(--color-overlay-1)',
                color: 'var(--color-text-secondary)',
              }}
            >
              {children}
            </blockquote>
          );
        },
        // Bold/Strong
        strong({ children }) {
          return <strong className="font-semibold" style={{ color: 'inherit' }}>{children}</strong>;
        },
        // Italic/Em
        em({ children }) {
          return <em className="italic" style={{ color: 'inherit' }}>{children}</em>;
        },
        // Horizontal rule
        hr() {
          return (
            <hr
              className="my-6"
              style={{ borderColor: 'var(--color-overlay-0)' }}
            />
          );
        },
        // Tables
        table({ children }) {
          return (
            <div className="overflow-x-auto mt-4 mb-8">
              <table
                className="w-full text-sm [&_tr:last-child_td]:border-b-0"
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
        tr({ children }) {
          return (
            <tr className="transition-colors hover:bg-[var(--color-surface-1)]">
              {children}
            </tr>
          );
        },
        th({ children }) {
          return (
            <th
              className="px-3 py-2 text-left font-medium first:rounded-tl-[7px] last:rounded-tr-[7px]"
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
        {cleanedContent}
      </ReactMarkdown>
    </div>
  );
};

MarkdownContent.displayName = 'MarkdownContent';

/**
 * Animated streaming indicator shown when waiting for first token.
 */
const StreamingIndicator = memo(() => {
  return (
    <div className="flex items-center gap-1.5 py-1">
      <div
        className="w-2 h-2 rounded-full animate-pulse"
        style={{
          backgroundColor: 'var(--color-text-muted)',
          animationDelay: '0ms',
        }}
      />
      <div
        className="w-2 h-2 rounded-full animate-pulse"
        style={{
          backgroundColor: 'var(--color-text-muted)',
          animationDelay: '150ms',
        }}
      />
      <div
        className="w-2 h-2 rounded-full animate-pulse"
        style={{
          backgroundColor: 'var(--color-text-muted)',
          animationDelay: '300ms',
        }}
      />
    </div>
  );
});

StreamingIndicator.displayName = 'StreamingIndicator';

/**
 * Animated Leaxer logo with gradient animation.
 * Pulses and rotates while streaming, transitions to static when done.
 */
const LeaxerLogo = memo(({ className, isAnimating }: { className?: string; isAnimating?: boolean }) => (
  <div
    className={`${className} transition-transform duration-500 ease-out`}
    style={{
      animation: isAnimating
        ? 'leaxerPulse 1.5s ease-in-out infinite'
        : 'none',
      transform: isAnimating ? undefined : 'scale(1)',
    }}
  >
    <style>
      {`
        @keyframes leaxerPulse {
          0%, 100% { transform: scale(1); }
          50% { transform: scale(1.2); }
        }
      `}
    </style>
    <svg
      className="w-full h-full"
      viewBox="0 0 511 512"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      style={{ overflow: 'visible' }}
    >
      <defs>
        <radialGradient
          id="animatedGradient"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(0 512) rotate(-45) scale(782 780)"
        >
          <stop offset="0%" stopColor="#F18DF2">
            <animate
              attributeName="stop-color"
              values="#F18DF2;#275AF2;#00D9FF;#F18DF2"
              dur="4s"
              repeatCount="indefinite"
            />
          </stop>
          <stop offset="50%" stopColor="#275AF2">
            <animate
              attributeName="stop-color"
              values="#275AF2;#00D9FF;#F18DF2;#275AF2"
              dur="4s"
              repeatCount="indefinite"
            />
          </stop>
          <stop offset="100%" stopColor="#00D9FF">
            <animate
              attributeName="stop-color"
              values="#00D9FF;#F18DF2;#275AF2;#00D9FF"
              dur="4s"
              repeatCount="indefinite"
            />
          </stop>
        </radialGradient>
      </defs>
      <path
        d="M416.304 0L94.8107 2.81609e-05C-9.11684 3.72643e-05 -37.1644 143.461 59.0821 182.749L213.662 245.85C237.275 255.489 256.011 274.261 265.631 297.92L328.608 452.802C367.819 549.237 511 521.135 511 417.004L511 94.8809C511 42.4796 468.603 -4.58107e-06 416.304 0Z"
        fill="url(#animatedGradient)"
      />
    </svg>
  </div>
));

LeaxerLogo.displayName = 'LeaxerLogo';

/**
 * Collapsible thinking block component.
 */
interface ThinkingBlockProps {
  content: string;
  isExpanded: boolean;
  onToggle: () => void;
  isStreaming?: boolean;
}

const ThinkingBlock = memo(({ content, isExpanded, onToggle, isStreaming }: ThinkingBlockProps) => (
  <div className="mb-4">
    {/* Clickable header */}
    <button
      onClick={onToggle}
      className="flex items-center gap-1 py-1 text-[16px] transition-colors cursor-pointer hover:opacity-80"
      style={{ color: 'var(--color-text-secondary)' }}
    >
      {isExpanded ? (
        <ChevronDown className="w-4 h-4" />
      ) : (
        <ChevronRight className="w-4 h-4" />
      )}
      <span>{isStreaming ? 'Thinking...' : (isExpanded ? 'Hide thinking' : 'Show thinking')}</span>
    </button>

    {/* Expandable content */}
    {isExpanded && (
      <div
        className="pl-5 mt-2 text-[16px] leading-[2] overflow-x-auto"
        style={{ color: 'var(--color-text-secondary)' }}
      >
        {content ? (
          <MarkdownContent content={content} />
        ) : isStreaming ? (
          <span className="opacity-60">Processing...</span>
        ) : null}

        {/* Hide button at bottom for long content */}
        {content && content.length > 500 && (
          <button
            onClick={onToggle}
            className="flex items-center gap-1 mt-4 py-1 text-[16px] transition-colors cursor-pointer hover:opacity-80"
            style={{ color: 'var(--color-text-secondary)' }}
          >
            <ChevronUp className="w-4 h-4" />
            <span>Hide thinking</span>
          </button>
        )}
      </div>
    )}
  </div>
));

ThinkingBlock.displayName = 'ThinkingBlock';

/**
 * Media embed type detection and rendering utilities
 */
type EmbedType = 'youtube' | 'twitter' | 'vimeo' | 'spotify' | 'github' | 'reddit' | 'tiktok' | 'codepen' | null;

interface EmbedInfo {
  type: EmbedType;
  id: string;
  extra?: Record<string, string>;
}

function detectEmbed(url: string): EmbedInfo | null {
  // YouTube
  const youtubePatterns = [
    /(?:youtube\.com\/watch\?v=|youtube\.com\/embed\/|youtu\.be\/|youtube\.com\/v\/|youtube\.com\/shorts\/)([a-zA-Z0-9_-]{11})/,
    /youtube\.com\/watch\?.*v=([a-zA-Z0-9_-]{11})/,
  ];
  for (const pattern of youtubePatterns) {
    const match = url.match(pattern);
    if (match?.[1]) return { type: 'youtube', id: match[1] };
  }

  // Twitter/X
  const twitterMatch = url.match(/(?:twitter\.com|x\.com)\/\w+\/status\/(\d+)/);
  if (twitterMatch?.[1]) return { type: 'twitter', id: twitterMatch[1] };

  // Vimeo
  const vimeoMatch = url.match(/vimeo\.com\/(\d+)/);
  if (vimeoMatch?.[1]) return { type: 'vimeo', id: vimeoMatch[1] };

  // Spotify
  const spotifyMatch = url.match(/spotify\.com\/(track|album|playlist|episode|show)\/([a-zA-Z0-9]+)/);
  if (spotifyMatch?.[1] && spotifyMatch?.[2]) {
    return { type: 'spotify', id: spotifyMatch[2], extra: { contentType: spotifyMatch[1] } };
  }

  // GitHub repo
  const githubMatch = url.match(/github\.com\/([^\/]+\/[^\/]+)\/?$/);
  if (githubMatch?.[1]) return { type: 'github', id: githubMatch[1] };

  // Reddit
  const redditMatch = url.match(/reddit\.com\/r\/([^\/]+)\/comments\/([a-zA-Z0-9]+)/);
  if (redditMatch?.[1] && redditMatch?.[2]) {
    return { type: 'reddit', id: redditMatch[2], extra: { subreddit: redditMatch[1] } };
  }

  // TikTok
  const tiktokMatch = url.match(/tiktok\.com\/@[^\/]+\/video\/(\d+)/);
  if (tiktokMatch?.[1]) return { type: 'tiktok', id: tiktokMatch[1] };

  // CodePen
  const codepenMatch = url.match(/codepen\.io\/([^\/]+)\/pen\/([a-zA-Z0-9]+)/);
  if (codepenMatch?.[1] && codepenMatch?.[2]) {
    return { type: 'codepen', id: codepenMatch[2], extra: { user: codepenMatch[1] } };
  }

  return null;
}


/**
 * Rich embed card for various media types
 */
interface EmbedCardProps {
  reference: {
    index: number;
    title: string;
    url: string;
    description?: string;
    image?: string;
    site_name?: string;
    favicon?: string;
  };
}

const EmbedCard = memo(({ reference }: EmbedCardProps) => {
  const embed = detectEmbed(reference.url);

  // YouTube embed
  if (embed?.type === 'youtube') {
    return (
      <div className="rounded-xl overflow-hidden" style={{ background: 'rgba(255, 255, 255, 0.06)' }}>
        <div className="relative w-full" style={{ paddingBottom: '56.25%' }}>
          <iframe
            className="absolute inset-0 w-full h-full"
            src={`https://www.youtube.com/embed/${embed.id}`}
            title={reference.title}
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
            allowFullScreen
          />
        </div>
        <EmbedCardFooter reference={reference} platform="YouTube" />
      </div>
    );
  }

  // Twitter/X embed - use embedded tweet iframe
  if (embed?.type === 'twitter') {
    return (
      <div className="rounded-xl overflow-hidden" style={{ background: 'rgba(255, 255, 255, 0.06)' }}>
        <div className="relative w-full min-h-[200px]">
          <iframe
            className="w-full"
            src={`https://platform.twitter.com/embed/Tweet.html?id=${embed.id}&theme=dark`}
            style={{ border: 'none', minHeight: '200px' }}
            loading="lazy"
          />
        </div>
        <EmbedCardFooter reference={reference} platform="X" />
      </div>
    );
  }

  // Vimeo embed
  if (embed?.type === 'vimeo') {
    return (
      <div className="rounded-xl overflow-hidden" style={{ background: 'rgba(255, 255, 255, 0.06)' }}>
        <div className="relative w-full" style={{ paddingBottom: '56.25%' }}>
          <iframe
            className="absolute inset-0 w-full h-full"
            src={`https://player.vimeo.com/video/${embed.id}`}
            title={reference.title}
            allow="autoplay; fullscreen; picture-in-picture"
            allowFullScreen
          />
        </div>
        <EmbedCardFooter reference={reference} platform="Vimeo" />
      </div>
    );
  }

  // Spotify embed
  if (embed?.type === 'spotify') {
    const contentType = embed.extra?.contentType || 'track';
    const height = contentType === 'track' ? '152' : '352';
    return (
      <div className="rounded-xl overflow-hidden" style={{ background: 'rgba(255, 255, 255, 0.06)' }}>
        <iframe
          src={`https://open.spotify.com/embed/${contentType}/${embed.id}?theme=0`}
          width="100%"
          height={height}
          allow="autoplay; clipboard-write; encrypted-media; fullscreen; picture-in-picture"
          loading="lazy"
          style={{ borderRadius: '12px 12px 0 0', border: 'none' }}
        />
        <EmbedCardFooter reference={reference} platform="Spotify" />
      </div>
    );
  }

  // GitHub repo card
  if (embed?.type === 'github') {
    return (
      <a
        href={reference.url}
        target="_blank"
        rel="noopener noreferrer"
        className="block rounded-xl overflow-hidden transition-colors hover:bg-white/10"
        style={{ background: 'rgba(255, 255, 255, 0.06)' }}
      >
        <div className="p-4">
          <div className="flex items-center gap-2 mb-2">
            <svg className="w-5 h-5" viewBox="0 0 24 24" fill="currentColor" style={{ color: 'var(--color-text-secondary)' }}>
              <path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0024 12c0-6.63-5.37-12-12-12z"/>
            </svg>
            <span className="text-sm font-medium" style={{ color: 'var(--color-text)' }}>{embed.id}</span>
          </div>
          {reference.description && (
            <div className="text-xs line-clamp-2" style={{ color: 'var(--color-text-secondary)' }}>
              {reference.description}
            </div>
          )}
        </div>
        <EmbedCardFooter reference={reference} platform="GitHub" />
      </a>
    );
  }

  // Reddit post - use Reddit's embed
  if (embed?.type === 'reddit') {
    return (
      <div className="rounded-xl overflow-hidden" style={{ background: 'rgba(255, 255, 255, 0.06)' }}>
        <div className="relative w-full min-h-[300px]">
          <iframe
            className="w-full h-full absolute inset-0"
            src={`https://www.redditmedia.com/r/${embed.extra?.subreddit}/comments/${embed.id}/?embed=true&theme=dark`}
            style={{ border: 'none' }}
            loading="lazy"
            sandbox="allow-scripts allow-same-origin allow-popups"
          />
        </div>
        <EmbedCardFooter reference={reference} platform="Reddit" />
      </div>
    );
  }

  // TikTok embed
  if (embed?.type === 'tiktok') {
    return (
      <div className="rounded-xl overflow-hidden" style={{ background: 'rgba(255, 255, 255, 0.06)' }}>
        <div className="relative w-full" style={{ paddingBottom: '177.78%', maxHeight: '500px' }}>
          <iframe
            className="absolute inset-0 w-full h-full"
            src={`https://www.tiktok.com/embed/v2/${embed.id}`}
            style={{ border: 'none' }}
            loading="lazy"
            sandbox="allow-scripts allow-same-origin allow-popups"
            allowFullScreen
          />
        </div>
        <EmbedCardFooter reference={reference} platform="TikTok" />
      </div>
    );
  }

  // CodePen embed
  if (embed?.type === 'codepen') {
    return (
      <div className="rounded-xl overflow-hidden" style={{ background: 'rgba(255, 255, 255, 0.06)' }}>
        <iframe
          height="300"
          style={{ width: '100%', border: 'none' }}
          scrolling="no"
          src={`https://codepen.io/${embed.extra?.user}/embed/${embed.id}?default-tab=result&theme-id=dark`}
          loading="lazy"
          allowFullScreen
        />
        <EmbedCardFooter reference={reference} platform="CodePen" />
      </div>
    );
  }

  // Default card for non-embeddable content
  return <DefaultSourceCard reference={reference} />;
});

EmbedCard.displayName = 'EmbedCard';

/**
 * Footer for embed cards showing index and platform
 */
const EmbedCardFooter = memo(({ reference, platform }: { reference: EmbedCardProps['reference']; platform: string }) => (
  <div className="px-3 py-2 flex items-center gap-2" style={{ borderTop: '1px solid rgba(255,255,255,0.05)' }}>
    <span
      className="flex items-center justify-center w-4 h-4 rounded text-[10px] font-medium flex-shrink-0"
      style={{ background: 'var(--color-accent)', color: 'var(--color-base)' }}
    >
      {reference.index}
    </span>
    <span className="text-[11px]" style={{ color: 'var(--color-text-muted)' }}>
      {platform}
    </span>
    <span className="flex-1 text-xs truncate" style={{ color: 'var(--color-text-secondary)' }}>
      {reference.title}
    </span>
  </div>
));

EmbedCardFooter.displayName = 'EmbedCardFooter';

/**
 * Default source card for non-embeddable content
 */
const DefaultSourceCard = memo(({ reference }: EmbedCardProps) => (
  <a
    href={reference.url}
    target="_blank"
    rel="noopener noreferrer"
    className="group flex gap-3 p-3 rounded-xl transition-colors duration-200 hover:bg-white/10"
    style={{
      background: 'rgba(255, 255, 255, 0.06)',
      boxShadow: 'inset 0 1px 0 rgba(255, 255, 255, 0.05)',
    }}
  >
    {/* Thumbnail or favicon fallback */}
    <div
      className="flex-shrink-0 w-16 h-16 rounded-lg overflow-hidden flex items-center justify-center"
      style={{ background: 'rgba(255, 255, 255, 0.05)' }}
    >
      {reference.image ? (
        <img
          src={reference.image}
          alt=""
          className="w-full h-full object-cover"
          onError={(e) => {
            const target = e.target as HTMLImageElement;
            target.style.display = 'none';
            target.parentElement!.innerHTML = reference.favicon
              ? `<img src="${reference.favicon}" class="w-6 h-6" onerror="this.style.display='none';this.parentElement.innerHTML='<span class=\\'text-lg font-semibold\\' style=\\'color: var(--color-text-secondary)\\'>${reference.index}</span>'" />`
              : `<span class="text-lg font-semibold" style="color: var(--color-text-secondary)">${reference.index}</span>`;
          }}
        />
      ) : reference.favicon ? (
        <img
          src={reference.favicon}
          alt=""
          className="w-6 h-6"
          onError={(e) => {
            const target = e.target as HTMLImageElement;
            target.style.display = 'none';
            target.parentElement!.innerHTML = `<span class="text-lg font-semibold" style="color: var(--color-text-secondary)">${reference.index}</span>`;
          }}
        />
      ) : (
        <span
          className="text-lg font-semibold"
          style={{ color: 'var(--color-text-secondary)' }}
        >
          {reference.index}
        </span>
      )}
    </div>

    {/* Content */}
    <div className="flex-1 min-w-0 flex flex-col">
      {/* Site name with index badge */}
      <div className="flex items-center gap-1.5 mb-1">
        <span
          className="flex items-center justify-center w-4 h-4 rounded text-[10px] font-medium flex-shrink-0"
          style={{ background: 'var(--color-accent)', color: 'var(--color-base)' }}
        >
          {reference.index}
        </span>
        <span
          className="text-[11px] truncate"
          style={{ color: 'var(--color-text-muted)' }}
        >
          {reference.site_name || new URL(reference.url).hostname.replace('www.', '')}
        </span>
      </div>

      {/* Title */}
      <div
        className="text-sm font-medium line-clamp-2 mb-1"
        style={{ color: 'var(--color-text)' }}
      >
        {reference.title}
      </div>

      {/* Description */}
      {reference.description && (
        <div
          className="text-xs line-clamp-2"
          style={{ color: 'var(--color-text-secondary)' }}
        >
          {reference.description}
        </div>
      )}
    </div>

    {/* External link icon */}
    <ExternalLink
      className="w-4 h-4 flex-shrink-0 opacity-0 group-hover:opacity-50 transition-opacity"
      style={{ color: 'var(--color-text-secondary)' }}
    />
  </a>
));

DefaultSourceCard.displayName = 'DefaultSourceCard';

/**
 * Attachment display component for chat messages.
 */
interface MessageAttachmentProps {
  attachment: ChatAttachment;
}

const MessageAttachment = memo(({ attachment }: MessageAttachmentProps) => {
  const isImage = attachment.requiresVision;
  const [isExpanded, setIsExpanded] = useState(false);

  // For images, show a thumbnail that expands on click
  if (isImage && attachment.dataUrl) {
    return (
      <>
        <button
          onClick={() => setIsExpanded(true)}
          className="relative rounded-xl overflow-hidden cursor-pointer transition-transform hover:scale-[1.02]"
          style={{ maxWidth: '200px' }}
        >
          <img
            src={attachment.dataUrl}
            alt={attachment.name}
            className="w-full h-auto rounded-xl"
            style={{ maxHeight: '150px', objectFit: 'cover' }}
          />
          <div
            className="absolute bottom-0 left-0 right-0 px-2 py-1 text-[11px] truncate"
            style={{
              background: 'linear-gradient(transparent, rgba(0,0,0,0.7))',
              color: 'var(--color-text)',
            }}
          >
            {attachment.name}
          </div>
        </button>

        {/* Expanded image modal */}
        {isExpanded && (
          <div
            className="fixed inset-0 z-50 flex items-center justify-center p-8 cursor-pointer"
            style={{ background: 'rgba(0,0,0,0.9)' }}
            onClick={() => setIsExpanded(false)}
          >
            <img
              src={attachment.dataUrl}
              alt={attachment.name}
              className="max-w-full max-h-full object-contain rounded-lg"
            />
          </div>
        )}
      </>
    );
  }

  // For text files, show a chip-style preview
  return (
    <div
      className="flex items-center gap-2 px-3 py-2 rounded-xl text-xs"
      style={{
        background: 'rgba(255, 255, 255, 0.06)',
        color: 'var(--color-text)',
      }}
    >
      <FileText className="w-4 h-4 flex-shrink-0" style={{ color: 'var(--color-text-secondary)' }} />
      <div className="flex flex-col min-w-0">
        <span className="truncate max-w-[150px]">{attachment.name}</span>
        <span style={{ color: 'var(--color-text-muted)' }}>{formatFileSize(attachment.size)}</span>
      </div>
    </div>
  );
});

MessageAttachment.displayName = 'MessageAttachment';
