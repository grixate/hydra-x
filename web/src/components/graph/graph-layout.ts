import ELK, { type ElkNode } from "elkjs/lib/elk-api";
import elkWorkerUrl from "elkjs/lib/elk-worker.min.js?url";
import type { Node, Edge } from "@xyflow/react";
import type { GraphDataNode, GraphDataEdge } from "@/types";
import {
  NODE_COLORS,
  STATUS_COLORS,
  statusGroupKey,
  prettyLabel,
} from "./graph-constants";

const elk = new ELK({
  workerFactory: () => new Worker(elkWorkerUrl),
});

export type LayoutMode = "structured" | "group-type" | "group-status";

export type LayoutResult = {
  nodes: Node[];
  edges: Edge[];
  groupNodes: Node[];
  summaryNodes: Node[];
};

export type ComputeLayoutInput = {
  graphNodes: GraphDataNode[];
  graphEdges: GraphDataEdge[];
  mode: LayoutMode;
  expandedGroups: string[];
  edgeFadeThreshold: number;
};

const NODE_WIDTH = 280;
const NODE_HEIGHT = 160;
const SUMMARY_WIDTH = 320;
const SUMMARY_HEIGHT = 150;
const GROUP_PADDING_TOP = 44;
const GROUP_PADDING = 20;

const structuredLayoutOptions: Record<string, string> = {
  "elk.algorithm": "layered",
  "elk.direction": "DOWN",
  "elk.spacing.nodeNode": "40",
  "elk.spacing.edgeNode": "20",
  "elk.layered.spacing.nodeNodeBetweenLayers": "90",
  "elk.layered.crossingMinimization.strategy": "LAYER_SWEEP",
  "elk.layered.nodePlacement.strategy": "NETWORK_SIMPLEX",
  "elk.edgeRouting": "SPLINES",
  "elk.separateConnectedComponents": "true",
  "elk.spacing.componentComponent": "80",
  "elk.padding": "[top=40,left=40,bottom=40,right=40]",
};

export async function computeLayout(input: ComputeLayoutInput): Promise<LayoutResult> {
  const { graphNodes, graphEdges, mode, expandedGroups, edgeFadeThreshold } = input;
  const nodeIds = new Set(graphNodes.map((n) => n.id));
  const visibleEdges = graphEdges.filter(
    (e) => nodeIds.has(e.source) && nodeIds.has(e.target),
  );

  if (mode === "structured") {
    return computeStructuredLayout(graphNodes, visibleEdges, edgeFadeThreshold);
  }
  return computeGroupedLayout(
    graphNodes,
    visibleEdges,
    mode,
    new Set(expandedGroups),
    edgeFadeThreshold,
  );
}

async function computeStructuredLayout(
  graphNodes: GraphDataNode[],
  visibleEdges: GraphDataEdge[],
  edgeFadeThreshold: number,
): Promise<LayoutResult> {
  const elkGraph: ElkNode = {
    id: "root",
    layoutOptions: structuredLayoutOptions,
    children: graphNodes.map((node) => ({
      id: node.id,
      width: NODE_WIDTH,
      height: NODE_HEIGHT,
    })),
    edges: visibleEdges.map((e) => ({
      id: String(e.id),
      sources: [e.source],
      targets: [e.target],
    })),
  };

  const result = await elk.layout(elkGraph);

  const nodes: Node[] = (result.children ?? []).map((elkNode) => {
    const original = graphNodes.find((n) => n.id === elkNode.id)!;
    return makeDataNode(original, elkNode.x ?? 0, elkNode.y ?? 0);
  });

  const faded = visibleEdges.length > edgeFadeThreshold;
  return {
    nodes,
    edges: makeEdges(visibleEdges, faded),
    groupNodes: [],
    summaryNodes: [],
  };
}

type GroupDef = { key: string; label: string; color: string };

function groupOf(node: GraphDataNode, mode: "group-type" | "group-status"): GroupDef {
  if (mode === "group-type") {
    return {
      key: node.node_type,
      label: prettyLabel(node.node_type),
      color: NODE_COLORS[node.node_type] ?? NODE_COLORS.default,
    };
  }
  const key = statusGroupKey(node.status);
  return {
    key,
    label: prettyLabel(key),
    color: STATUS_COLORS[key] ?? STATUS_COLORS.default,
  };
}

type Bucket = { def: GroupDef; nodes: GraphDataNode[]; groupId: string; summaryId: string };

