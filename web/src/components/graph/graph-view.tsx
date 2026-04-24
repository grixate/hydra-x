import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { Graph } from "@cosmos.gl/graph";
import { GitBranch, Loader2, Orbit, Route, ShieldAlert } from "lucide-react";

import { api } from "@/lib/api";
import { subscribeToProject } from "@/lib/project-channel";
import type { GraphData, GraphDataNode, SourceReference } from "@/types";
import { GraphChatProvider, type GraphCommand } from "@/components/chat/graph-chat-context";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";

import {
  altitudeForZoom,
  buildCosmosGraphModel,
  type CosmosGraphModel,
  type GraphAltitude,
} from "./cosmos-graph-adapter";
import { GraphFilterChips } from "./graph-filter-chips";
import { GraphHtmlCardRenderer } from "./graph-html-card-renderer";
import { computeLineage } from "./graph-lineage";
import { GraphSmartViewSelector } from "./graph-smart-view-selector";
import { applySmartView, type SmartView } from "./graph-smart-views";
import { GraphSpotlight, SpotlightTrigger } from "./graph-spotlight";
import { FILTERABLE_NODE_TYPES, MOTION } from "./graph-constants";
import { WhyPanel } from "./why-panel";

type ViewMode =
  | { kind: "default" }
  | { kind: "lineage"; targetTitle: string }
  | { kind: "focused"; targetTitle: string };

const DEFAULT_SIMULATION = {
  simulationGravity: 0.18,
  simulationRepulsion: 0.68,
  simulationLinkSpring: 0.7,
  simulationLinkDistance: 22,
  simulationFriction: 0.84,
};

const RECOMPOSE_SIMULATION = {
  simulationGravity: 0.42,
  simulationRepulsion: 0.16,
  simulationLinkSpring: 1.35,
  simulationLinkDistance: 14,
  simulationFriction: 0.74,
};

