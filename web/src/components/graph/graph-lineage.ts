// Graph Optimization spec §8 — Lineage View mode.
//
// Given a target node, compute a clean vertical chain of ancestors above
// and descendants below. This is a *simplified* view: only the chain is
// rendered sharply; off-chain nodes are kept as atmospheric background.
//
// Implementation is pure — takes nodes + edges and returns which ids are
// in the ancestor, descendant, and target sets, plus per-node depth so
// the caller can position them vertically.

import type { GraphDataEdge, GraphDataNode } from "@/types";

export type LineageResult = {
  targetId: string;
  ancestors: Map<string, number>; // id → depth (1 = parent, 2 = grandparent, …)
  descendants: Map<string, number>;
  chainIds: Set<string>;
};

const MAX_DEPTH = 10;

export function computeLineage(
  nodes: GraphDataNode[],
  edges: GraphDataEdge[],
  targetId: string,
): LineageResult {
  const incoming = new Map<string, string[]>();
  const outgoing = new Map<string, string[]>();

  const known = new Set(nodes.map((n) => n.id));

  for (const e of edges) {
    if (!known.has(e.source) || !known.has(e.target)) continue;
    if (!incoming.has(e.target)) incoming.set(e.target, []);
    incoming.get(e.target)!.push(e.source);
    if (!outgoing.has(e.source)) outgoing.set(e.source, []);
    outgoing.get(e.source)!.push(e.target);
  }

  const ancestors = bfs(targetId, incoming);
  const descendants = bfs(targetId, outgoing);

  const chainIds = new Set<string>([targetId]);
  ancestors.forEach((_d, id) => chainIds.add(id));
  descendants.forEach((_d, id) => chainIds.add(id));

  return { targetId, ancestors, descendants, chainIds };
}

function bfs(start: string, adj: Map<string, string[]>): Map<string, number> {
  const result = new Map<string, number>();
  const queue: Array<{ id: string; depth: number }> = [];

  for (const nb of adj.get(start) ?? []) {
    queue.push({ id: nb, depth: 1 });
  }

  while (queue.length > 0) {
    const { id, depth } = queue.shift()!;
    if (result.has(id)) continue;
    if (depth > MAX_DEPTH) continue;
    result.set(id, depth);
    for (const nb of adj.get(id) ?? []) {
      if (!result.has(nb) && nb !== start) {
        queue.push({ id: nb, depth: depth + 1 });
      }
    }
  }

  return result;
}

// Arrange chain vertically: target stays at the given anchor, ancestors
// above at negative y (by depth), descendants below at positive y. Returns
// a map of id → { x, y } for all chain nodes. Siblings at the same depth
// spread horizontally around the anchor x.
export function layoutLineageChainFromAnchor(
  lineage: LineageResult,
  anchor: { x: number; y: number },
  nodeSpacing = { x: 320, y: 170 },
): Map<string, { x: number; y: number }> {
  const positions = new Map<string, { x: number; y: number }>();
  positions.set(lineage.targetId, { x: anchor.x, y: anchor.y });

  // Group by depth
  const byDepth = new Map<number, string[]>();
  lineage.ancestors.forEach((depth, id) => {
    if (!byDepth.has(-depth)) byDepth.set(-depth, []);
    byDepth.get(-depth)!.push(id);
  });
  lineage.descendants.forEach((depth, id) => {
    if (!byDepth.has(depth)) byDepth.set(depth, []);
    byDepth.get(depth)!.push(id);
  });

  for (const [depth, ids] of byDepth.entries()) {
    const count = ids.length;
    const totalWidth = (count - 1) * nodeSpacing.x;
    ids.forEach((id, i) => {
      positions.set(id, {
        x: anchor.x + i * nodeSpacing.x - totalWidth / 2,
        y: anchor.y + depth * nodeSpacing.y,
      });
    });
  }

  return positions;
}

// Backwards-compatible wrapper: anchor at origin.
export function layoutLineageChain(
  lineage: LineageResult,
  nodeSpacing = { x: 320, y: 170 },
): Map<string, { x: number; y: number }> {
  return layoutLineageChainFromAnchor(lineage, { x: 0, y: 0 }, nodeSpacing);
}
