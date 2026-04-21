import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import Sigma from "sigma";
import Graph from "graphology";
import { Loader2, LayoutGrid } from "lucide-react";

import { api } from "@/lib/api";
import type { GraphData, GraphDataNode } from "@/types";
import {
  computeLayout,
  type LayoutMode,
  type LayoutResult,
} from "./graph-layout";
import { NODE_COLORS, FILTERABLE_NODE_TYPES } from "./graph-constants";
import { GraphSmartViewSelector } from "./graph-smart-view-selector";
import { GraphFilterChips } from "./graph-filter-chips";
import { GraphSpotlight, SpotlightTrigger } from "./graph-spotlight";
import { GraphNodeDetail } from "./graph-node-detail";
import { WhyPanel } from "./why-panel";
import { Skeleton } from "@/components/ui/skeleton";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectSeparator,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { applySmartView, type SmartView } from "./graph-smart-views";
import { GroupOverlay, type SigmaGroup } from "./graph-sigma-groups";

const COLLAPSE_THRESHOLD = 200;
const EDGE_FADE_THRESHOLD = 200;
const NODE_BASE_SIZE = 6;
const NODE_MAX_SIZE = 16;

function nodeSize(connections: number) {
  return Math.min(NODE_MAX_SIZE, NODE_BASE_SIZE + Math.sqrt(Math.max(0, connections)) * 1.6);
}

