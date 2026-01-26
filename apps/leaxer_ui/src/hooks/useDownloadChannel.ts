import { useEffect, useRef, useCallback } from 'react';
import { Socket, Channel } from 'phoenix';
import { useDownloadStore, type ActiveDownload, type DownloadStatus } from '../stores/downloadStore';
import { useSettingsStore } from '../stores/settingsStore';
import { createLogger } from '../lib/logger';

const log = createLogger('downloads');

interface DownloadPayload {
  download_id: string;
  model_id: string;
  model_name: string;
  filename: string;
  status: string;
  percentage: number;
  bytes_downloaded: number;
  total_bytes: number;
  speed_bps: number;
  error?: string;
  target_path?: string;
  duration_seconds?: number;
}

function payloadToDownload(payload: DownloadPayload): ActiveDownload {
  return {
    download_id: payload.download_id,
    model_id: payload.model_id,
    model_name: payload.model_name,
    filename: payload.filename,
    status: payload.status as DownloadStatus,
    percentage: payload.percentage,
    bytes_downloaded: payload.bytes_downloaded,
    total_bytes: payload.total_bytes,
    speed_bps: payload.speed_bps,
    error: payload.error,
    target_path: payload.target_path,
    duration_seconds: payload.duration_seconds,
  };
}

export function useDownloadChannel() {
  const socketRef = useRef<Socket | null>(null);
  const channelRef = useRef<Channel | null>(null);

  const setDownload = useDownloadStore((s) => s.setDownload);
  const checkInstalled = useDownloadStore((s) => s.checkInstalled);
  const getBackendWsUrl = useSettingsStore((s) => s.getBackendWsUrl);

  const connectChannel = useCallback(() => {
    if (socketRef.current && channelRef.current) {
      return;
    }

    // Get the WebSocket URL (handles LAN access automatically)
    const backendWsUrl = getBackendWsUrl();

    // Normalize to ws://host:port/socket format
    let wsUrl = backendWsUrl
      .replace(/^http/, 'ws')           // http(s) -> ws(s)
      .replace(/\/socket\/?$/, '')      // remove trailing /socket if present
      .replace(/\/$/, '');              // remove trailing slash
    wsUrl = `${wsUrl}/socket`;          // add /socket
    const socket = new Socket(wsUrl);

    socket.connect();
    socketRef.current = socket;

    const channel = socket.channel('downloads:lobby');
    channelRef.current = channel;

    channel.on('download_started', (payload: DownloadPayload) => {
      setDownload(payload.download_id, payloadToDownload(payload));
    });

    channel.on('progress_update', (payload: DownloadPayload) => {
      setDownload(payload.download_id, payloadToDownload(payload));
    });

    channel.on('download_complete', (payload: DownloadPayload) => {
      setDownload(payload.download_id, payloadToDownload(payload));
      checkInstalled();
    });

    channel.on('download_failed', (payload: DownloadPayload) => {
      setDownload(payload.download_id, payloadToDownload(payload));
    });

    channel.on('download_cancelled', (payload: DownloadPayload) => {
      setDownload(payload.download_id, payloadToDownload(payload));
    });

    channel.join()
      .receive('ok', () => {
        log.debug('Connected to channel');
      })
      .receive('error', (resp) => {
        log.error('Failed to connect:', resp);
      });

  }, [getBackendWsUrl, setDownload, checkInstalled]);

  const disconnectChannel = useCallback(() => {
    if (channelRef.current) {
      channelRef.current.leave();
      channelRef.current = null;
    }
    if (socketRef.current) {
      socketRef.current.disconnect();
      socketRef.current = null;
    }
  }, []);

  const startDownload = useCallback(async (modelId: string, targetDir?: string): Promise<string> => {
    return new Promise((resolve, reject) => {
      if (!channelRef.current) {
        reject(new Error('Channel not connected'));
        return;
      }

      channelRef.current
        .push('start_download', { model_id: modelId, target_dir: targetDir })
        .receive('ok', (response: { download_id: string }) => {
          resolve(response.download_id);
        })
        .receive('error', (error: { reason?: string }) => {
          reject(new Error(error.reason || 'Failed to start download'));
        })
        .receive('timeout', () => {
          reject(new Error('Request timed out'));
        });
    });
  }, []);

  const cancelDownload = useCallback(async (downloadId: string): Promise<void> => {
    return new Promise((resolve, reject) => {
      if (!channelRef.current) {
        reject(new Error('Channel not connected'));
        return;
      }

      channelRef.current
        .push('cancel_download', { download_id: downloadId })
        .receive('ok', () => {
          resolve();
        })
        .receive('error', (error: { reason?: string }) => {
          reject(new Error(error.reason || 'Failed to cancel download'));
        })
        .receive('timeout', () => {
          reject(new Error('Request timed out'));
        });
    });
  }, []);

  const getProgress = useCallback(async (downloadId: string): Promise<ActiveDownload> => {
    return new Promise((resolve, reject) => {
      if (!channelRef.current) {
        reject(new Error('Channel not connected'));
        return;
      }

      channelRef.current
        .push('get_progress', { download_id: downloadId })
        .receive('ok', (response: DownloadPayload) => {
          resolve(payloadToDownload(response));
        })
        .receive('error', (error: { reason?: string }) => {
          reject(new Error(error.reason || 'Failed to get progress'));
        })
        .receive('timeout', () => {
          reject(new Error('Request timed out'));
        });
    });
  }, []);

  useEffect(() => {
    connectChannel();
    return () => {
      disconnectChannel();
    };
  }, [connectChannel, disconnectChannel]);

  return {
    startDownload,
    cancelDownload,
    getProgress,
    connectChannel,
    disconnectChannel,
  };
}
