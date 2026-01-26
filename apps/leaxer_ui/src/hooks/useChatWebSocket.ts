import { useEffect, useRef, useCallback, useState } from 'react';
import { Socket, Channel } from 'phoenix';
import { useSettingsStore } from '@/stores/settingsStore';
import { useChatStore } from '@/stores/chatStore';
import type {
  ChatCompletionMessage,
  ChatSettings,
  ModelStatusPayload,
  StreamChunkPayload,
  GenerationCompletePayload,
  GenerationErrorPayload,
} from '@/types/chat';
import { createLogger } from '@/lib/logger';

const log = createLogger('ChatWebSocket');

interface ToolStatusPayload {
  status: 'searching' | 'complete' | 'error';
  query?: string;
  error?: string;
  references?: Array<{
    index: number;
    title: string;
    url: string;
    description?: string;
    image?: string;
    site_name?: string;
    favicon?: string;
  }>;
}

interface ArtifactStatusPayload {
  status: 'pending' | 'generating' | 'complete' | 'error';
  title?: string;
  content?: string;
  error?: string;
}

interface ArtifactChunkPayload {
  content: string;
}

export interface LlmServerHealthPayload {
  status: 'idle' | 'loading' | 'ready' | 'stopped' | 'restarting' | 'error';
  model: string | null;
  server_port: number;
  os_pid: number | null;
  binary_available: boolean;
  error?: string;
}

interface LlmServerStatusPayload {
  status: 'idle' | 'loading' | 'ready' | 'restarting' | 'error';
  model?: string;
  error?: string;
}

interface UseChatWebSocketOptions {
  onModelStatus?: (status: ModelStatusPayload) => void;
  onStreamChunk?: (chunk: StreamChunkPayload) => void;
  onGenerationComplete?: (data: GenerationCompletePayload) => void;
  onGenerationError?: (error: GenerationErrorPayload) => void;
  onToolStatus?: (status: ToolStatusPayload) => void;
  onArtifactStatus?: (status: ArtifactStatusPayload) => void;
  onArtifactChunk?: (chunk: ArtifactChunkPayload) => void;
  onLlmServerStatus?: (status: LlmServerStatusPayload) => void;
  onConnected?: () => void;
  onDisconnected?: () => void;
}

