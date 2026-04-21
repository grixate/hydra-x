// Graph Optimization spec §9 — Composed Views.
//
// The signature interaction: a user or agent asks a focused question and
// the graph reshapes to answer it.
//
// Four composition types (§9):
//   - path:       horizontal/vertical chain from A to B
//   - radial:     centered node with influenced children radiating
//   - tree:       descendants arranged as a clean tree
//   - comparison: two nodes side-by-side with their lineage
//
// This module takes the graph data + a composition spec and returns new
// positions for the relevant subset of nodes. Non-relevant nodes aren't
// removed from the data — the caller dims them (30% opacity per §9).

import type { GraphDataEdge, GraphDataNode } from "@/types";
import { computeLineage } from "./graph-lineage";

export type ComposedViewKind = "path" | "radial" | "tree" | "comparison";

export type ComposedViewSpec =
  | { kind: "path"; fromId: string; toId: string }
  | { kind: "radial"; centerId: string; maxDepth?: number }
  | { kind: "tree"; rootId: string; maxDepth?: number }
  | { kind: "comparison"; leftId: string; rightId: string };

export type ComposedView = {
  kind: ComposedViewKind;
  positions: Map<string, { x: number; y: number }>;
  relevantIds: Set<string>;
  dimmedIds: Set<string>;
};

const NODE_SPACING = { x: 320, y: 170 };

export function composeView(
  nodes: GraphDataNode[],
  edges: GraphDataEdge[],
  spec: ComposedViewSpec,
): ComposedView {
  switch (spec.kind) {
    case "path":
      return composePath(nodes, edges, spec.fromId, spec.toId);
    case "radial":
      return composeRadial(nodes, edges, spec.centerId, spec.maxDepth ?? 2);
    case "tree":
      return composeTree(nodes, edges, spec.rootId, spec.maxDepth ?? 4);
    case "comparison":
      return composeComparison(nodes, edges, spec.leftId, spec.rightId);
  }
}

// ---- Path ----------------------------------------------------------

function composePath(
  nodes: GraphDataNode[],
  edges: GraphDataEdge[],
  fromId: string,
  toId: string,
): ComposedView {
  const path = shortestPath(nodes, edges, fromId, toId);
  const positions = new Map<string, { x: number; y: number }>();

  if (path.length === 0) {
    // No path — fall back to two-node side-by-side
    positions.set(fromId, { x: -NODE_SPACING.x, y: 0 });
    positions.set(toId, { x: NODE_SPACING.x, y: 0 });
    return finalize(nodes, new Set([fromId, toId]), positions, "path");
  }

  path.forEach((id, i) => {
    positions.set(id, {
      x: i * NODE_SPACING.x - ((path.length - 1) * NODE_SPACING.x) / 2,
      y: 0,
    });
  });

  return finalize(nodes, new Set(path), positions, "path");
}

function shortestPath(
  nodes: GraphDataNode[],
  edges: GraphDataEdge[],
  fromId: string,
  toId: string,
): string[] {
  const known = new Set(nodes.map((n) => n.id));
  if (!known.has(fromId) || !known.has(toId)) return [];

  const adj = new Map<string, Set<string>>();
  for (const e of edges) {
    if (!known.has(e.source) || !known.has(e.target)) continue;
    if (!adj.has(e.source)) adj.set(e.source, new Set());
    adj.get(e.source)!.add(e.target);
    // Treat edges as bidirectional for path finding — the user is asking
    // "how does X relate to Y," not "is there a directed path."
    if (!adj.has(e.target)) adj.set(e.target, new Set());
    adj.get(e.target)!.add(e.source);
  }

  const prev = new Map<string, string>();
  const queue: string[] = [fromId];
  const seen = new Set<string>([fromId]);

  while (queue.length > 0) {
    const cur = queue.shift()!;
    if (cur === toId) break;
    for (const nb of adj.get(cur) ?? []) {
      if (seen.has(nb)) continue;
      seen.add(nb);
      prev.set(nb, cur);
      queue.push(nb);
    }
  }

  if (!prev.has(toId) && fromId !== toId) return [];

  const path: string[] = [toId];
  let cur = toId;
  while (cur !== fromId && prev.has(cur)) {
    cur = prev.get(cur)!;
    path.unshift(cur);
  }
  return path[0] === fromId ? path : [];
}

// ---- Radial --------------------------------------------------------

