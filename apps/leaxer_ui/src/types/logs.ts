export type LogLevel = 'debug' | 'info' | 'warning' | 'error';

export interface LogEntry {
  id: string;
  timestamp: string;
  level: LogLevel;
  message: string;
  metadata?: Record<string, string>;
}

export interface LogBatch {
  logs: LogEntry[];
}

export interface LogChannelJoinResponse {
  recent_logs: LogEntry[];
}