export function GraphSigmaView({ projectId }: { projectId: number }) {
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const containerRef = useRef<HTMLDivElement>(null);
  const sigmaRef = useRef<Sigma | null>(null);
  const graphRef = useRef<Graph | null>(null);
  const overlayRef = useRef<GroupOverlay | null>(null);

  const [graphData, setGraphData] = useState<GraphData | null>(null);
  const [whyTarget, setWhyTarget] = useState<{ nodeType: string; nodeId: number } | null>(null);
  const [loading, setLoading] = useState(true);
  const [layouting, setLayouting] = useState(false);

  const [layoutMode, setLayoutMode] = useState<LayoutMode>("structured");
  const [visibleTypes, setVisibleTypes] = useState<Set<string>>(
    new Set(FILTERABLE_NODE_TYPES),
  );
  const [highlightedIds, setHighlightedIds] = useState<Set<string>>(new Set());
  const [activeSmartView, setActiveSmartView] = useState<SmartView | null>(null);
  const [spotlightOpen, setSpotlightOpen] = useState(false);

  const [selectedNodeId, setSelectedNodeId] = useState<string | null>(null);
  const [overlayPos, setOverlayPos] = useState<{ x: number; y: number } | null>(null);

  // ⌘K spotlight
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault();
        setSpotlightOpen((p) => !p);
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, []);

  // Mount sigma instance once
  useEffect(() => {
    if (!containerRef.current) return;
    const graph = new Graph({ multi: false, type: "directed" });
    graphRef.current = graph;
    const sigma = new Sigma(graph, containerRef.current, {
      renderEdgeLabels: false,
      enableEdgeEvents: false,
      labelDensity: 0.5,
      labelGridCellSize: 100,
      labelRenderedSizeThreshold: 8,
      defaultNodeColor: "#94a3b8",
      defaultEdgeColor: "#cbd5e1",
      labelColor: { color: "#1f2937" },
    });
    sigmaRef.current = sigma;
    overlayRef.current = new GroupOverlay(sigma, graph);

    const handleClick = ({ node }: { node: string }) => {
      setSelectedNodeId(node);
    };
    const handleStage = () => {
      setSelectedNodeId(null);
    };
    sigma.on("clickNode", handleClick);
    sigma.on("clickStage", handleStage);

    const updateOverlayPos = () => {
      if (!selectedNodeIdRef.current || !graphRef.current?.hasNode(selectedNodeIdRef.current)) {
        setOverlayPos(null);
        return;
      }
      const x = graphRef.current.getNodeAttribute(selectedNodeIdRef.current, "x") as number;
      const y = graphRef.current.getNodeAttribute(selectedNodeIdRef.current, "y") as number;
      const screen = sigma.graphToViewport({ x, y });
      setOverlayPos(screen);
    };
    sigma.on("afterRender", updateOverlayPos);

    return () => {
      sigma.off("clickNode", handleClick);
      sigma.off("clickStage", handleStage);
      sigma.off("afterRender", updateOverlayPos);
      overlayRef.current?.destroy();
      overlayRef.current = null;
      sigma.kill();
      sigmaRef.current = null;
      graphRef.current = null;
    };
  }, []);

  // Track selected node id in a ref so the afterRender callback can read latest value
  const selectedNodeIdRef = useRef<string | null>(null);
  useEffect(() => {
    selectedNodeIdRef.current = selectedNodeId;
    if (!selectedNodeId) {
      setOverlayPos(null);
      return;
    }
    const g = graphRef.current;
    const s = sigmaRef.current;
    if (!g || !s || !g.hasNode(selectedNodeId)) return;
    const x = g.getNodeAttribute(selectedNodeId, "x") as number;
    const y = g.getNodeAttribute(selectedNodeId, "y") as number;
    setOverlayPos(s.graphToViewport({ x, y }));
  }, [selectedNodeId]);

  // Fetch graph data
  const refreshGraphData = useCallback(async () => {
    const data = await api.getGraphData(projectId);
    setGraphData(data);
    return data;
  }, [projectId]);

  useEffect(() => {
    setLoading(true);
    refreshGraphData()
      .then((data) => {
        const defaultView: SmartView | null =
          data.nodes.length >= 10 ? "next_actions" : null;
        setActiveSmartView(defaultView);
        setHighlightedIds(
          defaultView ? applySmartView(defaultView, data) : new Set(),
        );
        setLoading(false);
      })
      .catch(() => setLoading(false));
  }, [projectId, refreshGraphData]);

  // Recompute layout & populate graphology when inputs change
  useEffect(() => {
    if (!graphData || !graphRef.current || !sigmaRef.current) return;
    let cancelled = false;
    setLayouting(true);

    const visibleNodes = graphData.nodes.filter((n) => visibleTypes.has(n.node_type));
    const visibleNodeIds = new Set(visibleNodes.map((n) => n.id));
    const visibleEdges = graphData.edges.filter(
      (e) => visibleNodeIds.has(e.source) && visibleNodeIds.has(e.target),
    );

    // Auto-collapse on grouped + large
    const expandedGroups: string[] =
      layoutMode === "structured" || visibleNodes.length <= COLLAPSE_THRESHOLD
        ? // expand all when small
          uniqueGroupKeys(visibleNodes, layoutMode)
        : [];

    computeLayout({
      graphNodes: visibleNodes,
      graphEdges: visibleEdges,
      mode: layoutMode,
      expandedGroups,
      edgeFadeThreshold: EDGE_FADE_THRESHOLD,
    })
      .then((result) => {
        if (cancelled) return;
        applyToGraphology(result, visibleNodes, highlightedIds);
        const groups = buildSigmaGroups(result, visibleNodes, layoutMode);
        overlayRef.current?.setGroups(groups);
        setLayouting(false);
      })
      .catch(() => setLayouting(false));

    return () => {
      cancelled = true;
    };
  }, [graphData, visibleTypes, layoutMode, highlightedIds]);

  function applyToGraphology(
    result: LayoutResult,
    visibleNodes: GraphDataNode[],
    highlighted: Set<string>,
  ) {
    const graph = graphRef.current;
    if (!graph) return;
    graph.clear();

    const positionById = new Map<string, { x: number; y: number }>();
    for (const n of result.nodes) {
      positionById.set(n.id, { x: n.position.x, y: -n.position.y });
    }

    const dimEnabled = highlighted.size > 0;
    for (const node of visibleNodes) {
      const pos = positionById.get(node.id);
      if (!pos) continue;
      const baseColor = NODE_COLORS[node.node_type] ?? NODE_COLORS.default;
      const dim = dimEnabled && !highlighted.has(node.id);
      const color = dim ? `${baseColor}33` : baseColor;
      graph.addNode(node.id, {
        x: pos.x,
        y: pos.y,
        size: nodeSize(node.connection_count),
        label: node.title,
        color,
        nodeType: node.node_type,
      });
    }

    const fade = result.edges.length > EDGE_FADE_THRESHOLD;
    for (const edge of result.edges) {
      if (!graph.hasNode(edge.source) || !graph.hasNode(edge.target)) continue;
      if (graph.hasEdge(edge.source, edge.target)) continue;
      graph.addEdgeWithKey(String(edge.id), edge.source, edge.target, {
        size: fade ? 0.3 : 1,
        color: fade ? "rgba(148,163,184,0.18)" : "rgba(148,163,184,0.55)",
      });
    }

    sigmaRef.current?.refresh();
  }

  // Filters
  const handleToggleType = useCallback((type: string) => {
    setVisibleTypes((prev) => {
      const next = new Set(prev);
      if (next.has(type)) next.delete(type);
      else next.add(type);
      return next;
    });
  }, []);

  // Smart view
  const handleSmartViewChange = useCallback(
    (view: SmartView | null) => {
      setActiveSmartView(view);
      if (!graphData) return;
      setHighlightedIds(view ? applySmartView(view, graphData) : new Set());
    },
    [graphData],
  );

  // Search
  const handleSearch = useCallback(
    (query: string) => {
      if (!graphData || !query.trim()) {
        if (activeSmartView && graphData) {
          setHighlightedIds(applySmartView(activeSmartView, graphData));
        } else {
          setHighlightedIds(new Set());
        }
        return;
      }
      const q = query.toLowerCase();
      setHighlightedIds(
        new Set(
          graphData.nodes
            .filter((n) => n.title.toLowerCase().includes(q))
            .map((n) => n.id),
        ),
      );
    },
    [graphData, activeSmartView],
  );

  const previewNode = useMemo(() => {
    if (!selectedNodeId || !graphData) return null;
    return graphData.nodes.find((n) => n.id === selectedNodeId) ?? null;
  }, [selectedNodeId, graphData]);

  const containerWidth = containerRef.current?.offsetWidth ?? 1200;
  const containerHeight = containerRef.current?.offsetHeight ?? 800;

  const switchToReactFlow = () => {
    const next = new URLSearchParams(searchParams);
    next.delete("engine");
    setSearchParams(next, { replace: true });
  };

  return (
    <div className="relative h-full w-full overflow-hidden">
      <div ref={containerRef} className="absolute inset-0" />

      {loading && (
        <div className="absolute inset-0 z-20 flex items-center justify-center bg-background/60">
          <Skeleton className="h-96 w-96 rounded-xl" />
        </div>
      )}

      {/* Smart views — top left */}
      <div className="absolute left-4 top-4 z-10">
        <GraphSmartViewSelector
          active={activeSmartView}
          onChange={handleSmartViewChange}
          nodeCount={graphData?.nodes.length ?? 0}
        />
      </div>

      {/* Toolbar — top right */}
      <div className="absolute right-4 top-4 z-10 flex items-center gap-1.5">
        <Select value={layoutMode} onValueChange={(v) => setLayoutMode(v as LayoutMode)}>
          <SelectTrigger className="h-7 w-[160px] text-xs">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="structured">Structured</SelectItem>
            <SelectSeparator />
            <SelectItem value="group-type">Grouped by type</SelectItem>
            <SelectItem value="group-status">Grouped by status</SelectItem>
          </SelectContent>
        </Select>
        {layouting && (
          <div className="flex items-center gap-1 rounded-md border bg-background/80 px-2 py-1 text-[11px] text-muted-foreground shadow-sm backdrop-blur">
            <Loader2 className="h-3 w-3 animate-spin" />
            <span>Laying out…</span>
          </div>
        )}
        <GraphFilterChips visibleTypes={visibleTypes} onToggle={handleToggleType} />
        <SpotlightTrigger onClick={() => setSpotlightOpen(true)} />
        <Button
          variant="outline"
          size="sm"
          className="h-7 gap-1 text-[11px]"
          onClick={switchToReactFlow}
          title="Switch to React Flow engine"
        >
          <LayoutGrid className="h-3 w-3" /> DOM
        </Button>
      </div>

      {/* Selected node detail overlay */}
      {previewNode && overlayPos && graphData && (
        <GraphNodeDetail
          node={previewNode}
          graphData={graphData}
          projectId={projectId}
          nodeScreenPosition={overlayPos}
          containerWidth={containerWidth}
          containerHeight={containerHeight}
          onClose={() => setSelectedNodeId(null)}
          onOpenTrail={(nodeType, nodeId) => {
            navigate(`/projects/${projectId}/trail/${nodeType}/${nodeId}`, {
              state: { from: "graph" },
            });
          }}
          onOpenWhy={(nodeType, nodeId) => setWhyTarget({ nodeType, nodeId })}
          onHighlightConnections={(nodeIds) => setHighlightedIds(new Set(nodeIds))}
          onChatAbout={() => {}}
          isInChatContext={false}
        />
      )}

      <WhyPanel
        open={whyTarget !== null}
        projectId={projectId}
        nodeType={whyTarget?.nodeType ?? null}
        nodeId={whyTarget?.nodeId ?? null}
        onClose={() => setWhyTarget(null)}
        onNavigateToNode={(nodeType, nodeId) => setWhyTarget({ nodeType, nodeId })}
      />

      {/* Spotlight */}
      <GraphSpotlight
        open={spotlightOpen}
        onClose={() => {
          setSpotlightOpen(false);
          handleSearch("");
        }}
        nodes={graphData?.nodes ?? []}
        onFocusNode={(nodeId) => {
          setSelectedNodeId(nodeId);
          setHighlightedIds(new Set([nodeId]));
          const g = graphRef.current;
          const s = sigmaRef.current;
          if (g && s && g.hasNode(nodeId)) {
            const x = g.getNodeAttribute(nodeId, "x") as number;
            const y = g.getNodeAttribute(nodeId, "y") as number;
            const camera = s.getCamera();
            camera.animate({ x, y, ratio: 0.5 }, { duration: 400 });
          }
        }}
        onSmartView={handleSmartViewChange}
        onFitToScreen={() => {
          const s = sigmaRef.current;
          if (s) s.getCamera().animatedReset();
        }}
        onSearch={handleSearch}
      />
    </div>
  );
}

