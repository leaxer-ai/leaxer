import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import { useChatStore } from './chatStore';

export type ViewType = 'chat' | 'node';

export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  timestamp: number;
}

interface ViewState {
  // Current view
  currentView: ViewType;
  setCurrentView: (view: ViewType) => void;

  // Chat state
  chatMessages: ChatMessage[];
  addChatMessage: (message: Omit<ChatMessage, 'id' | 'timestamp'>) => void;
  clearChatMessages: () => void;
}

export const useViewStore = create<ViewState>()(
  persist(
    (set, get) => ({
      // Default to chat view
      currentView: 'chat',
      setCurrentView: (view) => {
        const previousView = get().currentView;
        set({ currentView: view });

        // When switching TO chat view from another view, start a new chat
        if (view === 'chat' && previousView !== 'chat') {
          useChatStore.getState().startNewChat();
        }
      },

      // Chat state
      chatMessages: [],
      addChatMessage: (message) =>
        set((state) => ({
          chatMessages: [
            ...state.chatMessages,
            {
              ...message,
              id: `msg_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
              timestamp: Date.now(),
            },
          ],
        })),
      clearChatMessages: () => set({ chatMessages: [] }),
    }),
    {
      name: 'leaxer-view-store',
      partialize: (state) => ({
        // Only persist current view, not chat history or params
        currentView: state.currentView,
      }),
    }
  )
);
