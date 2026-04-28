import { PointShape } from "@cosmos.gl/graph";

import type { GraphData, GraphDataEdge, GraphDataNode } from "@/types";

import { FAMILY_COLORS, NODE_COLORS, STATE_TONES, familyFor } from "./graph-constants";

export type GraphAltitude = "overview" | "neighbourhood" | "document";

export type CosmosGraphModel = {
  nodes: GraphDataNode[];
  edges: GraphDataEdge[];
  nodeIndexById: Map<string, number>;
  nodeIdByIndex: string[];
  edgeIndexById: Map<number, number>;
  pointPositions: Float32Array;
  pointColors: Float32Array;
  pointSizes: Float32Array;
  pointShapes: Float32Array;
  links: Float32Array;
  linkColors: Float32Array;
  linkWidths: Float32Array;
  linkArrows: boolean[];
  // Indices of nodes that should render the dense-evidence outline ring.
  // Cosmograph supports a single outline color globally — we use it as a
  // density signal (≥3 source refs reads as "thick evidence" per spec).
  denseRingIndices: number[];
};

// Density signal threshold for the outline ring (Constellation spec §1.1
// "thick evidence" = ≥3 sources or ≥10 connections in the local cluster).
const DENSE_RING_SOURCE_THRESHOLD = 3;

export function altitudeForZoom(zoom: number): GraphAltitude {
  if (zoom >= 1.25) return "document";
  if (zoom >= 0.42) return "neighbourhood";
  return "overview";
}

export function buildCosmosGraphModel(
  graphData: GraphData,
  visibleTypes: Set<string>,
  highlightedIds: Set<string>,
): CosmosGraphModel {
  const nodes = graphData.nodes.filter((node) => visibleTypes.has(node.node_type));
  const nodeIds = new Set(nodes.map((node) => node.id));
  const edges = graphData.edges.filter(
    (edge) => nodeIds.has(edge.source) && nodeIds.has(edge.target),
  );
  const nodeIndexById = new Map<string, number>();
  const nodeIdByIndex: string[] = [];

  nodes.forEach((node, index) => {
    nodeIndexById.set(node.id, index);
    nodeIdByIndex[index] = node.id;
  });

  const pointPositions = new Float32Array(nodes.length * 2);
  const pointColors = new Float32Array(nodes.length * 4);
  const pointSizes = new Float32Array(nodes.length);
  const pointShapes = new Float32Array(nodes.length);
  const denseRingIndices: number[] = [];

  nodes.forEach((node, index) => {
    const [x, y] = initialPosition(node, index, nodes.length);
    pointPositions[index * 2] = x;
    pointPositions[index * 2 + 1] = y;

    // Always render at full identity color. Highlighting/dimming is
    // applied by Cosmograph itself via `highlightedPointIndices` +
    // `pointGreyoutColor` / `pointGreyoutOpacity` — pushing dim alpha
    // into the buffer would double-encode the dim and force a data
    // rebuild every time the user hovered.
    pointColors.set(hexToRgba(colorForNode(node), alphaForNode(node)), index * 4);
    pointSizes[index] = densitySize(node);
    pointShapes[index] = shapeForNode(node);

    if ((node.source_reference_count ?? 0) >= DENSE_RING_SOURCE_THRESHOLD) {
      denseRingIndices.push(index);
    }
  });

  const links = new Float32Array(edges.length * 2);
  const linkColors = new Float32Array(edges.length * 4);
  const linkWidths = new Float32Array(edges.length);
  const linkArrows: boolean[] = [];
  const edgeIndexById = new Map<number, number>();

  edges.forEach((edge, index) => {
    const sourceIndex = nodeIndexById.get(edge.source) ?? 0;
    const targetIndex = nodeIndexById.get(edge.target) ?? 0;
    links[index * 2] = sourceIndex;
    links[index * 2 + 1] = targetIndex;
    edgeIndexById.set(edge.id, index);

    const color = colorForEdge(edge);
    const isContradicts = edge.kind === "contradicts";
    // Idle hairline alpha. Cosmograph's `linkGreyoutOpacity` handles
    // dimming when a highlight set is active; we don't bake it in.
    linkColors.set(hexToRgba(color, isContradicts ? 0.85 : 0.32), index * 4);
    linkWidths[index] = isContradicts ? 1.1 : 0.5;
    linkArrows[index] = edge.kind === "lineage" || edge.kind === "dependency";
  });

  return {
    nodes,
    edges,
    nodeIndexById,
    nodeIdByIndex,
    edgeIndexById,
    pointPositions,
    pointColors,
    pointSizes,
    pointShapes,
    links,
    linkColors,
    linkWidths,
    linkArrows,
    denseRingIndices,
  };
}