function composeRadial(
  nodes: GraphDataNode[],
  edges: GraphDataEdge[],
  centerId: string,
  maxDepth: number,
): ComposedView {
  const { descendants } = computeLineage(nodes, edges, centerId);

  const byDepth = new Map<number, string[]>();
  descendants.forEach((depth, id) => {
    if (depth > maxDepth) return;
    if (!byDepth.has(depth)) byDepth.set(depth, []);
    byDepth.get(depth)!.push(id);
  });

  const positions = new Map<string, { x: number; y: number }>();
  positions.set(centerId, { x: 0, y: 0 });

  const relevant = new Set<string>([centerId]);

  for (const [depth, ids] of byDepth.entries()) {
    const radius = depth * 220;
    const count = ids.length;
    ids.forEach((id, i) => {
      const angle = (2 * Math.PI * i) / count - Math.PI / 2;
      positions.set(id, {
        x: radius * Math.cos(angle),
        y: radius * Math.sin(angle),
      });
      relevant.add(id);
    });
  }

  return finalize(nodes, relevant, positions, "radial");
}

// ---- Tree ----------------------------------------------------------

function composeTree(
  nodes: GraphDataNode[],
  edges: GraphDataEdge[],
  rootId: string,
  maxDepth: number,
): ComposedView {
  const { descendants } = computeLineage(nodes, edges, rootId);

  const byDepth = new Map<number, string[]>();
  byDepth.set(0, [rootId]);
  descendants.forEach((depth, id) => {
    if (depth > maxDepth) return;
    if (!byDepth.has(depth)) byDepth.set(depth, []);
    byDepth.get(depth)!.push(id);
  });

  const positions = new Map<string, { x: number; y: number }>();
  const relevant = new Set<string>();

  for (const [depth, ids] of byDepth.entries()) {
    const totalWidth = (ids.length - 1) * NODE_SPACING.x;
    ids.forEach((id, i) => {
      positions.set(id, {
        x: i * NODE_SPACING.x - totalWidth / 2,
        y: depth * NODE_SPACING.y,
      });
      relevant.add(id);
    });
  }

  return finalize(nodes, relevant, positions, "tree");
}

// ---- Comparison ----------------------------------------------------

function composeComparison(
  nodes: GraphDataNode[],
  edges: GraphDataEdge[],
  leftId: string,
  rightId: string,
): ComposedView {
  const left = computeLineage(nodes, edges, leftId);
  const right = computeLineage(nodes, edges, rightId);

  const positions = new Map<string, { x: number; y: number }>();
  const relevant = new Set<string>();
  const columnOffset = NODE_SPACING.x * 2.5;

  function place(
    chainIds: Set<string>,
    ancestors: Map<string, number>,
    descendants: Map<string, number>,
    centerId: string,
    xOffset: number,
  ) {
    positions.set(centerId, { x: xOffset, y: 0 });
    relevant.add(centerId);

    const above = Array.from(ancestors.entries()).reduce(
      (m, [id, d]) => {
        if (!m.has(d)) m.set(d, []);
        m.get(d)!.push(id);
        return m;
      },
      new Map<number, string[]>(),
    );

    above.forEach((ids, d) => {
      const totalWidth = (ids.length - 1) * NODE_SPACING.x;
      ids.forEach((id, i) => {
        positions.set(id, {
          x: xOffset + i * NODE_SPACING.x - totalWidth / 2,
          y: -d * NODE_SPACING.y,
        });
        relevant.add(id);
      });
    });

    const below = Array.from(descendants.entries()).reduce(
      (m, [id, d]) => {
        if (!m.has(d)) m.set(d, []);
        m.get(d)!.push(id);
        return m;
      },
      new Map<number, string[]>(),
    );

    below.forEach((ids, d) => {
      const totalWidth = (ids.length - 1) * NODE_SPACING.x;
      ids.forEach((id, i) => {
        positions.set(id, {
          x: xOffset + i * NODE_SPACING.x - totalWidth / 2,
          y: d * NODE_SPACING.y,
        });
        relevant.add(id);
      });
    });

    chainIds.forEach((id) => relevant.add(id));
  }

  place(left.chainIds, left.ancestors, left.descendants, leftId, -columnOffset / 2);
  place(right.chainIds, right.ancestors, right.descendants, rightId, columnOffset / 2);

  return finalize(nodes, relevant, positions, "comparison");
}

// ---- Helpers -------------------------------------------------------

function finalize(
  nodes: GraphDataNode[],
  relevant: Set<string>,
  positions: Map<string, { x: number; y: number }>,
  kind: ComposedViewKind,
): ComposedView {
  const dimmed = new Set<string>();
  for (const n of nodes) if (!relevant.has(n.id)) dimmed.add(n.id);
  return { kind, positions, relevantIds: relevant, dimmedIds: dimmed };
}