function uniqueGroupKeys(nodes: GraphDataNode[], mode: LayoutMode): string[] {
  if (mode === "structured") return [];
  const keys = new Set<string>();
  for (const n of nodes) {
    if (mode === "group-type") keys.add(n.node_type);
    else keys.add(n.status || "other");
  }
  return Array.from(keys);
}

function buildSigmaGroups(
  result: LayoutResult,
  visibleNodes: GraphDataNode[],
  mode: LayoutMode,
): SigmaGroup[] {
  if (mode === "structured") return [];

  // Reuse the group containers from the layout result for label/color/key
  const buckets = new Map<string, SigmaGroup>();
  for (const node of visibleNodes) {
    const key = mode === "group-type" ? node.node_type : node.status || "other";
    if (!buckets.has(key)) {
      const groupNode = result.groupNodes.find((g) =>
        String(g.id).endsWith(`-${key}`),
      );
      const data = (groupNode?.data ?? {}) as { label?: string; color?: string };
      buckets.set(key, {
        key,
        label: data.label ?? key,
        color:
          data.color ?? NODE_COLORS[node.node_type] ?? NODE_COLORS.default,
        nodeKeys: [],
      });
    }
    buckets.get(key)!.nodeKeys.push(node.id);
  }
  return Array.from(buckets.values());
}
