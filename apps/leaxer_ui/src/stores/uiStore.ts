import { create } from 'zustand';

export interface PendingConnection {
  nodeId: string;
  nodeType: string;
  handleId: string;
  handleType: 'source' | 'target';
  dataType: string;
  position: { x: number; y: number };
}

interface UIState {
  commandPaletteOpen: boolean;
  pendingConnection: PendingConnection | null;
  viewportLocked: boolean;
  setCommandPaletteOpen: (open: boolean) => void;
  openCommandPalette: () => void;
  openCommandPaletteWithConnection: (connection: PendingConnection) => void;
  closeCommandPalette: () => void;
  setViewportLocked: (locked: boolean) => void;
  toggleViewportLocked: () => void;
}

export const useUIStore = create<UIState>()((set) => ({
  commandPaletteOpen: false,
  pendingConnection: null,
  viewportLocked: false,
  setCommandPaletteOpen: (open) => set({ commandPaletteOpen: open, pendingConnection: open ? undefined : null }),
  openCommandPalette: () => set({ commandPaletteOpen: true, pendingConnection: null }),
  openCommandPaletteWithConnection: (connection) => set({ commandPaletteOpen: true, pendingConnection: connection }),
  closeCommandPalette: () => set({ commandPaletteOpen: false, pendingConnection: null }),
  setViewportLocked: (locked) => set({ viewportLocked: locked }),
  toggleViewportLocked: () => set((state) => ({ viewportLocked: !state.viewportLocked })),
}));
