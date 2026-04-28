import {
  Component,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ErrorInfo,
  type ReactNode,
} from "react";
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
import { GraphDomCardOverlay } from "./graph-dom-card-overlay";
import { GraphFilterChips } from "./graph-filter-chips";
import { GraphHtmlCardRenderer } from "./graph-html-card-renderer";
import { computeLineage } from "./graph-lineage";
import { GraphSmartViewSelector } from "./graph-smart-view-selector";
import { applySmartView, type SmartView } from "./graph-smart-views";
import { GraphSpotlight, SpotlightTrigger } from "./graph-spotlight";
import {
  FILTERABLE_NODE_TYPES,
  LIBRARY_DEFAULT_VISIBLE_TYPES,
  LIBRARY_FILTERABLE_NODE_TYPES,
  MOTION,
} from "./graph-constants";
import { WhyPanel } from "./why-panel";

type ViewMode =
  | { kind: "default" }
  | { kind: "lineage"; targetTitle: string }
  | { kind: "focused"; targetTitle: string };

// Library spec §5: the Library lens uses the same Cosmograph engine but
// fetches a Library-flavored slice of the graph (Library node types only,
// sources always graph-resident).
export type GraphLens = "project" | "library";

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

function GraphViewInner({ projectId, lens = "project" }: { projectId: number; lens?: GraphLens }) {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const filterableTypes =
    lens === "library" ? LIBRARY_FILTERABLE_NODE_TYPES : FILTERABLE_NODE_TYPES;
  const initialVisibleTypes =
    lens === "library" ? LIBRARY_DEFAULT_VISIBLE_TYPES : FILTERABLE_NODE_TYPES;
  const containerRef = useRef<HTMLDivElement>(null);
  const graphRef = useRef<Graph | null>(null);
  // The card overlay can be either of two implementations: the DOM-only
  // overlay (default — zero GPU cost) or the experimental html-in-canvas
  // WebGL2 path (opt-in via `?cards=html-in-canvas`). Both expose the same
  // surface so GraphView can hold either behind a single ref.
  const rendererRef = useRef<GraphDomCardOverlay | GraphHtmlCardRenderer | null>(null);
  const modelRef = useRef<CosmosGraphModel | null>(null);
  const graphDataRef = useRef<GraphData | null>(null);
  const altitudeRef = useRef<GraphAltitude>("overview");
  const selectedNodeIdRef = useRef<string | null>(null);
  const hoveredNodeIdRef = useRef<string | null>(null);
  const sourceRefsRef = useRef<SourceReference[]>([]);
  const firstRenderRef = useRef(true);
  // Tracks whether we've performed the once-per-mount post-settle refit.
  const firstSettleRef = useRef(true);
  const recomposeTimerRef = useRef<number | null>(null);

  const [graphData, setGraphData] = useState<GraphData | null>(null);
  const [badgesByNode, setBadgesByNode] = useState<Map<string, { severity: "high" | "medium" | "low"; count: number }>>(
    new Map(),
  );
  const [loading, setLoading] = useState(true);
  const [layouting, setLayouting] = useState(false);
  const [compatibilityError, setCompatibilityError] = useState<string | null>(null);
  const [activeSmartView, setActiveSmartView] = useState<SmartView | null>(null);
  const [visibleTypes, setVisibleTypes] = useState<Set<string>>(new Set(initialVisibleTypes));
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

  // The set of node indices we want to label. Updated by the
  // selection/hover effect; read here so renderOverlay re-uses the
  // latest set on every animation tick (resize, simulation drift).
  const labelIndicesRef = useRef<number[]>([]);

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
      labelIndices: labelIndicesRef.current,
    });
  }, []);

  const refreshGraphData = useCallback(async () => {
    const data =
      lens === "library"
        ? await api.getLibraryGraphData(projectId)
        : await api.getGraphData(projectId);
    setGraphData(data);
    return data;
  }, [projectId, lens]);

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
    const fetcher =
      lens === "library" ? api.getLibraryGraphData(projectId) : api.getGraphData(projectId);
    fetcher
      .then((data) => {
        if (cancelled) return;
        setGraphData(data);
        // Library lens doesn't surface "next actions" — the Library is a
        // research workspace, not an execution surface. Skip auto-selection.
        const defaultView: SmartView | null =
          lens === "library" || data.nodes.length < 10 ? null : "next_actions";
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
  }, [projectId, lens, refreshBadges]);

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
        try {
          graph.fitViewByPointIndices(indices, MOTION.RESTRUCTURE_MOVE_MS, 0.28);
        } catch (err) {
          console.warn("[GraphView] fitViewByPointIndices skipped", err);
        }
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

    // StrictMode in dev double-mounts effects: mount → cleanup → mount again.
    // The first mount's `graph.ready` promise can resolve AFTER cleanup runs,
    // creating a second GraphHtmlCardRenderer (with its own GL context and
    // texture pool) on top of the second mount's renderer. Stack two of those
    // and the GPU process OOMs — Chrome shows the broken-robot crash page.
    // Track cleanup via a closure flag so the deferred renderer setup bails.
    let effectCleanedUp = false;

    const graph = new Graph(containerRef.current, {
      ...DEFAULT_SIMULATION,
      backgroundColor: [1, 1, 1, 0],
      // Match Cosmograph's own quick-start: use the documented defaults
      // for spaceSize, scalePointsOnZoom, rescalePositions. Without
      // `scalePointsOnZoom` points stay at fixed device-pixel size when
      // you zoom in, so the constellation appears to dissolve. Without
      // `rescalePositions` our adapter's ring-radius initial layout
      // isn't normalised into the simulation grid and the camera fits
      // it awkwardly.
      spaceSize: 4096,
      scalePointsOnZoom: true,
      rescalePositions: true,
      fitViewOnInit: true,
      fitViewDelay: 1000,
      fitViewPadding: 0.18,
      // Straight links — curved + 16 segments tessellated every edge into
      // 16 line primitives, taxing the GPU for cosmetic gain.
      curvedLinks: false,
      pointDefaultColor: "#CECBF6",
      pointGreyoutColor: "#CBD5E1",
      pointGreyoutOpacity: 0.16,
      linkDefaultColor: "#94a3b8",
      linkDefaultWidth: 0.5,
      linkGreyoutOpacity: 0.06,
      renderHoveredPointRing: true,
      // Calm ring palette: hover/focus are deep slate (the same neutral
      // the rest of the chrome uses), the dense-evidence outline ring
      // is a softer slate so it reads as "thick" without shouting.
      hoveredPointRingColor: "#1f2937",
      focusedPointRingColor: "#1f2937",
      outlinedPointRingColor: "#475569",
      hoveredPointCursor: "pointer",
      enableDrag: true,
      // Don't run the force simulation during pan/zoom — it pegs the GPU
      // for no perceptible benefit. Cosmograph's demo doesn't enable this.
      enableSimulationDuringZoom: false,
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
      // No onSimulationTick — that callback fires 60×/sec and is only
      // useful when a card overlay needs to track moving points. The DOM
      // overlay re-positions itself on its own animation frame; the
      // html-in-canvas path mounts onSimulationTick separately when it
      // becomes active. At overview altitude with no overlay, ticks are
      // pure waste.
      onSimulationEnd: () => {
        // Once the force simulation settles, refit the camera once so
        // the constellation fills the canvas (Cosmograph's
        // `fitViewOnInit` fires too early, before nodes have spread).
        // Do NOT call graph.pause() — it interrupts Cosmograph's camera
        // tween mid-animation, freezing the view in a half-state. With
        // sim-during-zoom off and curvedLinks off, the idle simulation
        // costs almost nothing anyway.
        if (firstSettleRef.current) {
          firstSettleRef.current = false;
          try {
            graph.fitView(450, 0.18);
          } catch {
            // positions not ready yet; user can hit Fit manually
          }
        }
      },
    });

    graphRef.current = graph;
    graph.ready
      .then(() => {
        if (effectCleanedUp) {
          graph.destroy();
          return;
        }
        // Card renderer is created lazily — see effect below — so a single
        // browser tab never holds two WebGL2 contexts at once, and the
        // GPU process doesn't get pressured before the user actually
        // zooms in to a point worth seeing as a card.
        renderOverlay();
      })
      .catch((error: Error) => {
        if (!effectCleanedUp) setCompatibilityError(error.message);
      });

    return () => {
      effectCleanedUp = true;
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

  // Lazy-mount the card overlay the first time the user zooms past
  // overview altitude. Three modes:
  //   default       → DOM overlay (no GPU cost, always works)
  //   ?cards=off    → no card layer (escape hatch — points-only graph)
  //   ?cards=html-in-canvas → experimental WebGL2 + texElementImage2D
  //                    (Constellation §5.1 ideal path; can OOM the GPU
  //                    process on real hardware so it's opt-in only)
  useEffect(() => {
    if (rendererRef.current) return;
    if (altitude === "overview") return;
    const cardsMode = searchParams.get("cards");
    if (cardsMode === "off") return;
    if (!containerRef.current || !graphRef.current) return;

    if (cardsMode === "html-in-canvas") {
      const renderer = new GraphHtmlCardRenderer(containerRef.current, cardActions);
      rendererRef.current = renderer;
      if (!renderer.supported) {
        setCompatibilityError(
          renderer.unsupportedReason ?? "This browser does not support html-in-canvas.",
        );
      }
    } else {
      rendererRef.current = new GraphDomCardOverlay(containerRef.current, cardActions);
    }
    renderOverlay();
  }, [altitude, cardActions, renderOverlay, searchParams]);

  // Effect A — full data rebuild. Re-runs only when the data itself
  // changes (or visibility/badges change the structural set). Highlights
  // and selection now live in their own effect that pushes config only,
  // never touches positions, never restarts the simulation.
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
    // Dense-evidence outline ring (Constellation §1.1 "thick evidence").
    graph.setConfigPartial({
      outlinedPointIndices:
        model.denseRingIndices.length > 0 ? model.denseRingIndices : undefined,
    });
    graph.render();

    if (firstRenderRef.current) {
      firstRenderRef.current = false;
    }
    setLayouting(false);
    renderOverlay();
    // `highlightedIds` is intentionally NOT in the deps — it's now
    // applied in the selection/highlight effect via setConfigPartial.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [graphData, visibleTypes, badgesByNode, renderOverlay]);

  // Compute the effective highlight set:
  //   1. Hover takes priority — show the hovered node + its 1-degree
  //      neighbours so the user can see what connects to what without
  //      committing to a click.
  //   2. Selection (when not hovering) — same treatment, persisted.
  //   3. Otherwise fall back to whatever explicit `highlightedIds` are
  //      driven by smart views, search, or spotlight.
  const effectiveHighlights = useMemo(() => {
    const computeNeighbours = (anchorId: string): Set<string> => {
      const set = new Set<string>([anchorId]);
      if (!graphData) return set;
      for (const e of graphData.edges) {
        if (e.source === anchorId) set.add(e.target);
        if (e.target === anchorId) set.add(e.source);
      }
      return set;
    };

    if (hoveredNodeId) return computeNeighbours(hoveredNodeId);
    if (selectedNodeId) return computeNeighbours(selectedNodeId);
    return highlightedIds;
  }, [hoveredNodeId, selectedNodeId, highlightedIds, graphData]);

  // The top-N most-connected node indices — stable across pan/zoom so
  // labels at neighbourhood altitude don't flicker as the camera moves.
  // Recomputed only when the underlying data changes.
  const topConnectedIndices = useMemo(() => {
    const model = modelRef.current;
    if (!model || !graphData) return [] as number[];
    const TOP_N = 20;
    return model.nodes
      .map((node, index) => ({
        index,
        score:
          (node.connection_count ?? 0) +
          (node.source_reference_count ?? 0) * 1.5,
      }))
      .sort((a, b) => b.score - a.score)
      .slice(0, TOP_N)
      .map((entry) => entry.index);
    // Recompute when the data effect rebuilds the model. badgesByNode is
    // included because the data effect re-runs on it, refreshing model.
  }, [graphData, badgesByNode]);

  // Effect B — selection / hover / highlight updates. Never re-seeds
  // positions or restarts the simulation. Pushes:
  //   1. focusedPointIndex + highlightedPointIndices into Cosmograph
  //      config (drives ring + greyout)
  //   2. The combined label-index set (top-N + hovered/selected +
  //      neighbours) into trackPointPositionsByIndices so the DOM
  //      overlay can read their screen positions for labels
  useEffect(() => {
    const graph = graphRef.current;
    const model = modelRef.current;
    if (!graph || !model) return;

    const focusedIndex = selectedNodeId ? model.nodeIndexById.get(selectedNodeId) : undefined;
    const highlightedIndices =
      effectiveHighlights.size > 0
        ? Array.from(effectiveHighlights)
            .map((id) => model.nodeIndexById.get(id))
            .filter((index): index is number => index !== undefined)
        : undefined;

    // Build the label-index set per the documented algorithm.
    const labelSet = new Set<number>();
    if (altitude === "neighbourhood") {
      for (const idx of topConnectedIndices) labelSet.add(idx);
    }
    // Hover/select neighbours always show, regardless of altitude.
    if (highlightedIndices) {
      for (const idx of highlightedIndices) labelSet.add(idx);
    }
    if (focusedIndex !== undefined) labelSet.add(focusedIndex);
    const labelIndices = Array.from(labelSet);
    labelIndicesRef.current = labelIndices;

    graph.setConfigPartial({
      highlightedPointIndices: highlightedIndices,
      focusedPointIndex: focusedIndex,
    });
    // Track every label point so we can read its screen position. Card
    // tracking still works because the focused index is always in the set.
    graph.trackPointPositionsByIndices(labelIndices);
    renderOverlay();
  }, [selectedNodeId, effectiveHighlights, altitude, topConnectedIndices, renderOverlay]);

  // All user-initiated fitView calls below funnel through this — catch
  // the rare race where a user hits "Fit" before positions have rendered.
  const safeFitView = useCallback((duration = 350, padding = 0.18) => {
    try {
      graphRef.current?.fitView(duration, padding);
    } catch (err) {
      console.warn("[GraphView] fitView skipped (positions not ready)", err);
    }
  }, []);

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
          safeFitView(350, 0.18);
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

        <div className="pointer-events-none absolute left-4 top-4 z-20 flex items-start gap-2">
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
                  safeFitView(350, 0.18);
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
          <GraphFilterChips
            visibleTypes={visibleTypes}
            onToggle={handleToggleType}
            filterableTypes={filterableTypes}
          />
          <SpotlightTrigger onClick={() => setSpotlightOpen(true)} />
          <Tooltip delayDuration={120}>
            <TooltipTrigger asChild>
              <Button size="icon-sm" variant="outline" onClick={() => safeFitView(350, 0.18)}>
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

        {/* Constellation §5.1 — fallback should degrade gracefully, not
            block the constellation. Render the notice as a small chip
            in the bottom-right so the underlying WebGL points stay
            visible. */}
        {compatibilityError ? (
          <div className="pointer-events-auto absolute bottom-4 right-4 z-30 max-w-xs rounded-md border bg-background/95 px-3 py-2 text-[11px] leading-snug text-muted-foreground shadow-sm backdrop-blur">
            <div className="font-medium text-foreground">Card layer disabled</div>
            <p className="mt-0.5">
              {compatibilityError} Constellation still renders; selected-node cards are
              suppressed until you open this in a browser with html-in-canvas support.
            </p>
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
          onFitToScreen={() => safeFitView(350, 0.18)}
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

// Outer boundary — if Cosmograph or any deep child throws (rare GPU
// failures, library bugs), the user gets a visible "graph unavailable"
// message instead of a blank app. Errors do not propagate past this point.
class GraphSurfaceErrorBoundary extends Component<
  { children: ReactNode; onReset?: () => void },
  { error: Error | null }
> {
  constructor(props: { children: ReactNode; onReset?: () => void }) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(error: Error) {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error("[GraphView] surface crashed", error, info);
  }

  render() {
    if (this.state.error) {
      return (
        <div className="flex h-full w-full items-center justify-center bg-background p-8">
          <div className="max-w-md rounded-lg border bg-card p-6 text-center shadow-sm">
            <h2 className="text-base font-semibold">Graph couldn't render</h2>
            <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
              {this.state.error.message}
            </p>
            <button
              type="button"
              onClick={() => this.setState({ error: null })}
              className="mt-4 rounded-md border bg-background px-3 py-1.5 text-xs hover:bg-muted"
            >
              Try again
            </button>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}

export function GraphView({
  projectId,
  lens = "project",
}: {
  projectId: number;
  lens?: GraphLens;
}) {
  return (
    <GraphSurfaceErrorBoundary>
      <GraphViewInner projectId={projectId} lens={lens} />
    </GraphSurfaceErrorBoundary>
  );
}
