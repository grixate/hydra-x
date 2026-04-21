import { useEffect, useSyncExternalStore, type ReactNode } from "react";
import type { GraphDataNode } from "@/types";

export type GraphCommand =
  | { type: "highlight"; nodeIds?: string[] }
  | { type: "reset" }
  | { type: "focus"; nodeId?: string }
  | { type: "node_created" }
  | { type: "show_lineage"; nodeId?: string }
  | { type: "compose_path"; fromId?: string; toId?: string; label?: string }
  | { type: "compose_radial"; centerId?: string; label?: string }
  | { type: "compose_tree"; rootId?: string; label?: string }
  | { type: "compose_comparison"; leftId?: string; rightId?: string; label?: string };

export interface GraphChatContextValue {
  contextNodes: GraphDataNode[];
  previewNode: GraphDataNode | null;
  onClearContext: () => void;
  onRemoveContext: (nodeId: string) => void;
  onGraphCommand?: (cmd: GraphCommand) => void;
}

// Graph state needs to be consumed by `AgentChatPane`, which renders in a
// *sibling* subtree (app-level ResizableLayout's right pane). React context
// doesn't cross sibling boundaries, so we use a module-level store that
// GraphView publishes into via `GraphChatProvider` and AgentChatPane reads
// via `useGraphChatContext`.

let currentValue: GraphChatContextValue | null = null;
const listeners = new Set<() => void>();

function subscribe(cb: () => void) {
  listeners.add(cb);
  return () => {
    listeners.delete(cb);
  };
}

function getSnapshot() {
  return currentValue;
}

function setValue(next: GraphChatContextValue | null) {
  if (next === currentValue) return;
  currentValue = next;
  listeners.forEach((l) => l());
}

export function GraphChatProvider({
  value,
  children,
}: {
  value: GraphChatContextValue;
  children: ReactNode;
}) {
  useEffect(() => {
    setValue(value);
    return () => {
      // Only clear if we're still the active publisher.
      if (currentValue === value) setValue(null);
    };
  }, [value]);

  return <>{children}</>;
}

export function useGraphChatContext(): GraphChatContextValue | null {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}
