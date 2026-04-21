import type { Channel } from "phoenix";
import { getSocket } from "./socket";

type Handler = (payload: Record<string, unknown>) => void;

type Entry = {
  channel: Channel;
  refCount: number;
  handlers: Map<string, Set<Handler>>;
};

// One Phoenix Channel instance per project, shared across all components that
// care about project-level events. Ref-counted so the last unsubscriber
// leaves the channel; otherwise earlier components would orphan late
// subscribers with a dead channel.
const registry = new Map<number, Entry>();

function getOrJoin(projectId: number): Entry {
  let entry = registry.get(projectId);
  if (entry) return entry;

  const channel = getSocket().channel(`project:${projectId}`);
  channel.join();

  entry = { channel, refCount: 0, handlers: new Map() };
  registry.set(projectId, entry);
  return entry;
}

export function subscribeToProject(
  projectId: number,
  events: Array<{ event: string; handler: Handler }>,
): () => void {
  const entry = getOrJoin(projectId);
  entry.refCount += 1;

  for (const { event, handler } of events) {
    let set = entry.handlers.get(event);
    if (!set) {
      set = new Set();
      entry.handlers.set(event, set);

      // Register a single channel-level handler per event; it fans out to
      // every subscriber set.
      entry.channel.on(event, (payload: Record<string, unknown>) => {
        const current = entry!.handlers.get(event);
        if (!current) return;
        for (const fn of current) fn(payload);
      });
    }
    set.add(handler);
  }

  return () => {
    entry.refCount -= 1;

    for (const { event, handler } of events) {
      const set = entry.handlers.get(event);
      set?.delete(handler);
    }

    if (entry.refCount <= 0) {
      entry.channel.leave();
      registry.delete(projectId);
    }
  };
}
