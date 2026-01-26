import { useNotificationStore } from '../stores/notificationStore';
import { Notification } from './Notification';
import './NotificationCenter.css';

export function NotificationCenter() {
  const notifications = useNotificationStore((s) => s.notifications);

  if (notifications.length === 0) return null;

  return (
    <div className="fixed top-4 left-1/2 -translate-x-1/2 z-[60] flex flex-col gap-2">
      {notifications.map((notification) => (
        <Notification key={notification.id} notification={notification} />
      ))}
    </div>
  );
}
