import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { subscribeToProject } from "@/lib/project-channel";
import type { Flow } from "@/types";

function upsertFlow(list: Flow[], next: Flow): Flow[] {
  const idx = list.findIndex((entry) => entry.id === next.id);
  if (idx === -1) return [next, ...list];
  const copy = list.slice();
  copy[idx] = next;
  return copy;
}

function removeFlow(list: Flow[], id: number): Flow[] {
  return list.filter((entry) => entry.id !== id);
}

const ACTIVE_STATUSES = new Set(["ongoing", "stalled"]);

export function useFlows(projectId: number | null): { flows: Flow[] } {
  const [flows, setFlows] = useState<Flow[]>([]);

  useEffect(() => {
    if (!projectId) {
      setFlows([]);
      return;
    }

    let cancelled = false;
    api
      .listFlows(projectId)
      .then((data) => {
        if (!cancelled) setFlows(data);
      })
      .catch(() => {});

    return () => {
      cancelled = true;
    };
  }, [projectId]);

  useEffect(() => {
    if (!projectId) return;

    const handle = (payload: Record<string, unknown>) => {
      const flow = payload.flow as Flow | undefined;
      if (!flow) return;
      if (ACTIVE_STATUSES.has(flow.status)) {
        setFlows((current) => upsertFlow(current, flow));
      } else {
        setFlows((current) => removeFlow(current, flow.id));
      }
    };

    const onArchived = (payload: Record<string, unknown>) => {
      const flow = payload.flow as Flow | undefined;
      if (flow) setFlows((current) => removeFlow(current, flow.id));
    };

    return subscribeToProject(projectId, [
      { event: "flow.created", handler: handle },
      { event: "flow.updated", handler: handle },
      { event: "flow.membership_updated", handler: handle },
      { event: "flow.archived", handler: onArchived },
    ]);
  }, [projectId]);

  return { flows };
}
