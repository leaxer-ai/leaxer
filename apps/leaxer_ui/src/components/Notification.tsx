import { useEffect, useState, useRef } from 'react';
import { X, CheckCircle, AlertTriangle, XCircle, Info } from 'lucide-react';
import { cn } from '@/lib/utils';
import type { Notification as NotificationType } from '../stores/notificationStore';
import { useNotificationStore } from '../stores/notificationStore';

interface NotificationProps {
  notification: NotificationType;
}

const iconMap = {
  success: CheckCircle,
  warning: AlertTriangle,
  error: XCircle,
  info: Info,
};

export function Notification({ notification }: NotificationProps) {
  const dismissNotification = useNotificationStore((s) => s.dismissNotification);
  const [isHovered, setIsHovered] = useState(false);
  const [_remainingTime, setRemainingTime] = useState(notification.duration);
  const lastTickRef = useRef(Date.now());

  const Icon = iconMap[notification.type];

  // Auto-dismiss countdown (pauses on hover)
  useEffect(() => {
    if (notification.duration <= 0 || notification.dismissing) return;

    lastTickRef.current = Date.now();

    const interval = setInterval(() => {
      if (isHovered) {
        // Reset the last tick when hovered so we don't count hovered time
        lastTickRef.current = Date.now();
        return;
      }

      const now = Date.now();
      const elapsed = now - lastTickRef.current;
      lastTickRef.current = now;

      setRemainingTime((prev) => {
        const newTime = prev - elapsed;
        if (newTime <= 0) {
          dismissNotification(notification.id);
          return 0;
        }
        return newTime;
      });
    }, 100);

    return () => clearInterval(interval);
  }, [notification.id, notification.duration, notification.dismissing, isHovered, dismissNotification]);

  return (
    <div
      className={cn(
        'relative flex items-center gap-3 h-[44px] px-5 rounded-full backdrop-blur-xl overflow-hidden',
        notification.dismissing ? 'notification-exit' : 'notification-enter'
      )}
      style={{
        background: 'rgba(255, 255, 255, 0.08)',
        boxShadow: '0 8px 32px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)',
      }}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
    >
      {/* Type icon */}
      <Icon
        size={16}
        className="flex-shrink-0"
        style={{ color: 'var(--color-text-muted)' }}
      />

      {/* Message */}
      <span
        className="text-[13px] font-medium"
        style={{ color: 'var(--color-text)' }}
      >
        {notification.message}
      </span>

      {/* Description (if any) */}
      {notification.description && (
        <>
          <span style={{ color: 'var(--color-text-muted)' }}>·</span>
          <span
            className="text-[13px]"
            style={{ color: 'var(--color-text-secondary)' }}
          >
            {notification.description}
          </span>
        </>
      )}

      {/* Close button */}
      <button
        onClick={() => dismissNotification(notification.id)}
        className="flex-shrink-0 p-1 rounded-full transition-colors hover:bg-white/10 ml-1"
        style={{ color: 'var(--color-text-muted)' }}
      >
        <X size={14} />
      </button>
    </div>
  );
}