export function colorForNode(node: Pick<GraphDataNode, "node_type" | "source_reference_count">): string {
  // Calm family palette per the design proposal — fill encodes identity
  // (which family the node belongs to), the global outline ring encodes
  // density (≥3 source refs lights up). No more saturated overrides per
  // type. Library entities get their dedicated tokens since they don't
  // map cleanly to the project graph's five families.
  switch (node.node_type) {
    case "constraint":
      return STATE_TONES.tension;
    case "topic":
      return NODE_COLORS.topic ?? "#7c5cd1";
    case "author":
      return NODE_COLORS.author ?? "#0e8a6c";
    case "publication":
      return NODE_COLORS.publication ?? "#7e6a4f";
    case "excerpt":
      return NODE_COLORS.excerpt ?? "#a8b3c9";
    default:
      return FAMILY_COLORS[familyFor(node.node_type)];
  }
}

// Library spec §5.2 — visual hierarchy. Topic > source > author/publication;
// authors render as triangles, publications as squares, excerpts as small
// diamonds; everything else stays circular.
function shapeForNode(node: Pick<GraphDataNode, "node_type">): number {
  switch (node.node_type) {
    case "decision":
      return PointShape.Square;
    case "author":
      return PointShape.Triangle;
    case "publication":
      return PointShape.Square;
    case "excerpt":
      return PointShape.Diamond;
    default:
      return PointShape.Circle;
  }
}

export function densitySize(
  node: Pick<GraphDataNode, "source_reference_count" | "connection_count" | "node_type"> & {
    granularity?: string | null;
  },
): number {
  // Library spec §5.2 — topics are visual anchors, larger by default.
  // Granularity drives a multiplier: coarse > medium > fine.
  if (node.node_type === "topic") {
    const granularityBoost =
      node.granularity === "coarse" ? 10 : node.granularity === "fine" ? 4 : 7;
    const connectionWeight = Math.sqrt(Math.max(0, node.connection_count ?? 0)) * 1.6;
    return Math.max(8, Math.min(28, 6 + granularityBoost + connectionWeight));
  }

  // Authors and publications are smaller satellite markers — they're context,
  // not the primary signal.
  if (node.node_type === "author" || node.node_type === "publication") {
    const connectionWeight = Math.sqrt(Math.max(0, node.connection_count ?? 0)) * 1.0;
    return Math.max(4, Math.min(12, 4 + connectionWeight));
  }

  if (node.node_type === "excerpt") {
    return 5;
  }

  const sourceCount = node.source_reference_count ?? 0;
  const connectionWeight = Math.sqrt(Math.max(0, node.connection_count ?? 0)) * 1.25;
  const evidenceWeight = Math.log2(sourceCount + 1) * 3.25;
  const typeBoost = node.node_type === "source" || node.node_type === "source_ref" ? -1 : 0;
  return Math.max(4, Math.min(24, 5 + evidenceWeight + connectionWeight + typeBoost));
}

export function colorForEdge(edge: Pick<GraphDataEdge, "kind">): string {
  // Calm hairline palette — the edges should whisper. Only contradictions
  // and questions carry an attention-grabbing hue.
  switch (edge.kind) {
    case "contradicts":
      return STATE_TONES.tension;
    case "questions":
      return "#d97706";
    default:
      return "#94a3b8"; // slate-400 — neutral hairline for all structural edges
  }
}

function alphaForNode(node: GraphDataNode): number {
  // Evidence density is already encoded by `colorForNode` (DENSE_PURPLE
  // → MID_PURPLE → THIN_PURPLE). Layering alpha on top double-encodes
  // the same axis and just makes most nodes washed out (~54% opacity)
  // because most graphs have few source references per node.
  // Keep WIP slightly translucent — that's a visual cue for proposed /
  // forming state, not for evidence density.
  if (node.wip) return 0.7;
  return 1.0;
}

function initialPosition(node: GraphDataNode, index: number, total: number): [number, number] {
  const angle = index * 2.399963229728653;
  const density = Math.max(1, node.connection_count + (node.source_reference_count ?? 0));
  const ring = 120 + Math.sqrt(index + 1) * 42 + (total > 80 ? 80 : 0);
  const pull = Math.max(0.62, 1.25 - Math.log2(density + 1) * 0.08);
  return [Math.cos(angle) * ring * pull, Math.sin(angle) * ring * pull];
}

function hexToRgba(hex: string, alpha = 1): [number, number, number, number] {
  const normalized = hex.replace("#", "");
  const value =
    normalized.length === 3
      ? normalized
          .split("")
          .map((char) => char + char)
          .join("")
      : normalized;
  const int = Number.parseInt(value, 16);
  return [
    ((int >> 16) & 255) / 255,
    ((int >> 8) & 255) / 255,
    (int & 255) / 255,
    alpha,
  ];
}
