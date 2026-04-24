import { PointShape } from "@cosmos.gl/graph";

import type { GraphData, GraphDataEdge, GraphDataNode } from "@/types";

import { NODE_COLORS, STATE_TONES } from "./graph-constants";

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
};

const DENSE_PURPLE = "#534AB7";
const MID_PURPLE = "#7F77DD";
const THIN_PURPLE = "#CECBF6";
const TEAL = "#1D9E75";
const PINK = "#D946EF";
const DECISION = "#334155";

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
  const dimUnhighlighted = highlightedIds.size > 0;

  nodes.forEach((node, index) => {
    const [x, y] = initialPosition(node, index, nodes.length);
    pointPositions[index * 2] = x;
    pointPositions[index * 2 + 1] = y;

    const color = colorForNode(node);
    const rgba = hexToRgba(color, dimUnhighlighted && !highlightedIds.has(node.id) ? 0.22 : alphaForNode(node));
    pointColors.set(rgba, index * 4);
    pointSizes[index] = densitySize(node);
    pointShapes[index] = node.node_type === "decision" ? PointShape.Square : PointShape.Circle;
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
    const isDimmed =
      highlightedIds.size > 0 &&
      !highlightedIds.has(edge.source) &&
      !highlightedIds.has(edge.target);
    linkColors.set(hexToRgba(color, isDimmed ? 0.08 : edge.kind === "contradicts" ? 0.82 : 0.34), index * 4);
    linkWidths[index] = edge.kind === "contradicts" ? 1.05 : 0.65;
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
  };
}

export function colorForNode(node: Pick<GraphDataNode, "node_type" | "source_reference_count">): string {
  switch (node.node_type) {
    case "insight":
    case "requirement":
      return densityColor(node.source_reference_count ?? 0);
    case "source":
    case "source_ref":
    case "signal":
      return TEAL;
    case "decision":
      return DECISION;
    case "strategy":
      return "#0f5a7a";
    case "constraint":
      return STATE_TONES.tension;
    case "learning":
    case "outcome":
      return "#9a5d2a";
    case "design_node":
    case "architecture_node":
    case "task":
      return "#3f4a5c";
    default:
      return NODE_COLORS[node.node_type] ?? densityColor(node.source_reference_count ?? 0);
  }
}

export function densityColor(sourceCount: number): string {
  if (sourceCount >= 10) return DENSE_PURPLE;
  if (sourceCount >= 3) return MID_PURPLE;
  return THIN_PURPLE;
}

export function densitySize(node: Pick<GraphDataNode, "source_reference_count" | "connection_count" | "node_type">): number {
  const sourceCount = node.source_reference_count ?? 0;
  const connectionWeight = Math.sqrt(Math.max(0, node.connection_count ?? 0)) * 1.25;
  const evidenceWeight = Math.log2(sourceCount + 1) * 3.25;
  const typeBoost = node.node_type === "source" || node.node_type === "source_ref" ? -1 : 0;
  return Math.max(4, Math.min(24, 5 + evidenceWeight + connectionWeight + typeBoost));
}

export function colorForEdge(edge: Pick<GraphDataEdge, "kind">): string {
  switch (edge.kind) {
    case "contradicts":
      return STATE_TONES.tension;
    case "lineage":
    case "derived_from":
      return TEAL;
    case "questions":
      return "#d97706";
    case "supports":
      return MID_PURPLE;
    case "dependency":
      return "#64748b";
    default:
      return "#AFA9EC";
  }
}

function alphaForNode(node: GraphDataNode): number {
  if (node.wip) return 0.62;
  if ((node.source_reference_count ?? 0) >= 10) return 0.92;
  if ((node.source_reference_count ?? 0) >= 3) return 0.78;
  return 0.54;
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
