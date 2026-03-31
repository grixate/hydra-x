import type { GraphData } from "@/types";

export type SmartView =
  | "coverage"
  | "flow"
  | "stale"
  | "contradictions"
  | "orphans"
  | "next_actions";

export function applySmartView(view: SmartView, data: GraphData): Set<string> {
  switch (view) {
    case "coverage":
      return coverageView(data);
    case "flow":
      return flowView(data);
    case "stale":
      return staleView(data);
    case "contradictions":
      return contradictionsView(data);
    case "orphans":
      return orphansView(data);
    case "next_actions":
      return nextActionsView(data);
  }
}

function coverageView(data: GraphData): Set<string> {
  const avg =
    data.nodes.reduce((sum, n) => sum + n.connection_count, 0) /
    data.nodes.length;
  return new Set(
    data.nodes
      .filter(
        (n) =>
          n.connection_count < avg * 0.5 && n.node_type !== "source",
      )
      .map((n) => n.id),
  );
}

function flowView(data: GraphData): Set<string> {
  const nodesWithDownstream = new Set(data.edges.map((e) => e.source));
  return new Set(
    data.nodes
      .filter(
        (n) =>
          !nodesWithDownstream.has(n.id) &&
          n.node_type !== "task" &&
          n.node_type !== "learning",
      )
      .map((n) => n.id),
  );
}

function staleView(data: GraphData): Set<string> {
  const cutoff = Date.now() - 60 * 24 * 60 * 60 * 1000;
  return new Set(
    data.nodes
      .filter((n) => n.updated_at && new Date(n.updated_at).getTime() < cutoff)
      .map((n) => n.id),
  );
}

function contradictionsView(data: GraphData): Set<string> {
  const ids = new Set<string>();
  for (const e of data.edges) {
    if (e.kind === "contradicts") {
      ids.add(e.source);
      ids.add(e.target);
    }
  }
  for (const f of data.flags) {
    if (f.flag_type === "contradicted") {
      ids.add(f.node_id);
    }
  }
  return ids;
}

function orphansView(data: GraphData): Set<string> {
  const nodesWithIncoming = new Set(data.edges.map((e) => e.target));
  return new Set(
    data.nodes
      .filter(
        (n) =>
          !nodesWithIncoming.has(n.id) &&
          n.node_type !== "source" &&
          n.node_type !== "signal",
      )
      .map((n) => n.id),
  );
}

function nextActionsView(data: GraphData): Set<string> {
  return new Set([
    ...orphansView(data),
    ...staleView(data),
    ...flowView(data),
  ]);
}
