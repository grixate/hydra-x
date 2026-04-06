declare module "phoenix" {
  export class Channel {
    join(): Push;
    push(event: string, payload?: Record<string, unknown>): Push;
    on(event: string, callback: (payload: any) => void): number;
    off(event: string, ref?: number): void;
    leave(): Push;
  }

  export class Push {
    receive(status: string, callback: (payload: any) => void): Push;
  }

  export class Socket {
    constructor(endpoint: string, opts?: { params?: Record<string, unknown> });
    connect(): void;
    channel(topic: string, params?: Record<string, unknown>): Channel;
  }
}
