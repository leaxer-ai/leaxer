import { create } from 'zustand';

export type NotificationType = 'success' | 'warning' | 'error' | 'info';

export interface Notification {
  id: string;
  type: NotificationType;
  message: string;
  description?: string;
  duration: number;  // ms, 0 = persistent
  createdAt: number;
  dismissing?: boolean;  // exit animation flag
}

interface NotificationState {
  notifications: Notification[];
  addNotification: (notification: Omit<Notification, 'id' | 'createdAt' | 'dismissing'>) => string;
  dismissNotification: (id: string) => void;
  removeNotification: (id: string) => void;
  clearAll: () => void;
}

export const useNotificationStore = create<NotificationState>()((set, get) => ({
  notifications: [],

  addNotification: (notification) => {
    const id = crypto.randomUUID();
    const newNotification: Notification = {
      ...notification,
      id,
      createdAt: Date.now(),
      dismissing: false,
    };

    set((state) => ({
      notifications: [...state.notifications, newNotification],
    }));

    // Auto-dismiss is handled by the Notification component (supports hover pause)

    return id;
  },

  dismissNotification: (id) => {
    // Trigger exit animation
    set((state) => ({
      notifications: state.notifications.map((n) =>
        n.id === id ? { ...n, dismissing: true } : n
      ),
    }));

    // Remove after animation completes (300ms)
    setTimeout(() => {
      get().removeNotification(id);
    }, 300);
  },

  removeNotification: (id) => {
    set((state) => ({
      notifications: state.notifications.filter((n) => n.id !== id),
    }));
  },

  clearAll: () => {
    // Dismiss all notifications with animation
    const { notifications, dismissNotification } = get();
    notifications.forEach((n) => dismissNotification(n.id));
  },
}));
