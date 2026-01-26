/**
 * Conditional debug logger that only outputs in development mode.
 * Prevents console.log spam in production builds.
 */

const isDev = import.meta.env.DEV;

type LogLevel = 'debug' | 'info' | 'warn' | 'error';

interface LoggerOptions {
  /** Enable/disable this logger category */
  enabled?: boolean;
}

interface Logger {
  debug: (...args: unknown[]) => void;
  info: (...args: unknown[]) => void;
  warn: (...args: unknown[]) => void;
  error: (...args: unknown[]) => void;
}

/**
 * Creates a namespaced logger that only logs in development mode.
 *
 * @param namespace - Prefix for log messages (e.g., 'WebSocket', 'App')
 * @param options - Logger configuration options
 * @returns Logger object with debug, info, warn, error methods
 *
 * @example
 * const log = createLogger('WebSocket');
 * log.debug('Connected'); // Outputs: [WebSocket] Connected (dev only)
 */
export function createLogger(namespace: string, options: LoggerOptions = {}): Logger {
  const { enabled = true } = options;
  const prefix = `[${namespace}]`;

  const shouldLog = isDev && enabled;

  const log = (level: LogLevel, ...args: unknown[]): void => {
    if (!shouldLog) return;

    switch (level) {
      case 'debug':
        console.log(prefix, ...args);
        break;
      case 'info':
        console.info(prefix, ...args);
        break;
      case 'warn':
        console.warn(prefix, ...args);
        break;
      case 'error':
        console.error(prefix, ...args);
        break;
    }
  };

  return {
    debug: (...args: unknown[]) => log('debug', ...args),
    info: (...args: unknown[]) => log('info', ...args),
    warn: (...args: unknown[]) => log('warn', ...args),
    error: (...args: unknown[]) => log('error', ...args),
  };
}

/**
 * No-op logger for production or disabled categories.
 * All methods do nothing.
 */
export const noopLogger: Logger = {
  debug: () => {},
  info: () => {},
  warn: () => {},
  error: () => {},
};
