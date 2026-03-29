import { useState, useEffect, useCallback, useMemo } from "react";
import { useParams, useNavigate } from "react-router-dom";
import {
  ReactFlow,
  Background,
  Controls,
  MiniMap,
  useNodesState,
  useEdgesState,
  type Node,
  type Edge,
  type NodeMouseHandler,
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";
import { api } from "@/lib/api";
import { GraphNodeComponent } from "@/components/graph/graph-node";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardContent } from "@/components/ui/card";
import { cn } from "@/lib/utils";

const nodeTypeColors: Record<string, string> = {
  source: "#71717a",
  signal: "#71717a",
  insight: "#3b82f6",
  decision: "#f59e0b",
  strategy: "#14b8a6",
  requirement: "#22c55e",
  architecture_node: "#64748b",
  design_node: "#8b5cf6",
  task: "#f97316",
  learning: "#10b981",
  constraint: "#ef4444",
  routine: "#6366f1",
  knowledge_entry: "#06b6d4",
};

const nodeTypes = { graphNode: GraphNodeComponent };

const edgeStyles: Record<string, Partial<Edge>> = {
  lineage: { style: { stroke: "#94a3b8", strokeWidth: 2 }, animated: false },
  supports: { style: { stroke: "#86efac", strokeWidth: 1 } },
  contradicts: { style: { stroke: "#fca5a5", strokeWidth: 2, strokeDasharray: "5 5" } },
  supersedes: { style: { stroke: "#cbd5e1", strokeWidth: 1, strokeDasharray: "3 3" } },
  blocks: { style: { stroke: "#f87171", strokeWidth: 3 } },
  enables: { style: { stroke: "#4ade80", strokeWidth: 2 } },
  constrains: { style: { stroke: "#f87171", strokeWidth: 1, strokeDasharray: "4 2" } },
  dependency: { style: { stroke: "#a78bfa", strokeWidth: 1 } },
};

const allNodeTypes = Object.keys(nodeTypeColors);

export function GraphPage() {
  const { projectId } = useParams<{ projectId: string }>();
  const navigate = useNavigate();
  const [nodes, setNodes, onNodesChange] = useNodesState([] as Node[]);
  const [edges, setEdges, onEdgesChange] = useEdgesState([] as Edge[]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [visibleTypes, setVisibleTypes] = useState<Set<string>>(new Set(allNodeTypes));

  useEffect(() => {
    if (!projectId) return;
    setLoading(true);
    api.getGraphNodes(Number(projectId)).then((data) => {
      // Layout nodes in a force-directed-like grid
      const rfNodes: Node[] = data.nodes.map((n, i) => {
        const cols = Math.ceil(Math.sqrt(data.nodes.length));
        const row = Math.floor(i / cols);
        const col = i % cols;
        return {
          id: n.id,
          type: "graphNode",
          position: { x: col * 220 + Math.random() * 40, y: row * 120 + Math.random() * 30 },
          data: {
            label: n.title,
            nodeType: n.node_type,
            status: n.status,
            dbId: n.db_id,
            color: nodeTypeColors[n.node_type] ?? "#94a3b8",
          },
        };
      });

      const rfEdges: Edge[] = data.edges.map((e) => ({
        id: e.id,
        source: e.source,
        target: e.target,
        label: e.kind,
        ...(edgeStyles[e.kind] ?? edgeStyles.lineage),
      }));

      setNodes(rfNodes);
      setEdges(rfEdges);
    }).finally(() => setLoading(false));
  }, [projectId]);

  const filteredNodes = useMemo(() => {
    return nodes.map((n) => {
      const nodeType = n.data.nodeType as string;
      const label = (n.data.label as string).toLowerCase();
      const matchesType = visibleTypes.has(nodeType);
      const matchesSearch = !search || label.includes(search.toLowerCase());
      return {
        ...n,
        hidden: !matchesType || !matchesSearch,
        style: {
          ...n.style,
          opacity: matchesType && matchesSearch ? 1 : 0.15,
        },
      };
    });
  }, [nodes, visibleTypes, search]);

  const onNodeDoubleClick: NodeMouseHandler = useCallback(
    (_event, node) => {
      const { nodeType, dbId } = node.data as { nodeType: string; dbId: number };
      navigate(`/projects/${projectId}/trail/${nodeType}/${dbId}`);
    },
    [navigate, projectId],
  );

  function toggleType(type: string) {
    setVisibleTypes((prev) => {
      const next = new Set(prev);
      if (next.has(type)) next.delete(type);
      else next.add(type);
      return next;
    });
  }

  if (loading) {
    return (
      <div className="flex h-full items-center justify-center">
        <Skeleton className="h-96 w-96 rounded-xl" />
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col">
      {/* Toolbar */}
      <div className="flex shrink-0 items-center gap-2 border-b px-4 py-2 overflow-x-auto">
        <Input
          placeholder="Search nodes..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="w-48 text-sm"
        />
        <div className="flex gap-1">
          {allNodeTypes
            .filter((t) => !["signal", "routine", "knowledge_entry"].includes(t))
            .map((type) => (
              <Button
                key={type}
                variant={visibleTypes.has(type) ? "default" : "outline"}
                size="sm"
                className="text-[10px] px-2 py-0.5 h-6"
                onClick={() => toggleType(type)}
              >
                <span
                  className="mr-1 inline-block h-2 w-2 rounded-full"
                  style={{ backgroundColor: nodeTypeColors[type] }}
                />
                {type.replace(/_/g, " ")}
              </Button>
            ))}
        </div>
      </div>

      {/* Graph */}
      <div className="flex-1">
        <ReactFlow
          nodes={filteredNodes}
          edges={edges}
          onNodesChange={onNodesChange}
          onEdgesChange={onEdgesChange}
          onNodeDoubleClick={onNodeDoubleClick}
          nodeTypes={nodeTypes}
          fitView
          proOptions={{ hideAttribution: true }}
        >
          <Background />
          <Controls />
          <MiniMap
            nodeColor={(n) => (n.data as { color: string }).color ?? "#94a3b8"}
            maskColor="rgba(0,0,0,0.08)"
          />
        </ReactFlow>
      </div>
    </div>
  );
}
