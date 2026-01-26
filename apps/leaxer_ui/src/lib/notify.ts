import { useNotificationStore, type NotificationType } from '../stores/notificationStore';
import { useSettingsStore } from '../stores/settingsStore';
import { playSound } from './sounds';

interface NotifyOptions {
  description?: string;
  duration?: number;  // ms, 0 = persistent
  silent?: boolean;   // skip sound
}

const DEFAULT_DURATION = 5000;

function createNotification(type: NotificationType, message: string, options?: NotifyOptions): string {
  const { addNotification } = useNotificationStore.getState();
  const settings = useSettingsStore.getState();

  // Play sound unless silent (use error sound from settings for error/warning, complete sound for success/info)
  if (!options?.silent && settings.soundsEnabled) {
    if (type === 'error' || type === 'warning') {
      playSound(settings.soundError);
    } else {
      playSound(settings.soundComplete);
    }
  }

  return addNotification({
    type,
    message,
    description: options?.description,
    duration: options?.duration ?? DEFAULT_DURATION,
  });
}

export const notify = {
  success: (message: string, options?: NotifyOptions) => createNotification('success', message, options),
  warning: (message: string, options?: NotifyOptions) => createNotification('warning', message, options),
  error: (message: string, options?: NotifyOptions) => createNotification('error', message, options),
  info: (message: string, options?: NotifyOptions) => createNotification('info', message, options),
  dismiss: (id: string) => useNotificationStore.getState().dismissNotification(id),
  clearAll: () => useNotificationStore.getState().clearAll(),
};
