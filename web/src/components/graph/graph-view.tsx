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
import type { GraphData, GraphDataNode } from "@/types";
import { computeLayout } from "./graph-layout";
import { GraphCustomNode } from "./graph-custom-node";
import { GraphCustomEdge } from "./graph-custom-edge";
import { GraphSmartViewSelector } from "./graph-smart-view-selector";
import { GraphFilterChips } from "./graph-filter-chips";
import { GraphSpotlight, SpotlightTrigger } from "./graph-spotlight";
import { UniversalInput } from "@/components/chat/universal-input";
import { GraphChatCard } from "@/components/chat/chat-card";
import { GraphNodeDetail } from "./graph-node-detail";
import { ConnectionDialog } from "./connection-dialog";
import { EdgeDetailPopover } from "./edge-detail-popover";
import { FILTERABLE_NODE_TYPES } from "./graph-constants";
import { applySmartView, type SmartView } from "./graph-smart-views";
import { Skeleton } from "@/components/ui/skeleton";
import type { ChatTab } from "@/components/chat/chat-tabs";

const nodeTypes = { graphNode: GraphCustomNode };
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
  const [loading, setLoading] = useState(true);
  const [nodes, setNodes, onNodesChange] = useNodesState([] as Node[]);
  const [edges, setEdges, onEdgesChange] = useEdgesState([] as Edge[]);

  // Selection — detail preview (single node being inspected)
  const [previewNodeId, setPreviewNodeId] = useState<string | null>(null);
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

  // Chat — multi-tab state
  const [chatTabs, setChatTabs] = useState<ChatTab[]>([
    { agent: "memory", conversationId: null, messages: [], unread: 0 },
  ]);
  const [activeTabIndex, setActiveTabIndex] = useState(0);
  const [chatCardOpen, setChatCardOpen] = useState(false);
  const [chatCardMinimized, setChatCardMinimized] = useState(false);

  // Spotlight
  const [spotlightOpen, setSpotlightOpen] = useState(false);

  // ⌘K shortcut
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault();
        setSpotlightOpen((prev) => !prev);
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, []);

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

  const activeTab = chatTabs[activeTabIndex];

  // --- DATA FETCH ---
  const refreshGraphData = useCallback(async () => {
    const data = await api.getGraphData(projectId);
    setGraphData(data);
    return data;
  }, [projectId]);

  useEffect(() => {
    setLoading(true);
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

  useEffect(() => {
    if (!graphData) return;
    layoutAndSetNodes(graphData, visibleTypes, highlightedIds, chatContextIds).then(() => {
      setTimeout(() => fitView({ padding: 0.1, duration: 300 }), 100);
    });
  }, [visibleTypes]);

  useEffect(() => {
    if (!graphData) return;
    setNodes((prev) =>
      prev.map((n) => ({
        ...n,
        data: {
          ...n.data,
          highlighted: highlightedIds.size > 0 && highlightedIds.has(n.id),
          dimmed: highlightedIds.size > 0 && !highlightedIds.has(n.id),
          multiSelected: chatContextIds.includes(n.id),
          previewing: n.id === previewNodeId,
        },
      })),
    );
  }, [highlightedIds, chatContextIds, previewNodeId]);

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
    const { nodes: layoutNodes, edges: layoutEdges } = await computeLayout(
      visibleNodes,
      visibleEdges,
    );
    const finalNodes = layoutNodes.map((n) => ({
      ...n,
      data: {
        ...n.data,
        highlighted: highlighted.size > 0 && highlighted.has(n.id),
        dimmed: highlighted.size > 0 && !highlighted.has(n.id),
        multiSelected: selected.includes(n.id),
      },
    }));
    setNodes(finalNodes);
    setEdges(layoutEdges);
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
      navigate(`/projects/${projectId}/trail/${d.node_type}/${d.node_id}`);
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

  // --- CHAT (multi-tab) ---
  const handleChatSubmit = useCallback(
    async (message: string, _agent: string, contextNodeIds: string[]) => {
      if (!chatCardOpen) setChatCardOpen(true);
      if (chatCardMinimized) setChatCardMinimized(false);

      const now = new Date().toISOString();
      // Add user message to active tab
      setChatTabs((prev) => {
        const next = [...prev];
        next[activeTabIndex] = {
          ...next[activeTabIndex],
          messages: [...next[activeTabIndex].messages, { role: "user", content: message, timestamp: now }],
          unread: 0,
        };
        return next;
      });

      // Send to API
      try {
        let convId = chatTabs[activeTabIndex].conversationId;
        if (!convId) {
          const conv = await api.createConversation(projectId, {
            persona: chatTabs[activeTabIndex].agent,
            title: "Graph exploration",
          });
          convId = conv.id;
          setChatTabs((prev) => {
            const next = [...prev];
            next[activeTabIndex] = { ...next[activeTabIndex], conversationId: convId };
            return next;
          });
        }

        const result = await api.sendConversationMessage(projectId, convId, message);
        const responseNow = new Date().toISOString();

        if (result.response?.content) {
          setChatTabs((prev) => {
            const next = [...prev];
            const isMinimized = chatCardMinimized;
            next[activeTabIndex] = {
              ...next[activeTabIndex],
              messages: [
                ...next[activeTabIndex].messages,
                { role: "assistant", content: result.response.content!, timestamp: responseNow },
              ],
              unread: isMinimized ? next[activeTabIndex].unread + 1 : 0,
            };
            return next;
          });
        }
      } catch {
        const errorNow = new Date().toISOString();
        setChatTabs((prev) => {
          const next = [...prev];
          next[activeTabIndex] = {
            ...next[activeTabIndex],
            messages: [
              ...next[activeTabIndex].messages,
              { role: "assistant", content: "Sorry, something went wrong.", timestamp: errorNow },
            ],
          };
          return next;
        });
      }
    },
    [chatCardOpen, chatCardMinimized, activeTabIndex, chatTabs, projectId],
  );

  const handleAgentChange = useCallback(
    (agent: string) => {
      // Find existing tab for this agent or create one
      const existingIdx = chatTabs.findIndex((t) => t.agent === agent);
      if (existingIdx >= 0) {
        setActiveTabIndex(existingIdx);
      } else {
        setChatTabs((prev) => [
          ...prev,
          { agent, conversationId: null, messages: [], unread: 0 },
        ]);
        setActiveTabIndex(chatTabs.length);
      }
    },
    [chatTabs],
  );

  const handleAddTab = useCallback(
    (agent: string) => {
      setChatTabs((prev) => [
        ...prev,
        { agent, conversationId: null, messages: [], unread: 0 },
      ]);
      setActiveTabIndex(chatTabs.length);
      if (!chatCardOpen) setChatCardOpen(true);
      if (chatCardMinimized) setChatCardMinimized(false);
    },
    [chatTabs.length, chatCardOpen, chatCardMinimized],
  );

  const handleTabClick = useCallback((index: number) => {
    setActiveTabIndex(index);
    setChatTabs((prev) => {
      const next = [...prev];
      next[index] = { ...next[index], unread: 0 };
      return next;
    });
  }, []);

  const handleGraphCommand = useCallback(
    (command: { type: string; nodeIds?: string[]; nodeId?: string }) => {
      switch (command.type) {
        case "highlight":
          if (command.nodeIds) setHighlightedIds(new Set(command.nodeIds));
          break;
        case "reset":
          setHighlightedIds(new Set());
          setSearchQuery("");
          setActiveSmartView(null);
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
      }
    },
    [refreshGraphData],
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

  if (loading) {
    return (
      <div className="flex h-full items-center justify-center">
        <Skeleton className="h-96 w-96 rounded-xl" />
      </div>
    );
  }

  return (
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
        <GraphFilterChips visibleTypes={visibleTypes} onToggle={handleToggleType} />
        <SpotlightTrigger onClick={() => setSpotlightOpen(true)} />
      </div>

      {/* Chat input — bottom center */}
      <UniversalInput
        surface="graph"
        projectId={projectId}
        onSubmit={handleChatSubmit}
        currentAgent={activeTab?.agent ?? "memory"}
        onAgentChange={handleAgentChange}
        selectedNodes={chatContextNodes}
        previewNode={previewNode}
        onClearSelection={() => setChatContextIds([])}
        onRemoveNode={(id) => setChatContextIds((prev) => prev.filter((i) => i !== id))}
      />

      {/* Chat card — bottom right */}
      {chatCardOpen && (
        <GraphChatCard
          tabs={chatTabs}
          activeIndex={activeTabIndex}
          minimized={chatCardMinimized}
          onTabClick={handleTabClick}
          onAddTab={handleAddTab}
          onMinimize={() => setChatCardMinimized((prev) => !prev)}
          onClose={() => setChatCardOpen(false)}
          onGraphCommand={handleGraphCommand}
        />
      )}

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
            navigate(`/projects/${projectId}/trail/${nodeType}/${nodeId}`);
          }}
          onHighlightConnections={(nodeIds) => setHighlightedIds(new Set(nodeIds))}
          onChatAbout={handleChatAbout}
          isInChatContext={chatContextIds.includes(previewNode?.id ?? "")}
        />
      )}

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
  );
}

export function GraphView({ projectId }: { projectId: number }) {
  return (
    <ReactFlowProvider>
      <GraphViewInner projectId={projectId} />
    </ReactFlowProvider>
  );
}
