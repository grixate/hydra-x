declare module "phoenix" {
  export class Socket {
    constructor(endpoint: string, opts?: { params?: Record<string, unknown> });
    connect(): void;
    channel(topic: string, params?: Record<string, unknown>): {
      join(): {
        receive(status: string, callback: (payload: any) => void): any;
      };
      on(event: string, callback: (payload: any) => void): void;
      leave(): void;
    };
  }
}