function summarizeBucket(bucket: Bucket) {
  const statusBreakdown: Record<string, number> = {};
  let topNode: GraphDataNode | null = null;
  let lastUpdated = "";
  for (const n of bucket.nodes) {
    const key = statusGroupKey(n.status);
    statusBreakdown[key] = (statusBreakdown[key] ?? 0) + 1;
    if (!topNode || n.connection_count > topNode.connection_count) topNode = n;
    if (n.updated_at && n.updated_at > lastUpdated) lastUpdated = n.updated_at;
  }
  return {
    statusBreakdown,
    topTitle: topNode?.title ?? null,
    topConnections: topNode?.connection_count ?? 0,
    lastUpdated,
  };
}

async function computeGroupedLayout(
  graphNodes: GraphDataNode[],
  visibleEdges: GraphDataEdge[],
  mode: "group-type" | "group-status",
  expandedGroups: Set<string>,
  edgeFadeThreshold: number,
): Promise<LayoutResult> {
  const buckets = new Map<string, Bucket>();
  for (const node of graphNodes) {
    const def = groupOf(node, mode);
    if (!buckets.has(def.key)) {
      buckets.set(def.key, {
        def,
        nodes: [],
        groupId: `group-${mode}-${def.key}`,
        summaryId: `summary-${mode}-${def.key}`,
      });
    }
    buckets.get(def.key)!.nodes.push(node);
  }

  const nodeToBucket = new Map<string, Bucket>();
  for (const bucket of buckets.values()) {
    for (const n of bucket.nodes) nodeToBucket.set(n.id, bucket);
  }

  const isExpanded = (b: Bucket) => expandedGroups.has(b.def.key);

  const elkChildren: ElkNode[] = Array.from(buckets.values()).map((bucket): ElkNode => {
    if (isExpanded(bucket)) {
      const opts: Record<string, string> = {
        "elk.algorithm": "rectpacking",
        "elk.spacing.nodeNode": "28",
        "elk.padding": `[top=${GROUP_PADDING_TOP},left=${GROUP_PADDING},bottom=${GROUP_PADDING},right=${GROUP_PADDING}]`,
        "elk.rectpacking.targetWidth": String(NODE_WIDTH * 2 + 80),
        "elk.aspectRatio": "1.6",
      };
      return {
        id: bucket.groupId,
        layoutOptions: opts,
        children: bucket.nodes.map((node) => ({
          id: node.id,
          width: NODE_WIDTH,
          height: NODE_HEIGHT,
        })),
      };
    }
    const collapsedOpts: Record<string, string> = {
      "elk.algorithm": "rectpacking",
      "elk.spacing.nodeNode": "0",
      "elk.padding": `[top=${GROUP_PADDING_TOP},left=${GROUP_PADDING},bottom=${GROUP_PADDING},right=${GROUP_PADDING}]`,
    };
    return {
      id: bucket.groupId,
      layoutOptions: collapsedOpts,
      children: [
        {
          id: bucket.summaryId,
          width: SUMMARY_WIDTH,
          height: SUMMARY_HEIGHT,
        },
      ],
    };
  });

  const groupEdgeSet = new Set<string>();
  const groupEdges: { id: string; sources: string[]; targets: string[] }[] = [];
  visibleEdges.forEach((e, idx) => {
    const sBucket = nodeToBucket.get(e.source);
    const tBucket = nodeToBucket.get(e.target);
    if (!sBucket || !tBucket || sBucket === tBucket) return;
    const key = `${sBucket.groupId}->${tBucket.groupId}`;
    if (groupEdgeSet.has(key)) return;
    groupEdgeSet.add(key);
    groupEdges.push({
      id: `ge-${idx}-${key}`,
      sources: [sBucket.groupId],
      targets: [tBucket.groupId],
    });
  });

  const elkGraph: ElkNode = {
    id: "root",
    layoutOptions: {
      "elk.algorithm": "layered",
      "elk.direction": "DOWN",
      "elk.spacing.nodeNode": "60",
      "elk.layered.spacing.nodeNodeBetweenLayers": "100",
      "elk.spacing.componentComponent": "80",
      "elk.separateConnectedComponents": "true",
      "elk.padding": "[top=40,left=40,bottom=40,right=40]",
    },
    children: elkChildren,
    edges: groupEdges,
  };

  const result = await elk.layout(elkGraph);

  const dataNodes: Node[] = [];
  const groupNodes: Node[] = [];
  const summaryNodes: Node[] = [];

  (result.children ?? []).forEach((elkGroup) => {
    const groupX = elkGroup.x ?? 0;
    const groupY = elkGroup.y ?? 0;
    const width = elkGroup.width ?? 300;
    const height = elkGroup.height ?? 200;
    const bucket = Array.from(buckets.values()).find((b) => b.groupId === elkGroup.id);
    if (!bucket) return;

    groupNodes.push({
      id: bucket.groupId,
      type: "groupNode",
      position: { x: groupX, y: groupY },
      data: {
        label: bucket.def.label,
        color: bucket.def.color,
        count: bucket.nodes.length,
      },
      style: { width, height },
      draggable: false,
      selectable: false,
      zIndex: -1,
    });

    if (isExpanded(bucket)) {
      (elkGroup.children ?? []).forEach((child) => {
        const original = bucket.nodes.find((n) => n.id === child.id);
        if (!original) return;
        dataNodes.push(
          makeDataNode(original, groupX + (child.x ?? 0), groupY + (child.y ?? 0)),
        );
      });
    } else {
      const child = (elkGroup.children ?? [])[0];
      const sx = groupX + (child?.x ?? GROUP_PADDING);
      const sy = groupY + (child?.y ?? GROUP_PADDING_TOP);
      const summary = summarizeBucket(bucket);
      summaryNodes.push({
        id: bucket.summaryId,
        type: "summaryNode",
        position: { x: sx, y: sy },
        data: {
          groupKey: bucket.def.key,
          label: bucket.def.label,
          color: bucket.def.color,
          count: bucket.nodes.length,
          ...summary,
        },
        style: { width: SUMMARY_WIDTH, height: SUMMARY_HEIGHT },
      });
    }
  });

  const remapped = new Map<string, Edge>();
  visibleEdges.forEach((e) => {
    const sBucket = nodeToBucket.get(e.source);
    const tBucket = nodeToBucket.get(e.target);
    if (!sBucket || !tBucket) return;
    const sId = isExpanded(sBucket) ? e.source : sBucket.summaryId;
    const tId = isExpanded(tBucket) ? e.target : tBucket.summaryId;
    if (sId === tId) return;
    const key = `${sId}->${tId}`;
    if (remapped.has(key)) return;
    remapped.set(key, {
      id: sId === e.source && tId === e.target ? String(e.id) : `synth-${key}`,
      source: sId,
      target: tId,
      type: "graphEdge",
      data: { kind: e.kind, weight: e.weight },
    });
  });

  const edges = Array.from(remapped.values());
  const faded = edges.length > edgeFadeThreshold;
  if (faded) {
    edges.forEach((edge) => {
      edge.data = { ...(edge.data as object), faded: true };
    });
  }

  return { nodes: dataNodes, edges, groupNodes, summaryNodes };
}

