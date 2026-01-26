import { useEffect, useRef, useState, useCallback } from 'react';
import { Socket, Channel } from 'phoenix';
import { createLogger } from '../lib/logger';

const log = createLogger('HardwareChannel');

export interface HardwareStats {
  cpu_percent: number;
  memory_percent: number;
  memory_used_gb: number;
  memory_total_gb: number;
  gpu_percent: number;
  vram_percent: number;
  vram_used_gb: number;
  vram_total_gb: number;
  gpu_name: string | null;
  history: {
    cpu: number[];
    memory: number[];
    gpu: number[];
    vram: number[];
  };
}

interface UseHardwareChannelOptions {
  url?: string;
  enabled?: boolean;
}

const defaultStats: HardwareStats = {
  cpu_percent: 0,
  memory_percent: 0,
  memory_used_gb: 0,
  memory_total_gb: 0,
  gpu_percent: 0,
  vram_percent: 0,
  vram_used_gb: 0,
  vram_total_gb: 0,
  gpu_name: null,
  history: {
    cpu: [],
    memory: [],
    gpu: [],
    vram: [],
  },
};

export function useHardwareChannel(options: UseHardwareChannelOptions = {}) {
  const { url = 'ws://localhost:4000/socket', enabled = true } = options;

  const socketRef = useRef<Socket | null>(null);
  const channelRef = useRef<Channel | null>(null);
  const [connected, setConnected] = useState(false);
  const [stats, setStats] = useState<HardwareStats>(defaultStats);

  useEffect(() => {
    if (!enabled) return;

    const socket = new Socket(url);
    socket.connect();
    socketRef.current = socket;

    const channel = socket.channel('hardware:stats', {});
    channelRef.current = channel;

    channel
      .join()
      .receive('ok', () => {
        log.debug('Joined hardware:stats channel');
        setConnected(true);
      })
      .receive('error', (resp) => {
        log.error('Failed to join hardware channel', resp);
      });

    channel.onClose(() => {
      setConnected(false);
    });

    channel.onError(() => {
      setConnected(false);
    });

    // Handle hardware stats updates
    channel.on('hardware_stats', (data: HardwareStats) => {
      setStats(data);
    });

    return () => {
      channel.leave();
      socket.disconnect();
    };
  }, [url, enabled]);

  const refresh = useCallback(() => {
    if (!channelRef.current) return;
    channelRef.current.push('get_stats', {}).receive('ok', (data: HardwareStats) => {
      setStats(data);
    });
  }, []);

  return {
    connected,
    stats,
    refresh,
  };
}