export function useChatWebSocket(options: UseChatWebSocketOptions = {}) {
  const {
    onModelStatus,
    onStreamChunk,
    onGenerationComplete,
    onGenerationError,
    onToolStatus,
    onArtifactStatus,
    onArtifactChunk,
    onLlmServerStatus,
    onConnected,
    onDisconnected,
  } = options;

  const socketRef = useRef<Socket | null>(null);
  const channelRef = useRef<Channel | null>(null);
  const [connected, setConnected] = useState(false);

  // Store callbacks in refs to avoid reconnecting when they change
  const onModelStatusRef = useRef(onModelStatus);
  const onStreamChunkRef = useRef(onStreamChunk);
  const onGenerationCompleteRef = useRef(onGenerationComplete);
  const onGenerationErrorRef = useRef(onGenerationError);
  const onToolStatusRef = useRef(onToolStatus);
  const onArtifactStatusRef = useRef(onArtifactStatus);
  const onArtifactChunkRef = useRef(onArtifactChunk);
  const onLlmServerStatusRef = useRef(onLlmServerStatus);
  const onConnectedRef = useRef(onConnected);
  const onDisconnectedRef = useRef(onDisconnected);

  useEffect(() => {
    onModelStatusRef.current = onModelStatus;
    onStreamChunkRef.current = onStreamChunk;
    onGenerationCompleteRef.current = onGenerationComplete;
    onGenerationErrorRef.current = onGenerationError;
    onToolStatusRef.current = onToolStatus;
    onArtifactStatusRef.current = onArtifactStatus;
    onArtifactChunkRef.current = onArtifactChunk;
    onLlmServerStatusRef.current = onLlmServerStatus;
    onConnectedRef.current = onConnected;
    onDisconnectedRef.current = onDisconnected;
  }, [onModelStatus, onStreamChunk, onGenerationComplete, onGenerationError, onToolStatus, onArtifactStatus, onArtifactChunk, onLlmServerStatus, onConnected, onDisconnected]);

  // Get the WebSocket URL from settings
  const getBackendWsUrl = useSettingsStore((s) => s.getBackendWsUrl);

  useEffect(() => {
    const url = getBackendWsUrl();
    log.debug('Connecting to chat WebSocket at:', url);

    const socket = new Socket(url, {
      reconnectAfterMs: (tries: number) => Math.min(1000 * Math.pow(2, tries - 1), 10000),
      heartbeatIntervalMs: 30000,
    });

    // Socket-level event handlers
    // @ts-expect-error Phoenix Socket types are incomplete
    socket.onOpen(() => {
      log.debug('Chat WebSocket connected');
    });

    socket.onError((error: unknown) => {
      log.error('Chat WebSocket error:', error);
    });

    socket.onClose(() => {
      log.debug('Chat WebSocket closed');
    });

    socket.connect();
    socketRef.current = socket;

    const channel = socket.channel('chat:main', {});
    channelRef.current = channel;

    let hasNotifiedDisconnect = false;

    const handleDisconnect = (reason: string) => {
      log.debug(`Chat channel ${reason}`);
      setConnected(false);
      useChatStore.getState().setConnected(false);
      if (!hasNotifiedDisconnect) {
        hasNotifiedDisconnect = true;
        onDisconnectedRef.current?.();
      }
    };

    // @ts-expect-error Phoenix Channel types don't match runtime behavior
    channel.onClose((payload: unknown) => {
      log.debug('Chat channel closed:', payload);
      handleDisconnect('closed');
    });

    // @ts-expect-error Phoenix Channel types don't match runtime behavior
    channel.onError((reason: unknown) => {
      log.error('Chat channel error:', reason);
      handleDisconnect('error - will auto-reconnect');
    });

    log.debug('Joining chat:main channel...');

    channel
      .join()
      .receive('ok', () => {
        log.debug('Successfully joined chat:main channel');
        hasNotifiedDisconnect = false;
        setConnected(true);
        useChatStore.getState().setConnected(true);
        onConnectedRef.current?.();
      })
      .receive('error', (resp: unknown) => {
        log.error('Failed to join chat channel:', resp);
        useChatStore.getState().setConnected(false);
      })
      .receive('timeout', () => {
        log.error('Chat channel join timed out');
        useChatStore.getState().setConnected(false);
      });

    // Handle model status updates
    channel.on('model_status', (data: ModelStatusPayload) => {
      log.debug('Received model_status:', data);
      onModelStatusRef.current?.(data);
      useChatStore.getState().setModelStatus(data.status);
    });

    // Handle stream chunks
    channel.on('stream_chunk', (data: StreamChunkPayload) => {
      onStreamChunkRef.current?.(data);
    });

    // Handle generation complete
    channel.on('generation_complete', (data: GenerationCompletePayload) => {
      log.debug('Received generation_complete:', data);
      onGenerationCompleteRef.current?.(data);
    });

    // Handle generation error
    channel.on('generation_error', (data: GenerationErrorPayload) => {
      log.error('Received generation_error:', data);
      onGenerationErrorRef.current?.(data);
    });

    // Handle tool status (web search)
    channel.on('tool_status', (data: ToolStatusPayload) => {
      log.debug('Received tool_status:', data);
      onToolStatusRef.current?.(data);
    });

    // Handle artifact status (document generation)
    channel.on('artifact_status', (data: ArtifactStatusPayload) => {
      log.debug('Received artifact_status:', data);
      onArtifactStatusRef.current?.(data);
    });

    // Handle artifact content chunks (streaming document generation)
    channel.on('artifact_chunk', (data: ArtifactChunkPayload) => {
      log.debug('Received artifact_chunk:', data.content.length, 'chars');
      onArtifactChunkRef.current?.(data);
    });

    // Handle LLM server status updates
    channel.on('llm_server_status', (data: LlmServerStatusPayload) => {
      log.debug('Received llm_server_status:', data);
      onLlmServerStatusRef.current?.(data);
    });

    return () => {
      channel.leave();
      socket.disconnect();
    };
  }, [getBackendWsUrl]);

  /**
   * Send a chat message and receive streaming response.
   */
  const sendMessage = useCallback(
    (
      messages: ChatCompletionMessage[],
      model: string,
      settings: ChatSettings,
      internetEnabled = false,
      searchProvider = 'searxng',
      searchMaxResults = 3,
      thinkingEnabled = false,
      artifactEnabled = false,
      existingArtifact?: string
    ): Promise<void> => {
      if (!channelRef.current) {
        return Promise.reject(new Error('Not connected to chat channel'));
      }

      // Debug: log what we're sending
      console.log('[WebSocket] Sending messages:', messages.length);
      messages.forEach((m, i) => {
        console.log(`  [${i}] role=${m.role}, content_length=${m.content.length}`);
        if (m.role === 'user') {
          console.log(`  [${i}] content preview:`, m.content.slice(0, 200));
        }
      });
      if (existingArtifact) {
        console.log('[WebSocket] Existing artifact:', existingArtifact.length, 'chars');
      }

      return new Promise((resolve, reject) => {
        channelRef.current!
          .push('send_message', {
            messages,
            model,
            settings,
            internet_enabled: internetEnabled,
            search_provider: searchProvider,
            search_max_results: searchMaxResults,
            thinking_enabled: thinkingEnabled,
            artifact_enabled: artifactEnabled,
            existing_artifact: existingArtifact || null,
          })
          .receive('ok', () => {
            log.debug('Message sent, streaming started');
            resolve();
          })
          .receive('error', (resp: { reason: string }) => {
            log.error('Failed to send message:', resp);
            reject(new Error(resp.reason));
          });
      });
    },
    []
  );

  /**
   * Abort the current generation.
   */
  const abortGeneration = useCallback(() => {
    if (!channelRef.current) return;

    channelRef.current.push('abort_generation', {});
  }, []);

  /**
   * Preload a model for faster first response.
   */
  const loadModel = useCallback((model: string): Promise<void> => {
    if (!channelRef.current) {
      return Promise.reject(new Error('Not connected to chat channel'));
    }

    return new Promise((resolve, reject) => {
      channelRef.current!
        .push('load_model', { model })
        .receive('ok', () => {
          log.debug('Model loading started');
          resolve();
        })
        .receive('error', (resp: { reason: string }) => {
          log.error('Failed to load model:', resp);
          reject(new Error(resp.reason));
        });
    });
  }, []);

  /**
   * Get current model status from server.
   */
  const getModelStatus = useCallback((): Promise<ModelStatusPayload> => {
    if (!channelRef.current) {
      return Promise.reject(new Error('Not connected to chat channel'));
    }

    return new Promise((resolve, reject) => {
      channelRef.current!
        .push('get_model_status', {})
        .receive('ok', (data: ModelStatusPayload) => {
          resolve(data);
        })
        .receive('error', (resp: { reason: string }) => {
          reject(new Error(resp.reason));
        });
    });
  }, []);

  /**
   * Get detailed LLM server health information.
   */
  const getLlmServerHealth = useCallback((): Promise<LlmServerHealthPayload> => {
    if (!channelRef.current) {
      return Promise.reject(new Error('Not connected to chat channel'));
    }

    return new Promise((resolve, reject) => {
      channelRef.current!
        .push('get_llm_server_health', {})
        .receive('ok', (data: LlmServerHealthPayload) => {
          resolve(data);
        })
        .receive('error', (resp: { reason: string }) => {
          reject(new Error(resp.reason));
        });
    });
  }, []);

  /**
   * Restart the LLM server (stops current server, ready for fresh start).
   */
  const restartLlmServer = useCallback((): Promise<void> => {
    if (!channelRef.current) {
      return Promise.reject(new Error('Not connected to chat channel'));
    }

    return new Promise((resolve, reject) => {
      channelRef.current!
        .push('restart_llm_server', {})
        .receive('ok', () => {
          log.debug('LLM server restart initiated');
          resolve();
        })
        .receive('error', (resp: { reason: string }) => {
          log.error('Failed to restart LLM server:', resp);
          reject(new Error(resp.reason));
        });
    });
  }, []);

  /**
   * Start the LLM server with an optional model.
   * If model is provided, loads that model. Otherwise just checks availability.
   */
  const startLlmServer = useCallback((model?: string): Promise<void> => {
    if (!channelRef.current) {
      return Promise.reject(new Error('Not connected to chat channel'));
    }

    return new Promise((resolve, reject) => {
      channelRef.current!
        .push('start_llm_server', { model })
        .receive('ok', () => {
          log.debug('LLM server start initiated');
          resolve();
        })
        .receive('error', (resp: { reason: string }) => {
          log.error('Failed to start LLM server:', resp);
          reject(new Error(resp.reason));
        });
    });
  }, []);

  return {
    connected,
    sendMessage,
    abortGeneration,
    loadModel,
    getModelStatus,
    getLlmServerHealth,
    restartLlmServer,
    startLlmServer,
  };
}