function makeDataNode(original: GraphDataNode, x: number, y: number): Node {
  return {
    id: original.id,
    position: { x, y },
    data: {
      ...original,
      color: NODE_COLORS[original.node_type] ?? NODE_COLORS.default,
      wip: original.wip ?? false,
    },
    type: "graphNode",
    style: { width: NODE_WIDTH, height: NODE_HEIGHT },
  };
}

// Graph-Opt §4 O3: edge bundling — collapse duplicate edges between the
// same node pair into a single visual edge with multiplicity.
function bundleEdges(edges: GraphDataEdge[]): Array<GraphDataEdge & { bundleCount: number }> {
  const map = new Map<string, { edge: GraphDataEdge; count: number }>();
  for (const e of edges) {
    const key = `${e.source}->${e.target}:${e.kind}`;
    const existing = map.get(key);
    if (existing) {
      existing.count += 1;
    } else {
      map.set(key, { edge: e, count: 1 });
    }
  }
  return Array.from(map.values()).map(({ edge, count }) => ({
    ...edge,
    bundleCount: count,
  }));
}

function makeEdges(visibleEdges: GraphDataEdge[], faded: boolean): Edge[] {
  const bundled = bundleEdges(visibleEdges);
  return bundled.map((e) => ({
    id: String(e.id),
    source: e.source,
    target: e.target,
    type: "graphEdge",
    data: {
      kind: e.kind,
      weight: e.weight,
      faded,
      bundleCount: e.bundleCount > 1 ? e.bundleCount : undefined,
    },
  }));
}
