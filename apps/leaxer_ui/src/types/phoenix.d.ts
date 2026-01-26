declare module 'phoenix' {
  export class Socket {
    constructor(endPoint: string, opts?: object);
    connect(): void;
    disconnect(): void;
    channel(topic: string, params?: object): Channel;
    onClose(callback: () => void): void;
    onError(callback: (error: unknown) => void): void;
  }

  export class Channel {
    join(): Push;
    leave(): Push;
    push(event: string, payload?: object): Push;
    on<T = unknown>(event: string, callback: (payload: T) => void): void;
    onClose(callback: () => void): void;
    onError(callback: () => void): void;
  }

  export class Push {
    receive<T = unknown>(status: string, callback: (response: T) => void): Push;
  }
}
