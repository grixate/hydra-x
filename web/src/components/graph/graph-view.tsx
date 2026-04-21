import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import {
  ReactFlow,
  ReactFlowProvider,
  Background,
  Controls,
  MiniMap,
  useNodesState,
  useEdgesState,
  useReactFlow,
  useViewport,
  type Node,
  type Edge,
  type Connection,
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";

import { api } from "@/lib/api";
import { subscribeToProject } from "@/lib/project-channel";
import type { GraphData, GraphDataNode } from "@/types";
import { computeLayout, type LayoutMode } from "./graph-layout";
import { GraphCustomNode } from "./graph-custom-node";
import { GraphGroupNode } from "./graph-group-node";
import { GraphSummaryNode } from "./graph-summary-node";
import { GraphCustomEdge } from "./graph-custom-edge";
import { LayoutControlsContext } from "./graph-layout-controls";
import { Loader2 } from "lucide-react";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectSeparator,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { GraphSmartViewSelector } from "./graph-smart-view-selector";
import { GraphFilterChips } from "./graph-filter-chips";
import { GraphViewModeToolbar, type GraphViewMode } from "./graph-view-mode-toolbar";
import { computeLineage, layoutLineageChainFromAnchor } from "./graph-lineage";
import { composeView, type ComposedViewSpec } from "./graph-composed-views";
import { MOTION } from "./graph-constants";
import { GraphSpotlight, SpotlightTrigger } from "./graph-spotlight";
import { GraphChatProvider, type GraphCommand } from "@/components/chat/graph-chat-context";
import { GraphNodeDetail } from "./graph-node-detail";
import { WhyPanel } from "./why-panel";
import { ConnectionDialog } from "./connection-dialog";
import { EdgeDetailPopover } from "./edge-detail-popover";
import { FILTERABLE_NODE_TYPES } from "./graph-constants";
import { applySmartView, type SmartView } from "./graph-smart-views";
import { Skeleton } from "@/components/ui/skeleton";

const nodeTypes = {
  graphNode: GraphCustomNode,
  groupNode: GraphGroupNode,
  summaryNode: GraphSummaryNode,
};

const COLLAPSE_THRESHOLD = 200;
const EDGE_FADE_THRESHOLD = 200;
const edgeTypes = { graphEdge: GraphCustomEdge };

function ArrowMarker() {
  return (
    <svg className="absolute h-0 w-0">
      <defs>
        <marker
          id="arrow-marker"
          viewBox="0 0 10 10"
          refX="10"
          refY="5"
          markerWidth="6"
          markerHeight="6"
          orient="auto-start-reverse"
        >
          <path d="M 0 0 L 10 5 L 0 10 z" fill="#94a3b8" />
        </marker>
      </defs>
    </svg>
  );
}

function parseNodeType(id: string): string {
  const idx = id.lastIndexOf("-");
  return id.slice(0, idx);
}
function parseNodeId(id: string): number {
  const idx = id.lastIndexOf("-");
  return Number(id.slice(idx + 1));
}

function GraphViewInner({ projectId }: { projectId: number }) {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { fitView } = useReactFlow();
  const viewport = useViewport();
  const containerRef = useRef<HTMLDivElement>(null);

  // Data
  const [graphData, setGraphData] = useState<GraphData | null>(null);
  const [badgesByNode, setBadgesByNode] = useState<Map<string, { severity: "high" | "medium" | "low"; count: number }>>(
    new Map(),
  );
  const [loading, setLoading] = useState(true);
  const [nodes, setNodes, onNodesChange] = useNodesState([] as Node[]);
  const [edges, setEdges, onEdgesChange] = useEdgesState([] as Edge[]);

  // Selection — detail preview (single node being inspected)
  const [previewNodeId, setPreviewNodeId] = useState<string | null>(null);
  const [whyTarget, setWhyTarget] = useState<{ nodeType: string; nodeId: number } | null>(null);
  const [selectedEdgeId, setSelectedEdgeId] = useState<string | null>(null);
  // Chat context — nodes explicitly added for agent conversations (persists across previews)
  const [chatContextIds, setChatContextIds] = useState<string[]>([]);

  // Filters
  const [visibleTypes, setVisibleTypes] = useState<Set<string>>(
    new Set(FILTERABLE_NODE_TYPES),
  );
  const [highlightedIds, setHighlightedIds] = useState<Set<string>>(new Set());
  const [searchQuery, setSearchQuery] = useState("");
  const [activeSmartView, setActiveSmartView] = useState<SmartView | null>(null);

  // Layout mode
  const [layoutMode, setLayoutMode] = useState<LayoutMode>("structured");
  const [expandedGroups, setExpandedGroups] = useState<Set<string>>(new Set());
  const [layouting, setLayouting] = useState(false);

  // Graph-Opt §8/§9 — view-mode (Lineage / Composed view).
  const [viewMode, setViewMode] = useState<GraphViewMode>({ kind: "default" });
  const [composedSpec, setComposedSpec] = useState<ComposedViewSpec | null>(null);
  const [lineageTargetId, setLineageTargetId] = useState<string | null>(null);

  const requestIdRef = useRef(0);
  const latestRequestRef = useRef(0);

  const toggleGroup = useCallback((groupKey: string) => {
    setExpandedGroups((prev) => {
      const next = new Set(prev);
      if (next.has(groupKey)) next.delete(groupKey);
      else next.add(groupKey);
      return next;
    });
  }, []);

  // Spotlight
  const [spotlightOpen, setSpotlightOpen] = useState(false);

  // ⌘/ spotlight + ?/W Why-button shortcut (Stream B2.5).
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      // Ignore shortcuts while user is typing in an input.
      const target = e.target as HTMLElement | null;
      const inEditable =
        target &&
        (target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.isContentEditable);

      if ((e.metaKey || e.ctrlKey) && e.key === "/") {
        e.preventDefault();
        setSpotlightOpen((prev) => !prev);
        return;
      }

      if (inEditable) return;

      if ((e.key === "?" || e.key.toLowerCase() === "w") && previewNodeId) {
        const node = graphData?.nodes.find((n) => n.id === previewNodeId);
        if (node) {
          e.preventDefault();
          setWhyTarget({ nodeType: node.node_type, nodeId: node.node_id });
        }
      }

      // Graph-Opt §8 — `L` toggles Lineage View on the focused node.
      if (e.key.toLowerCase() === "l" && previewNodeId) {
        const node = graphData?.nodes.find((n) => n.id === previewNodeId);
        if (node) {
          e.preventDefault();
          setLineageTargetId((prev) => (prev === node.id ? null : node.id));
          setComposedSpec(null);
          setViewMode({ kind: "lineage", targetTitle: node.title });
        }
      }

      // Escape — return to default view.
      if (e.key === "Escape" && viewMode.kind !== "default") {
        setViewMode({ kind: "default" });
        setLineageTargetId(null);
        setComposedSpec(null);
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [previewNodeId, graphData, viewMode]);

  // Connection dialog
  const [pendingConnection, setPendingConnection] = useState<{
    source: string;
    target: string;
  } | null>(null);

  // Edge detail popover
  const [edgePopoverPosition, setEdgePopoverPosition] = useState<{
    x: number;
    y: number;
  } | null>(null);

  // --- DATA FETCH ---
  const refreshGraphData = useCallback(async () => {
    const data = await api.getGraphData(projectId);
    setGraphData(data);
    return data;
  }, [projectId]);

  const refreshBadges = useCallback(async () => {
    try {
      const badges = await api.getContradictionBadges(projectId);
      const map = new Map<string, { severity: "high" | "medium" | "low"; count: number }>();
      for (const b of badges) {
        const severity: "high" | "medium" | "low" =
          b.high > 0 ? "high" : b.medium > 0 ? "medium" : "low";
        map.set(`${b.node_type}:${b.node_id}`, { severity, count: b.total });
      }
      setBadgesByNode(map);
    } catch {
      /* leave badges empty — graph still renders */
    }
  }, [projectId]);

  // Live-update badges on contradiction lifecycle events so the graph
  // stays in sync with the Coherence agent.
  useEffect(() => {
    return subscribeToProject(projectId, [
      { event: "contradiction.detected", handler: refreshBadges },
      { event: "contradiction.resolved", handler: refreshBadges },
      { event: "contradiction.dismissed", handler: refreshBadges },
      { event: "contradiction.stale", handler: refreshBadges },
    ]);
  }, [projectId, refreshBadges]);

  useEffect(() => {
    setLoading(true);
    refreshBadges();
    refreshGraphData()
      .then(async (data) => {
        const defaultView: SmartView | null =
          data.nodes.length >= 10 ? "next_actions" : null;
        setActiveSmartView(defaultView);
        const highlighted = defaultView
          ? applySmartView(defaultView, data)
          : new Set<string>();
        setHighlightedIds(highlighted);
        await layoutAndSetNodes(data, visibleTypes, highlighted, []);
        setLoading(false);
        setTimeout(() => fitView({ padding: 0.1, duration: 300 }), 100);
      })
      .catch(() => setLoading(false));
  }, [projectId]);

  // Auto-collapse all groups when entering grouped mode on a large graph
  useEffect(() => {
    if (layoutMode === "structured") {
      if (expandedGroups.size > 0) setExpandedGroups(new Set());
      return;
    }
    if (graphData && graphData.nodes.length > COLLAPSE_THRESHOLD) {
      setExpandedGroups(new Set());
    }
  }, [layoutMode, graphData]);

  useEffect(() => {
    if (!graphData) return;
    layoutAndSetNodes(graphData, visibleTypes, highlightedIds, chatContextIds).then(() => {
      setTimeout(() => fitView({ padding: 0.1, duration: 300 }), 100);
    });
  }, [visibleTypes, layoutMode, expandedGroups]);

  useEffect(() => {
    if (!graphData) return;

    // Graph-Opt §8/§9 — apply lineage/composed overrides.
    let chainIds: Set<string> | null = null;
    let overridePositions: Map<string, { x: number; y: number }> | null = null;

    if (lineageTargetId && graphData.nodes.some((n) => n.id === lineageTargetId)) {
      const lineage = computeLineage(graphData.nodes, graphData.edges, lineageTargetId);
      chainIds = lineage.chainIds;
      // Anchor the chain at the target's current laid-out position so the
      // click doesn't teleport it across the canvas.
      setNodes((prev) => {
        const anchorNode = prev.find((n) => n.id === lineageTargetId);
        const anchor = anchorNode ? anchorNode.position : { x: 0, y: 0 };
        const positions = layoutLineageChainFromAnchor(lineage, anchor);

        return prev
          .filter((n) => {
            if (n.type === "groupNode" || n.type === "summaryNode") return true;
            return lineage.chainIds.has(n.id);
          })
          .map((n) => {
            if (n.type === "groupNode" || n.type === "summaryNode") return n;
            const overridden = positions.get(n.id);
            return {
              ...n,
              ...(overridden ? { position: overridden } : {}),
              data: {
                ...n.data,
                highlighted: false,
                dimmed: false,
                multiSelected: chatContextIds.includes(n.id),
                previewing: n.id === previewNodeId,
                inLineage: true,
              },
              style: {
                ...(n.style as object),
                transition: `transform ${MOTION.RESTRUCTURE_MOVE_MS}ms ${MOTION.EASE_IN_OUT}, opacity 180ms ease`,
              },
            };
          });
      });
      return;
    }

    if (composedSpec) {
      const view = composeView(graphData.nodes, graphData.edges, composedSpec);
      chainIds = view.relevantIds;
      overridePositions = view.positions;
    }

    const shouldSkipAnimation =
      !!overridePositions && overridePositions.size > MOTION.RESTRUCTURE_SKIP_THRESHOLD;

    setNodes((prev) =>
      prev.map((n) => {
        if (n.type === "groupNode" || n.type === "summaryNode") return n;

        const inChain = chainIds ? chainIds.has(n.id) : null;
        const overridden = overridePositions?.get(n.id);

        const positionUpdate = overridden
          ? { position: overridden }
          : {};

        return {
          ...n,
          ...positionUpdate,
          data: {
            ...n.data,
            highlighted: highlightedIds.size > 0 && highlightedIds.has(n.id),
            dimmed:
              (highlightedIds.size > 0 && !highlightedIds.has(n.id)) ||
              (chainIds !== null && !chainIds.has(n.id)),
            multiSelected: chatContextIds.includes(n.id),
            previewing: n.id === previewNodeId,
            inLineage: inChain,
          },
          // Skip the restructure animation if too many nodes move at once
          // (§4 O4). React Flow doesn't natively tween positions; we rely
          // on CSS transitions on the node wrapper.
          style: shouldSkipAnimation
            ? { ...(n.style as object), transition: "none" }
            : { ...(n.style as object), transition: `transform ${MOTION.RESTRUCTURE_MOVE_MS}ms ${MOTION.EASE_IN_OUT}` },
        };
      }),
    );
  }, [highlightedIds, chatContextIds, previewNodeId, lineageTargetId, composedSpec, graphData]);

  // When lineage exits, re-run layout so off-chain nodes come back.
  useEffect(() => {
    if (lineageTargetId === null && graphData) {
      layoutAndSetNodes(graphData, visibleTypes, highlightedIds, chatContextIds).then(() => {
        setTimeout(() => fitView({ padding: 0.1, duration: 300 }), 50);
      });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lineageTargetId]);

  async function layoutAndSetNodes(
    data: GraphData,
    types: Set<string>,
    highlighted: Set<string>,
    selected: string[],
  ) {
    const visibleNodes = data.nodes.filter((n) => types.has(n.node_type));
    const visibleNodeIds = new Set(visibleNodes.map((n) => n.id));
    const visibleEdges = data.edges.filter(
      (e) => visibleNodeIds.has(e.source) && visibleNodeIds.has(e.target),
    );
    setLayouting(true);
    const requestId = ++requestIdRef.current;
    latestRequestRef.current = requestId;
    const result = await computeLayout({
      graphNodes: visibleNodes,
      graphEdges: visibleEdges,
      mode: layoutMode,
      expandedGroups: Array.from(expandedGroups),
      edgeFadeThreshold: EDGE_FADE_THRESHOLD,
    });
    // Drop stale results
    if (requestId !== latestRequestRef.current) return;
    const finalNodes = result.nodes.map((n) => {
      const gd = n.data as unknown as GraphDataNode;
      const badge = badgesByNode.get(`${gd.node_type}:${gd.node_id}`);
      return {
        ...n,
        data: {
          ...n.data,
          highlighted: highlighted.size > 0 && highlighted.has(n.id),
          dimmed: highlighted.size > 0 && !highlighted.has(n.id),
          multiSelected: selected.includes(n.id),
          contradiction_severity: badge?.severity ?? null,
          contradiction_count: badge?.count ?? 0,
        },
      };
    });
    setNodes([...result.groupNodes, ...finalNodes, ...result.summaryNodes]);
    setEdges(result.edges);
    setLayouting(false);
  }

  // --- SEARCH ---
  const handleSearch = useCallback(
    (query: string) => {
      setSearchQuery(query);
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
        new Set(graphData.nodes.filter((n) => n.title.toLowerCase().includes(q)).map((n) => n.id)),
      );
    },
    [graphData, activeSmartView],
  );

  // --- SMART VIEW ---
  const handleSmartViewChange = useCallback(
    (view: SmartView | null) => {
      setActiveSmartView(view);
      if (!graphData) return;
      setHighlightedIds(view ? applySmartView(view, graphData) : new Set());
    },
    [graphData],
  );

  // --- URL PARAMS ---
  useEffect(() => {
    const focusId = searchParams.get("focus");
    if (focusId) {
      setPreviewNodeId(focusId);
      setHighlightedIds(new Set([focusId]));
    }
  }, [searchParams]);

  // --- NODE CLICK ---
  const onNodeClick = useCallback((event: React.MouseEvent, node: Node) => {
    setSelectedEdgeId(null);
    if (event.ctrlKey || event.metaKey) {
      // Ctrl/Cmd+click: toggle node in chat context
      setChatContextIds((prev) =>
        prev.includes(node.id) ? prev.filter((id) => id !== node.id) : [...prev, node.id],
      );
    } else {
      // Regular click: preview this node (doesn't affect chat context)
      setPreviewNodeId((prev) => (prev === node.id ? null : node.id));
    }
  }, []);

  const onNodeDoubleClick = useCallback(
    (_: React.MouseEvent, node: Node) => {
      const d = node.data as unknown as GraphDataNode;
      navigate(`/projects/${projectId}/trail/${d.node_type}/${d.node_id}`, {
        state: { from: "graph" },
      });
    },
    [navigate, projectId],
  );

  const onPaneClick = useCallback(() => {
    setPreviewNodeId(null);
    setSelectedEdgeId(null);
  }, []);

  // --- EDGE CLICK ---
  const onEdgeClick = useCallback((event: React.MouseEvent, edge: Edge) => {
    setPreviewNodeId(null);
    setSelectedEdgeId((prev) => (prev === edge.id ? null : edge.id));
    setEdgePopoverPosition({ x: event.clientX - 112, y: event.clientY + 8 });
  }, []);

  // --- CONNECT ---
  const onConnect = useCallback((params: Connection) => {
    if (params.source && params.target && params.source !== params.target) {
      setPendingConnection({ source: params.source, target: params.target });
    }
  }, []);

  const handleConnectionConfirm = useCallback(
    async (kind: string, reason: string) => {
      if (!pendingConnection) return;
      await api.createGraphEdge(projectId, {
        from_node_type: parseNodeType(pendingConnection.source),
        from_node_id: parseNodeId(pendingConnection.source),
        to_node_type: parseNodeType(pendingConnection.target),
        to_node_id: parseNodeId(pendingConnection.target),
        kind,
        metadata: { created_by: "human", ...(reason ? { reason } : {}) },
      });
      setPendingConnection(null);
      const data = await refreshGraphData();
      await layoutAndSetNodes(data, visibleTypes, highlightedIds, chatContextIds);
      setTimeout(() => fitView({ padding: 0.1, duration: 300 }), 100);
    },
    [pendingConnection, projectId, visibleTypes, highlightedIds, chatContextIds],
  );

  const handleEdgeDelete = useCallback(async () => {
    setSelectedEdgeId(null);
    setEdgePopoverPosition(null);
    const data = await refreshGraphData();
    await layoutAndSetNodes(data, visibleTypes, highlightedIds, chatContextIds);
    setTimeout(() => fitView({ padding: 0.1, duration: 300 }), 100);
  }, [visibleTypes, highlightedIds, chatContextIds]);

  const handleToggleType = useCallback((type: string) => {
    setVisibleTypes((prev) => {
      const next = new Set(prev);
      if (next.has(type)) next.delete(type);
      else next.add(type);
      return next;
    });
  }, []);

  const handleGraphCommand = useCallback(
    (command: {
      type: string;
      nodeIds?: string[];
      nodeId?: string;
      fromId?: string;
      toId?: string;
      rootId?: string;
      centerId?: string;
      leftId?: string;
      rightId?: string;
      label?: string;
    }) => {
      switch (command.type) {
        case "highlight":
          if (command.nodeIds) setHighlightedIds(new Set(command.nodeIds));
          break;
        case "reset":
          setHighlightedIds(new Set());
          setSearchQuery("");
          setActiveSmartView(null);
          setLineageTargetId(null);
          setComposedSpec(null);
          setViewMode({ kind: "default" });
          break;
        case "focus":
          if (command.nodeId) {
            setPreviewNodeId(command.nodeId);
            setHighlightedIds(new Set([command.nodeId]));
          }
          break;
        case "node_created":
          refreshGraphData();
          break;
        // Graph-Opt §8
        case "show_lineage":
          if (command.nodeId) {
            const node = graphData?.nodes.find((n) => n.id === command.nodeId);
            if (node) {
              setLineageTargetId(command.nodeId);
              setComposedSpec(null);
              setViewMode({ kind: "lineage", targetTitle: node.title });
            }
          }
          break;
        // Graph-Opt §9 — Composed Views
        case "compose_path":
          if (command.fromId && command.toId) {
            setLineageTargetId(null);
            setComposedSpec({ kind: "path", fromId: command.fromId, toId: command.toId });
            setViewMode({ kind: "composed", label: command.label ?? "Path" });
          }
          break;
        case "compose_radial":
          if (command.centerId) {
            setLineageTargetId(null);
            setComposedSpec({ kind: "radial", centerId: command.centerId });
            setViewMode({ kind: "composed", label: command.label ?? "Radial" });
          }
          break;
        case "compose_tree":
          if (command.rootId) {
            setLineageTargetId(null);
            setComposedSpec({ kind: "tree", rootId: command.rootId });
            setViewMode({ kind: "composed", label: command.label ?? "Tree" });
          }
          break;
        case "compose_comparison":
          if (command.leftId && command.rightId) {
            setLineageTargetId(null);
            setComposedSpec({
              kind: "comparison",
              leftId: command.leftId,
              rightId: command.rightId,
            });
            setViewMode({ kind: "composed", label: command.label ?? "Comparison" });
          }
          break;
      }
    },
    [refreshGraphData, graphData],
  );

  // --- "CHAT ABOUT THIS" from node detail ---
  const handleChatAbout = useCallback(
    (node: GraphDataNode) => {
      setChatContextIds((prev) =>
        prev.includes(node.id)
          ? prev.filter((id) => id !== node.id)
          : [...prev, node.id],
      );
    },
    [],
  );

  // --- DERIVED ---
  // Chat context nodes (for the input context bar)
  const chatContextNodes = useMemo(() => {
    if (!graphData) return [];
    return chatContextIds
      .map((id) => graphData.nodes.find((n) => n.id === id))
      .filter((n): n is GraphDataNode => n != null);
  }, [chatContextIds, graphData]);

  // Preview node (for the detail popover)
  const previewNode = useMemo(() => {
    if (!previewNodeId || !graphData) return null;
    return graphData.nodes.find((n) => n.id === previewNodeId) ?? null;
  }, [previewNodeId, graphData]);

  const selectedEdge = useMemo(() => {
    if (!selectedEdgeId || !graphData) return null;
    return graphData.edges.find((e) => String(e.id) === selectedEdgeId) ?? null;
  }, [selectedEdgeId, graphData]);

  // Compute preview node screen position for detail popover
  const previewNodeScreenPos = useMemo(() => {
    if (!previewNode) return { x: 0, y: 0 };
    const layoutNode = nodes.find((n) => n.id === previewNode.id);
    if (!layoutNode) return { x: 0, y: 0 };
    return {
      x: layoutNode.position.x * viewport.zoom + viewport.x,
      y: layoutNode.position.y * viewport.zoom + viewport.y,
    };
  }, [previewNode, nodes, viewport]);

  const containerWidth = containerRef.current?.offsetWidth ?? 1200;
  const containerHeight = containerRef.current?.offsetHeight ?? 800;

  const pendingSourceNode =
    pendingConnection && graphData
      ? graphData.nodes.find((n) => n.id === pendingConnection.source)
      : null;
  const pendingTargetNode =
    pendingConnection && graphData
      ? graphData.nodes.find((n) => n.id === pendingConnection.target)
      : null;

  const graphChatValue = useMemo(
    () => ({
      contextNodes: chatContextNodes,
      previewNode,
      onClearContext: () => setChatContextIds([]),
      onRemoveContext: (id: string) =>
        setChatContextIds((prev) => prev.filter((i) => i !== id)),
      onGraphCommand: (cmd: GraphCommand) =>
        handleGraphCommand(cmd as Parameters<typeof handleGraphCommand>[0]),
    }),
    [chatContextNodes, previewNode, handleGraphCommand],
  );

  if (loading) {
    return (
      <div className="flex h-full items-center justify-center">
        <Skeleton className="h-96 w-96 rounded-xl" />
      </div>
    );
  }

  return (
    <LayoutControlsContext.Provider value={{ toggleGroup }}>
    <GraphChatProvider value={graphChatValue}>
    <div ref={containerRef} className="relative h-full w-full overflow-hidden">
      <ArrowMarker />

      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onNodeClick={onNodeClick}
        onNodeDoubleClick={onNodeDoubleClick}
        onPaneClick={onPaneClick}
        onEdgeClick={onEdgeClick}
        onConnect={onConnect}
        nodeTypes={nodeTypes}
        edgeTypes={edgeTypes}
        fitView
        minZoom={0.1}
        maxZoom={3}
        proOptions={{ hideAttribution: true }}
        edgesReconnectable={false}
        nodesDraggable={false}
        onlyRenderVisibleElements
      >
        <Background gap={24} size={1} color="hsl(var(--border))" />
        <Controls position="bottom-left" showInteractive={false} />
        <MiniMap
          position="bottom-right"
          style={{ bottom: 80, right: 16 }}
          nodeColor={(node) =>
            (node.data as { color?: string })?.color ?? "#6b7280"
          }
          maskColor="rgba(0,0,0,0.08)"
        />
      </ReactFlow>

      {/* View mode toolbar — top center (Lineage / Composed view exit) */}
      <GraphViewModeToolbar
        mode={viewMode}
        onExit={() => {
          setViewMode({ kind: "default" });
          setLineageTargetId(null);
          setComposedSpec(null);
          setTimeout(() => fitView({ padding: 0.1, duration: 300 }), 50);
        }}
      />

      {/* Smart views — top left */}
      <div className="absolute left-4 top-4 z-10">
        <GraphSmartViewSelector
          active={activeSmartView}
          onChange={handleSmartViewChange}
          nodeCount={graphData?.nodes.length ?? 0}
        />
      </div>

      {/* Filter chips + search — top right */}
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
      </div>

      {/* Chat is now hosted by the shared AgentChatPane in app-layout.tsx.
          Graph-specific context (selected nodes, preview, onGraphCommand) is
          exposed via <GraphChatProvider> at the outer component. */}

      {/* Node detail — anchored near node */}
      {previewNode && graphData && (
        <GraphNodeDetail
          node={previewNode}
          graphData={graphData}
          projectId={projectId}
          nodeScreenPosition={previewNodeScreenPos}
          containerWidth={containerWidth}
          containerHeight={containerHeight}
          onClose={() => setPreviewNodeId(null)}
          onOpenTrail={(nodeType, nodeId) => {
            navigate(`/projects/${projectId}/trail/${nodeType}/${nodeId}`, {
              state: { from: "graph" },
            });
          }}
          onOpenWhy={(nodeType, nodeId) => setWhyTarget({ nodeType, nodeId })}
          onHighlightConnections={(nodeIds) => setHighlightedIds(new Set(nodeIds))}
          onChatAbout={handleChatAbout}
          onShowLineage={(nodeId) => {
            const n = graphData?.nodes.find((gn) => gn.id === nodeId);
            if (n) {
              setLineageTargetId(nodeId);
              setComposedSpec(null);
              setViewMode({ kind: "lineage", targetTitle: n.title });
            }
          }}
          onOpenSource={(sourceId) =>
            navigate(`/projects/${projectId}/library?source=${sourceId}`)
          }
          isInChatContext={chatContextIds.includes(previewNode?.id ?? "")}
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

      {/* Connection dialog */}
      {pendingConnection && pendingSourceNode && pendingTargetNode && (
        <ConnectionDialog
          sourceNode={pendingSourceNode}
          targetNode={pendingTargetNode}
          onConfirm={handleConnectionConfirm}
          onCancel={() => setPendingConnection(null)}
        />
      )}

      {/* Edge detail popover */}
      {selectedEdge && edgePopoverPosition && graphData && (
        <EdgeDetailPopover
          edgeId={selectedEdge.id}
          kind={selectedEdge.kind}
          sourceTitle={
            graphData.nodes.find((n) => n.id === selectedEdge.source)?.title ?? selectedEdge.source
          }
          targetTitle={
            graphData.nodes.find((n) => n.id === selectedEdge.target)?.title ?? selectedEdge.target
          }
          projectId={projectId}
          position={edgePopoverPosition}
          onClose={() => {
            setSelectedEdgeId(null);
            setEdgePopoverPosition(null);
          }}
          onDelete={handleEdgeDelete}
        />
      )}

      {/* Spotlight search */}
      <GraphSpotlight
        open={spotlightOpen}
        onClose={() => {
          setSpotlightOpen(false);
          handleSearch("");
        }}
        nodes={graphData?.nodes ?? []}
        onFocusNode={(nodeId) => {
          setPreviewNodeId(nodeId);
          setHighlightedIds(new Set([nodeId]));
          const layoutNode = nodes.find((n) => n.id === nodeId);
          if (layoutNode) {
            fitView({ nodes: [{ id: nodeId }], padding: 0.5, duration: 500 });
          }
        }}
        onSmartView={handleSmartViewChange}
        onFitToScreen={() => fitView({ padding: 0.1, duration: 300 })}
        onSearch={handleSearch}
      />
    </div>
    </GraphChatProvider>
    </LayoutControlsContext.Provider>
  );
}

export function GraphView({ projectId }: { projectId: number }) {
  return (
    <ReactFlowProvider>
      <GraphViewInner projectId={projectId} />
    </ReactFlowProvider>
  );
}
