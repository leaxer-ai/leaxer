import { memo, useState, useCallback, useRef, useEffect } from 'react';
import { Plus, Trash2, Check, X, Pencil, MessageCircle, GitBranch } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useChatStore } from '@/stores/chatStore';
import type { ChatSession } from '@/types/chat';

interface ChatSidebarProps {
  isOpen: boolean;
  onToggle: () => void;
}

export const ChatSidebar = memo(({ isOpen, onToggle }: ChatSidebarProps) => {
  const sidebarRef = useRef<HTMLDivElement>(null);
  const sessions = useChatStore((s) => s.sessions);
  const activeSessionId = useChatStore((s) => s.activeSessionId);
  const deleteSession = useChatStore((s) => s.deleteSession);
  const setActiveSession = useChatStore((s) => s.setActiveSession);
  const renameSession = useChatStore((s) => s.renameSession);
  const startNewChat = useChatStore((s) => s.startNewChat);

  // Close sidebar when clicking outside
  useEffect(() => {
    if (!isOpen) return;

    const handleClickOutside = (e: MouseEvent) => {
      if (sidebarRef.current && !sidebarRef.current.contains(e.target as Node)) {
        onToggle();
      }
    };

    // Delay adding listener to avoid immediate close on open click
    const timer = setTimeout(() => {
      document.addEventListener('mousedown', handleClickOutside);
    }, 100);

    return () => {
      clearTimeout(timer);
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [isOpen, onToggle]);

  const handleNewChat = useCallback(() => {
    startNewChat();
    onToggle(); // Close sidebar after creating new chat
  }, [startNewChat, onToggle]);

  return (
    <>
      {/* Toggle button when closed - bottom left corner */}
      <button
        onClick={onToggle}
        className={cn(
          'fixed left-6 bottom-6 z-40 flex items-center justify-center w-[44px] h-[44px] rounded-full backdrop-blur-xl transition-all duration-300 ease-out',
          isOpen
            ? 'opacity-0 scale-75 pointer-events-none'
            : 'opacity-100 scale-100 hover:scale-105'
        )}
        style={{
          background: 'rgba(255, 255, 255, 0.08)',
          boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
          color: 'var(--color-text-secondary)',
        }}
        title="Open chat history"
      >
        <MessageCircle className="w-4 h-4" />
      </button>

      {/* Sidebar - grows from bottom left */}
      <div
        ref={sidebarRef}
        className={cn(
          'fixed left-6 bottom-6 z-40 flex flex-col w-[280px] rounded-xl backdrop-blur-xl overflow-hidden transition-all duration-300 ease-[cubic-bezier(0.34,1.56,0.64,1)] origin-bottom-left',
          isOpen
            ? 'opacity-100 scale-100 translate-y-0'
            : 'opacity-0 scale-90 translate-y-4 pointer-events-none'
        )}
        style={{
          background: 'rgba(255, 255, 255, 0.08)',
          boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
          minHeight: '400px',
          maxHeight: 'calc(100vh - 100px)',
        }}
      >
        {/* Session list */}
        <div className="flex-1 flex flex-col overflow-y-auto p-2 space-y-1">
          {sessions.length === 0 ? (
            <div
              className="flex-1 flex flex-col items-center justify-center text-center px-4"
              style={{ color: 'var(--color-text-muted)' }}
            >
              <MessageCircle className="w-6 h-6 mb-2 opacity-40" />
              <span className="text-xs">No chats yet</span>
              <span className="text-[10px] opacity-70">Start a new conversation</span>
            </div>
          ) : (
            sessions.map((session) => (
              <SessionItem
                key={session.id}
                session={session}
                isActive={session.id === activeSessionId}
                onSelect={() => {
                  setActiveSession(session.id);
                  onToggle(); // Close sidebar after selecting
                }}
                onDelete={() => deleteSession(session.id)}
                onRename={(name) => renameSession(session.id, name)}
              />
            ))
          )}
        </div>

        {/* New Chat button - fixed at bottom */}
        <div className="flex-shrink-0 px-2 py-2 border-t border-white/10">
          <button
            onClick={handleNewChat}
            className="flex items-center justify-center gap-2 w-full py-2 rounded-lg bg-white/10 text-[var(--color-text-secondary)] hover:bg-[var(--color-accent)] hover:text-[var(--color-crust)] transition-colors"
          >
            <Plus className="w-4 h-4" />
            <span className="text-xs">New Chat</span>
          </button>
        </div>
      </div>
    </>
  );
});

ChatSidebar.displayName = 'ChatSidebar';

interface SessionItemProps {
  session: ChatSession;
  isActive: boolean;
  onSelect: () => void;
  onDelete: () => void;
  onRename: (name: string) => void;
}

const SessionItem = memo(
  ({ session, isActive, onSelect, onDelete, onRename }: SessionItemProps) => {
    const [isEditing, setIsEditing] = useState(false);
    const [editName, setEditName] = useState(session.name);
    const [showActions, setShowActions] = useState(false);
    const inputRef = useRef<HTMLInputElement>(null);

    useEffect(() => {
      if (isEditing && inputRef.current) {
        inputRef.current.focus();
        inputRef.current.select();
      }
    }, [isEditing]);

    const handleStartEdit = useCallback((e: React.MouseEvent) => {
      e.stopPropagation();
      setEditName(session.name);
      setIsEditing(true);
      setShowActions(false);
    }, [session.name]);

    const handleConfirmEdit = useCallback(() => {
      const trimmed = editName.trim();
      if (trimmed && trimmed !== session.name) {
        onRename(trimmed);
      }
      setIsEditing(false);
    }, [editName, session.name, onRename]);

    const handleCancelEdit = useCallback(() => {
      setEditName(session.name);
      setIsEditing(false);
    }, [session.name]);

    const handleKeyDown = useCallback(
      (e: React.KeyboardEvent) => {
        if (e.key === 'Enter') {
          handleConfirmEdit();
        } else if (e.key === 'Escape') {
          handleCancelEdit();
        }
      },
      [handleConfirmEdit, handleCancelEdit]
    );

    const handleDelete = useCallback(
      (e: React.MouseEvent) => {
        e.stopPropagation();
        onDelete();
      },
      [onDelete]
    );

    return (
      <div
        onClick={onSelect}
        onMouseEnter={() => setShowActions(true)}
        onMouseLeave={() => setShowActions(false)}
        className="group relative flex items-center gap-2 px-3 py-2.5 rounded-lg cursor-pointer transition-all duration-150 hover:bg-white/10"
      >
        <div className="flex-1 min-w-0">
          {isEditing ? (
            <div className="flex items-center gap-1">
              <input
                ref={inputRef}
                type="text"
                value={editName}
                onChange={(e) => setEditName(e.target.value)}
                onKeyDown={handleKeyDown}
                onBlur={handleConfirmEdit}
                onClick={(e) => e.stopPropagation()}
                className="flex-1 px-1.5 py-0.5 text-xs rounded-md outline-none bg-black/20"
                style={{ color: 'var(--color-text)' }}
              />
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  handleConfirmEdit();
                }}
                className="p-0.5 rounded hover:bg-white/10"
                style={{ color: 'var(--color-text-muted)' }}
              >
                <Check className="w-3 h-3" />
              </button>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  handleCancelEdit();
                }}
                className="p-0.5 rounded hover:bg-white/10"
                style={{ color: 'var(--color-text-muted)' }}
              >
                <X className="w-3 h-3" />
              </button>
            </div>
          ) : (
            <div className="flex items-center gap-1.5">
              {session.branchedFrom && (
                <span title="Branched chat">
                  <GitBranch
                    className="w-3 h-3 flex-shrink-0"
                    style={{ color: 'var(--color-text-muted)' }}
                  />
                </span>
              )}
              <div
                className="text-xs font-medium truncate"
                style={{
                  color: 'var(--color-text)',
                  opacity: isActive ? 1 : 0.5,
                }}
              >
                {session.name}
              </div>
            </div>
          )}
        </div>

        {/* Action buttons */}
        {!isEditing && (
          <div
            className={cn(
              'flex items-center gap-0.5 transition-opacity',
              showActions ? 'opacity-100' : 'opacity-0'
            )}
          >
            <button
              onClick={handleStartEdit}
              className="p-1.5 rounded-lg hover:bg-white/10 transition-colors"
              style={{ color: 'var(--color-text-muted)' }}
              title="Rename"
            >
              <Pencil className="w-3 h-3" />
            </button>
            <button
              onClick={handleDelete}
              className="p-1.5 rounded-lg hover:bg-white/10 transition-colors"
              style={{ color: 'var(--color-text-muted)' }}
              title="Delete"
            >
              <Trash2 className="w-3 h-3" />
            </button>
          </div>
        )}
      </div>
    );
  }
);

SessionItem.displayName = 'SessionItem';