function GraphViewInner({ projectId }: { projectId: number }) {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const containerRef = useRef<HTMLDivElement>(null);
  const graphRef = useRef<Graph | null>(null);
  const rendererRef = useRef<GraphHtmlCardRenderer | null>(null);
  const modelRef = useRef<CosmosGraphModel | null>(null);
  const graphDataRef = useRef<GraphData | null>(null);
  const altitudeRef = useRef<GraphAltitude>("overview");
  const selectedNodeIdRef = useRef<string | null>(null);
  const hoveredNodeIdRef = useRef<string | null>(null);
  const sourceRefsRef = useRef<SourceReference[]>([]);
  const firstRenderRef = useRef(true);
  const recomposeTimerRef = useRef<number | null>(null);

  const [graphData, setGraphData] = useState<GraphData | null>(null);
  const [badgesByNode, setBadgesByNode] = useState<Map<string, { severity: "high" | "medium" | "low"; count: number }>>(
    new Map(),
  );
  const [loading, setLoading] = useState(true);
  const [layouting, setLayouting] = useState(false);
  const [compatibilityError, setCompatibilityError] = useState<string | null>(null);
  const [activeSmartView, setActiveSmartView] = useState<SmartView | null>(null);
  const [visibleTypes, setVisibleTypes] = useState<Set<string>>(new Set(FILTERABLE_NODE_TYPES));
  const [highlightedIds, setHighlightedIds] = useState<Set<string>>(new Set());
  const [selectedNodeId, setSelectedNodeId] = useState<string | null>(null);
  const [hoveredNodeId, setHoveredNodeId] = useState<string | null>(null);
  const [altitude, setAltitude] = useState<GraphAltitude>("overview");
  const [spotlightOpen, setSpotlightOpen] = useState(false);
  const [viewMode, setViewMode] = useState<ViewMode>({ kind: "default" });
  const [chatContextIds, setChatContextIds] = useState<string[]>([]);
  const [whyTarget, setWhyTarget] = useState<{ nodeType: string; nodeId: number } | null>(null);
  const [sourceRefs, setSourceRefs] = useState<SourceReference[]>([]);

  useEffect(() => {
    graphDataRef.current = graphData;
  }, [graphData]);

  const renderOverlay = useCallback(() => {
    const graph = graphRef.current;
    const renderer = rendererRef.current;
    const model = modelRef.current;
    if (!graph || !renderer || !model || !renderer.supported) return;
    renderer.render({
      graph,
      model,
      altitude: altitudeRef.current,
      selectedNodeId: selectedNodeIdRef.current,
      hoveredNodeId: hoveredNodeIdRef.current,
      sourceRefs: sourceRefsRef.current,
    });
  }, []);

  const refreshGraphData = useCallback(async () => {
    const data = await api.getGraphData(projectId);
    setGraphData(data);
    return data;
  }, [projectId]);

  const refreshBadges = useCallback(async () => {
    try {
      const badges = await api.getContradictionBadges(projectId);
      const map = new Map<string, { severity: "high" | "medium" | "low"; count: number }>();
      for (const badge of badges) {
        const severity: "high" | "medium" | "low" =
          badge.high > 0 ? "high" : badge.medium > 0 ? "medium" : "low";
        map.set(`${badge.node_type}:${badge.node_id}`, { severity, count: badge.total });
      }
      setBadgesByNode(map);
    } catch {
      setBadgesByNode(new Map());
    }
  }, [projectId]);

  useEffect(() => {
    return subscribeToProject(projectId, [
      { event: "contradiction.detected", handler: refreshBadges },
      { event: "contradiction.resolved", handler: refreshBadges },
      { event: "contradiction.dismissed", handler: refreshBadges },
      { event: "contradiction.stale", handler: refreshBadges },
    ]);
  }, [projectId, refreshBadges]);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    void refreshBadges();
    api
      .getGraphData(projectId)
      .then((data) => {
        if (cancelled) return;
        setGraphData(data);
        const defaultView: SmartView | null = data.nodes.length >= 10 ? "next_actions" : null;
        setActiveSmartView(defaultView);
        setHighlightedIds(defaultView ? applySmartView(defaultView, data) : new Set());
      })
      .catch(() => {
        if (!cancelled) setGraphData({ nodes: [], edges: [], flags: [], density: {} });
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [projectId, refreshBadges]);

  const selectedNode = useMemo(() => {
    if (!selectedNodeId || !graphData) return null;
    return graphData.nodes.find((node) => node.id === selectedNodeId) ?? null;
  }, [selectedNodeId, graphData]);

  const chatContextNodes = useMemo(() => {
    if (!graphData) return [];
    return chatContextIds
      .map((id) => graphData.nodes.find((node) => node.id === id))
      .filter((node): node is GraphDataNode => Boolean(node));
  }, [chatContextIds, graphData]);

  const updateNodeStatus = useCallback(
    async (node: GraphDataNode, status: string) => {
      const updateMap: Record<string, string> = {
        insight: "updateInsight",
        requirement: "updateRequirement",
        decision: "updateDecision",
        task: "updateTask",
        constraint: "updateConstraint",
      };
      const fnName = updateMap[node.node_type];
      const updateFn = fnName ? (api as Record<string, unknown>)[fnName] : null;
      if (typeof updateFn !== "function") return;
      await updateFn(projectId, node.node_id, { status });
      await refreshGraphData();
    },
    [projectId, refreshGraphData],
  );

  const showLineage = useCallback(
    (node: GraphDataNode) => {
      const data = graphDataRef.current;
      const graph = graphRef.current;
      const model = modelRef.current;
      if (!data || !graph || !model) return;
      const lineage = computeLineage(data.nodes, data.edges, node.id);
      setViewMode({ kind: "lineage", targetTitle: node.title });
      setHighlightedIds(lineage.chainIds);

      const indices = Array.from(lineage.chainIds)
        .map((id) => model.nodeIndexById.get(id))
        .filter((index): index is number => index !== undefined);

      if (recomposeTimerRef.current !== null) {
        window.clearTimeout(recomposeTimerRef.current);
      }

      graph.setConfigPartial({
        ...RECOMPOSE_SIMULATION,
        highlightedPointIndices: indices,
        outlinedPointIndices: indices,
      });
      if (indices.length > 0) {
        graph.fitViewByPointIndices(indices, MOTION.RESTRUCTURE_MOVE_MS, 0.28);
      }
      graph.start(0.82);
      recomposeTimerRef.current = window.setTimeout(() => {
        graphRef.current?.setConfigPartial(DEFAULT_SIMULATION);
        recomposeTimerRef.current = null;
      }, MOTION.RESTRUCTURE_MOVE_MS + 250);
    },
    [],
  );

  const cardActions = useMemo(
    () => ({
      onAccept: (node: GraphDataNode) => {
        void updateNodeStatus(node, node.node_type === "task" ? "done" : "accepted").catch(() => undefined);
      },
      onChallenge: (node: GraphDataNode) => {
        setSelectedNodeId(node.id);
        setHighlightedIds(new Set([node.id]));
        setWhyTarget({ nodeType: node.node_type, nodeId: node.node_id });
      },
      onShowLineage: (node: GraphDataNode) => showLineage(node),
      onOpenTrail: (node: GraphDataNode) =>
        navigate(`/projects/${projectId}/trail/${node.node_type}/${node.node_id}`, {
          state: { from: "graph" },
        }),
      onChatAbout: (node: GraphDataNode) =>
        setChatContextIds((prev) =>
          prev.includes(node.id) ? prev.filter((id) => id !== node.id) : [...prev, node.id],
        ),
    }),
    [navigate, projectId, showLineage, updateNodeStatus],
  );

  useEffect(() => {
    rendererRef.current?.updateActions(cardActions);
  }, [cardActions]);

  useEffect(() => {
    selectedNodeIdRef.current = selectedNodeId;
    const graph = graphRef.current;
    const model = modelRef.current;
    if (graph && model) {
      const selectedIndex = selectedNodeId ? model.nodeIndexById.get(selectedNodeId) : undefined;
      graph.trackPointPositionsByIndices(selectedIndex === undefined ? [] : [selectedIndex]);
    }
    renderOverlay();
  }, [selectedNodeId, renderOverlay]);

  useEffect(() => {
    hoveredNodeIdRef.current = hoveredNodeId;
    renderOverlay();
  }, [hoveredNodeId, renderOverlay]);

  useEffect(() => {
    altitudeRef.current = altitude;
    renderOverlay();
  }, [altitude, renderOverlay]);

  useEffect(() => {
    sourceRefsRef.current = sourceRefs;
    renderOverlay();
  }, [sourceRefs, renderOverlay]);

  useEffect(() => {
    let cancelled = false;
    if (!selectedNode || (selectedNode.source_reference_count ?? 0) === 0) {
      setSourceRefs([]);
      return;
    }
    api
      .getNodeSourceReferences(projectId, selectedNode.node_type, selectedNode.node_id)
      .then((refs) => {
        if (!cancelled) setSourceRefs(refs);
      })
      .catch(() => {
        if (!cancelled) setSourceRefs([]);
      });
    return () => {
      cancelled = true;
    };
  }, [projectId, selectedNode]);

  useEffect(() => {
    const focusId = searchParams.get("focus");
    if (focusId) {
      setSelectedNodeId(focusId);
      setHighlightedIds(new Set([focusId]));
    }
  }, [searchParams]);

  useEffect(() => {
    if (loading) return;
    if (!containerRef.current || graphRef.current) return;

    const graph = new Graph(containerRef.current, {
      ...DEFAULT_SIMULATION,
      backgroundColor: [1, 1, 1, 0],
      spaceSize: 4096,
      fitViewOnInit: true,
      fitViewDelay: 200,
      fitViewPadding: 0.18,
      curvedLinks: true,
      curvedLinkSegments: 16,
      pointDefaultColor: "#CECBF6",
      pointDefaultSize: 6,
      pointGreyoutColor: "#CBD5E1",
      pointGreyoutOpacity: 0.16,
      linkDefaultColor: "#AFA9EC",
      linkDefaultWidth: 0.6,
      linkGreyoutOpacity: 0.08,
      linkVisibilityDistanceRange: [0, 900],
      renderHoveredPointRing: true,
      hoveredPointRingColor: "#534AB7",
      focusedPointRingColor: "#534AB7",
      outlinedPointRingColor: "#BA7517",
      hoveredPointCursor: "pointer",
      enableDrag: true,
      enableSimulationDuringZoom: true,
      pointSamplingDistance: 120,
      linkSamplingDistance: 140,
      attribution: "",
      onPointClick: (index) => {
        const model = modelRef.current;
        const node = model?.nodes[index];
        if (!node) return;
        setSelectedNodeId(node.id);
        setViewMode({ kind: "focused", targetTitle: node.title });
        graph.zoomToPointByIndex(index, 650, 1.7, false, true);
      },
      onBackgroundClick: () => {
        setSelectedNodeId(null);
        setViewMode({ kind: "default" });
      },
      onPointMouseOver: (index) => {
        const model = modelRef.current;
        setHoveredNodeId(model?.nodes[index]?.id ?? null);
      },
      onPointMouseOut: () => setHoveredNodeId(null),
      onZoom: () => {
        const nextAltitude = altitudeForZoom(graph.getZoomLevel());
        altitudeRef.current = nextAltitude;
        setAltitude(nextAltitude);
        renderOverlay();
      },
      onSimulationTick: () => renderOverlay(),
      onSimulationEnd: () => renderOverlay(),
    });

    graphRef.current = graph;
    graph.ready
      .then(() => {
        if (!containerRef.current) return;
        const renderer = new GraphHtmlCardRenderer(containerRef.current, cardActions);
        rendererRef.current = renderer;
        if (!renderer.supported) {
          setCompatibilityError(renderer.unsupportedReason ?? "This browser does not support html-in-canvas.");
        }
        renderOverlay();
      })
      .catch((error: Error) => {
        setCompatibilityError(error.message);
      });

    return () => {
      if (recomposeTimerRef.current !== null) {
        window.clearTimeout(recomposeTimerRef.current);
        recomposeTimerRef.current = null;
      }
      rendererRef.current?.destroy();
      rendererRef.current = null;
      graph.destroy();
      graphRef.current = null;
    };
  }, [loading, renderOverlay]);

  useEffect(() => {
    const graph = graphRef.current;
    if (!graph || !graphData) return;
    setLayouting(true);
    const enrichedData = {
      ...graphData,
      nodes: graphData.nodes.map((node) => {
        const badge = badgesByNode.get(`${node.node_type}:${node.node_id}`);
        return badge ? { ...node, flag_count: Math.max(node.flag_count, badge.count) } : node;
      }),
    };
    const model = buildCosmosGraphModel(enrichedData, visibleTypes, highlightedIds);
    modelRef.current = model;

    graph.setPointPositions(model.pointPositions);
    graph.setPointColors(model.pointColors);
    graph.setPointSizes(model.pointSizes);
    graph.setPointShapes(model.pointShapes);
    graph.setLinks(model.links);
    graph.setLinkColors(model.linkColors);
    graph.setLinkWidths(model.linkWidths);
    graph.setLinkArrows(model.linkArrows);
    graph.setConfigPartial({
      highlightedPointIndices:
        highlightedIds.size > 0
          ? Array.from(highlightedIds)
              .map((id) => model.nodeIndexById.get(id))
              .filter((index): index is number => index !== undefined)
          : undefined,
      focusedPointIndex: selectedNodeId ? model.nodeIndexById.get(selectedNodeId) : undefined,
    });
    graph.render();

    const selectedIndex = selectedNodeId ? model.nodeIndexById.get(selectedNodeId) : undefined;
    graph.trackPointPositionsByIndices(selectedIndex === undefined ? [] : [selectedIndex]);
    if (firstRenderRef.current) {
      firstRenderRef.current = false;
      graph.fitView(350, 0.18);
    }
    setLayouting(false);
    renderOverlay();
  }, [graphData, visibleTypes, highlightedIds, selectedNodeId, badgesByNode, renderOverlay]);

  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key === "/") {
        event.preventDefault();
        setSpotlightOpen((prev) => !prev);
        return;
      }
      if (event.key === "Escape") {
        if (recomposeTimerRef.current !== null) {
          window.clearTimeout(recomposeTimerRef.current);
          recomposeTimerRef.current = null;
        }
        setViewMode({ kind: "default" });
        setSelectedNodeId(null);
        setHighlightedIds(new Set());
        graphRef.current?.setConfigPartial({
          ...DEFAULT_SIMULATION,
          highlightedPointIndices: undefined,
          outlinedPointIndices: undefined,
        });
      }
      if (event.key.toLowerCase() === "l" && selectedNode) {
        event.preventDefault();
        showLineage(selectedNode);
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [selectedNode, showLineage]);

  const handleToggleType = useCallback((type: string) => {
    setVisibleTypes((prev) => {
      const next = new Set(prev);
      if (next.has(type)) next.delete(type);
      else next.add(type);
      return next;
    });
  }, []);

  const handleSmartViewChange = useCallback(
    (view: SmartView | null) => {
      setActiveSmartView(view);
      if (!graphData) return;
      setHighlightedIds(view ? applySmartView(view, graphData) : new Set());
    },
    [graphData],
  );

  const focusNode = useCallback((nodeId: string) => {
    const graph = graphRef.current;
    const model = modelRef.current;
    const index = model?.nodeIndexById.get(nodeId);
    const node = model?.nodes.find((n) => n.id === nodeId);
    if (!graph || index === undefined || !node) return;
    setSelectedNodeId(nodeId);
    setHighlightedIds(new Set([nodeId]));
    setViewMode({ kind: "focused", targetTitle: node.title });
    graph.zoomToPointByIndex(index, 650, 1.7, false, true);
  }, []);

  const handleGraphCommand = useCallback(
    (command: GraphCommand) => {
      switch (command.type) {
        case "highlight":
          if (command.nodeIds) setHighlightedIds(new Set(command.nodeIds));
          break;
        case "focus":
          if (command.nodeId) focusNode(command.nodeId);
          break;
        case "show_lineage": {
          const node = graphData?.nodes.find((n) => n.id === command.nodeId);
          if (node) showLineage(node);
          break;
        }
        case "reset":
          setHighlightedIds(new Set());
          setSelectedNodeId(null);
          setViewMode({ kind: "default" });
          graphRef.current?.fitView(350, 0.18);
          break;
        case "node_created":
          refreshGraphData();
          break;
      }
    },
    [focusNode, graphData, refreshGraphData, showLineage],
  );

  const graphChatValue = useMemo(
    () => ({
      contextNodes: chatContextNodes,
      previewNode: selectedNode,
      onClearContext: () => setChatContextIds([]),
      onRemoveContext: (id: string) => setChatContextIds((prev) => prev.filter((item) => item !== id)),
      onGraphCommand: handleGraphCommand,
    }),
    [chatContextNodes, selectedNode, handleGraphCommand],
  );

  if (loading) {
    return (
      <div className="flex h-full items-center justify-center">
        <Skeleton className="h-96 w-96 rounded-xl" />
      </div>
    );
  }

  return (
    <GraphChatProvider value={graphChatValue}>
      <div className="relative h-full w-full overflow-hidden bg-background">
        <div ref={containerRef} className="absolute inset-0 hydra-cosmos-graph" />

        <div className="pointer-events-none absolute left-4 top-4 z-20 flex items-center gap-2">
          <div className="pointer-events-auto rounded-md border bg-background/88 px-2.5 py-1 text-xs text-muted-foreground shadow-sm backdrop-blur">
            <span className="font-medium text-foreground">Constellation</span>
            <span className="mx-1.5">·</span>
            {altitude}
          </div>
          <GraphSmartViewSelector
            active={activeSmartView}
            onChange={handleSmartViewChange}
            nodeCount={graphData?.nodes.length ?? 0}
          />
          {viewMode.kind !== "default" ? (
            <div className="pointer-events-auto flex items-center gap-1.5 rounded-md border bg-background/88 px-2 py-1 text-xs shadow-sm backdrop-blur">
              <GitBranch className="h-3 w-3 text-muted-foreground" />
              <span className="max-w-[240px] truncate">{viewMode.targetTitle}</span>
              <Button
                size="xs"
                variant="ghost"
                onClick={() => {
                  if (recomposeTimerRef.current !== null) {
                    window.clearTimeout(recomposeTimerRef.current);
                    recomposeTimerRef.current = null;
                  }
                  setViewMode({ kind: "default" });
                  setHighlightedIds(new Set());
                  graphRef.current?.setConfigPartial({
                    ...DEFAULT_SIMULATION,
                    highlightedPointIndices: undefined,
                    outlinedPointIndices: undefined,
                  });
                  graphRef.current?.fitView(350, 0.18);
                }}
              >
                Full graph
              </Button>
            </div>
          ) : null}
        </div>

        <div className="pointer-events-auto absolute right-4 top-4 z-20 flex items-center gap-1.5">
          {layouting ? (
            <div className="flex items-center gap-1 rounded-md border bg-background/88 px-2 py-1 text-[11px] text-muted-foreground shadow-sm backdrop-blur">
              <Loader2 className="h-3 w-3 animate-spin" />
              <span>Streaming to GPU…</span>
            </div>
          ) : null}
          {badgesByNode.size > 0 ? (
            <Tooltip delayDuration={120}>
              <TooltipTrigger asChild>
                <div className="flex h-7 items-center gap-1 rounded-md border bg-background/88 px-2 text-[11px] text-amber-700 shadow-sm backdrop-blur">
                  <ShieldAlert className="h-3 w-3" />
                  {badgesByNode.size}
                </div>
              </TooltipTrigger>
              <TooltipContent>Contradiction hotspots are highlighted in amber</TooltipContent>
            </Tooltip>
          ) : null}
          <GraphFilterChips visibleTypes={visibleTypes} onToggle={handleToggleType} />
          <SpotlightTrigger onClick={() => setSpotlightOpen(true)} />
          <Tooltip delayDuration={120}>
            <TooltipTrigger asChild>
              <Button size="icon-sm" variant="outline" onClick={() => graphRef.current?.fitView(350, 0.18)}>
                <Orbit className="h-4 w-4" />
              </Button>
            </TooltipTrigger>
            <TooltipContent>Fit graph</TooltipContent>
          </Tooltip>
          {selectedNode ? (
            <Tooltip delayDuration={120}>
              <TooltipTrigger asChild>
                <Button
                  size="icon-sm"
                  variant="outline"
                  onClick={() =>
                    navigate(`/projects/${projectId}/trail/${selectedNode.node_type}/${selectedNode.node_id}`, {
                      state: { from: "graph" },
                    })
                  }
                >
                  <Route className="h-4 w-4" />
                </Button>
              </TooltipTrigger>
              <TooltipContent>Open selected trail</TooltipContent>
            </Tooltip>
          ) : null}
        </div>

        {compatibilityError ? (
          <div className="absolute inset-0 z-30 flex items-center justify-center bg-background/95 p-8">
            <div className="max-w-md rounded-lg border bg-card p-6 text-center shadow-sm">
              <h2 className="text-base font-semibold">html-in-canvas required</h2>
              <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
                {compatibilityError} Open this graph in a Chromium build with native html-in-canvas
                support enabled.
              </p>
            </div>
          </div>
        ) : null}

        <WhyPanel
          open={whyTarget !== null}
          projectId={projectId}
          nodeType={whyTarget?.nodeType ?? null}
          nodeId={whyTarget?.nodeId ?? null}
          onClose={() => setWhyTarget(null)}
          onNavigateToNode={(nodeType, nodeId) => setWhyTarget({ nodeType, nodeId })}
        />

        <GraphSpotlight
          open={spotlightOpen}
          onClose={() => setSpotlightOpen(false)}
          nodes={graphData?.nodes ?? []}
          onFocusNode={focusNode}
          onSmartView={handleSmartViewChange}
          onFitToScreen={() => graphRef.current?.fitView(350, 0.18)}
          onSearch={(query) => {
            if (!graphData || !query.trim()) {
              setHighlightedIds(activeSmartView ? applySmartView(activeSmartView, graphData!) : new Set());
              return;
            }
            const q = query.toLowerCase();
            setHighlightedIds(
              new Set(graphData.nodes.filter((node) => node.title.toLowerCase().includes(q)).map((node) => node.id)),
            );
          }}
        />
      </div>
    </GraphChatProvider>
  );
}

export function GraphView({ projectId }: { projectId: number }) {
  return <GraphViewInner projectId={projectId} />;
}
