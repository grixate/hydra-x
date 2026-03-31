import ELK, { type ElkNode } from "elkjs/lib/elk.bundled.js";
import type { Node, Edge } from "@xyflow/react";
import type { GraphDataNode, GraphDataEdge } from "@/types";
import { NODE_COLORS, LAYER_ORDER } from "./graph-constants";

const elk = new ELK();

export async function computeLayout(
  graphNodes: GraphDataNode[],
  graphEdges: GraphDataEdge[],
  options?: { direction?: "DOWN" | "RIGHT" },
): Promise<{ nodes: Node[]; edges: Edge[] }> {
  const direction = options?.direction ?? "DOWN";
  const nodeIds = new Set(graphNodes.map((n) => n.id));

  const elkGraph: ElkNode = {
    id: "root",
    layoutOptions: {
      "elk.algorithm": "layered",
      "elk.direction": direction,
      // Tighter horizontal, more vertical space
      "elk.spacing.nodeNode": "30",
      "elk.layered.spacing.nodeNodeBetweenLayers": "140",
      // Smooth curved edges
      "elk.layered.edgeRouting": "SPLINES",
      // Favor long straight edges, reduce zigzag
      "elk.layered.nodePlacement.strategy": "NETWORK_SIMPLEX",
      "elk.layered.crossingMinimization.strategy": "LAYER_SWEEP",
      "elk.layered.layering.strategy": "LONGEST_PATH",
      "elk.padding": "[top=40,left=40,bottom=40,right=40]",
      "elk.separateConnectedComponents": "true",
      "elk.spacing.componentComponent": "80",
      "elk.partitioning.activate": "true",
      // Prefer taller, narrower layout
      "elk.aspectRatio": "0.5",
    },
    children: graphNodes.map((node) => ({
      id: node.id,
      width: nodeWidth(),
      height: nodeHeight(),
      layoutOptions: {
        "elk.partitioning.partition": String(
          LAYER_ORDER[node.node_type] ?? 4,
        ),
      },
    })),
    edges: graphEdges
      .filter((e) => nodeIds.has(e.source) && nodeIds.has(e.target))
      .map((e) => ({
        id: String(e.id),
        sources: [e.source],
        targets: [e.target],
      })),
  };

  const layoutResult = await elk.layout(elkGraph);

  const nodes: Node[] = (layoutResult.children ?? []).map((elkNode) => {
    const original = graphNodes.find((n) => n.id === elkNode.id)!;
    return {
      id: elkNode.id,
      position: { x: elkNode.x ?? 0, y: elkNode.y ?? 0 },
      data: {
        ...original,
        color: NODE_COLORS[original.node_type] ?? NODE_COLORS.default,
      },
      type: "graphNode",
      style: {
        width: nodeWidth(),
        height: nodeHeight(),
      },
    };
  });

  const edges: Edge[] = graphEdges
    .filter((e) => nodeIds.has(e.source) && nodeIds.has(e.target))
    .map((e) => ({
      id: String(e.id),
      source: e.source,
      target: e.target,
      type: "graphEdge",
      data: { kind: e.kind, weight: e.weight },
    }));

  return { nodes, edges };
}

function nodeWidth(): number {
  return 280;
}

function nodeHeight(): number {
  return 110;
}
