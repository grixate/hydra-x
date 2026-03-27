import { Socket } from "phoenix";

let socket: Socket | null = null;

export function getSocket() {
  if (!socket) {
    const path = import.meta.env.VITE_SOCKET_PATH ?? "/socket";
    socket = new Socket(path, { params: {} });
    socket.connect();
  }

  return socket;
}
