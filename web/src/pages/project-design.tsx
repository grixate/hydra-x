import { useState, useEffect, useMemo } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { api } from "@/lib/api";
import type { DesignNode } from "@/types";
import { NodeList } from "@/components/shared/node-list";
import { StatusBadge } from "@/components/shared/status-badge";
import { TrailLink } from "@/components/trail/trail-link";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";

const typeGroups = [
  { key: "user_flow", label: "User Flows" },
  { key: "interaction_pattern", label: "Interaction Patterns" },
  { key: "component_spec", label: "Component Specs" },
  { key: "design_rationale", label: "Design Rationale" },
];

export function DesignPage() {
  const { projectId } = useParams<{ projectId: string }>();
  const navigate = useNavigate();
  const [nodes, setNodes] = useState<DesignNode[]>([]);
  const [selected, setSelected] = useState<DesignNode | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!projectId) return;
    setLoading(true);
    api.listDesignNodes(Number(projectId)).then(setNodes).finally(() => setLoading(false));
  }, [projectId]);

  const grouped = useMemo(() => {
    const map: Record<string, DesignNode[]> = {};
    for (const g of typeGroups) map[g.key] = [];
    for (const n of nodes) (map[n.node_type] ??= []).push(n);
    return map;
  }, [nodes]);

  if (loading) {
    return <div className="space-y-4 p-6"><Skeleton className="h-8 w-48" /><Skeleton className="h-24 w-full" /></div>;
  }

  return (
    <div className="p-6">
      <h1 className="font-display text-xl font-semibold mb-6">Design</h1>
      {nodes.length === 0 ? (
        <Card><CardContent className="py-12 text-center text-sm text-[var(--ink-soft)]">
          No design specifications yet. Chat with the designer agent to start specifying user experiences.
        </CardContent></Card>
      ) : (
        <div className="grid gap-6 xl:grid-cols-[360px_minmax(0,1fr)]">
          <div className="space-y-4">
            {typeGroups.map((g) => {
              const items = grouped[g.key];
              if (!items || items.length === 0) return null;
              return (
                <div key={g.key}>
                  <p className="px-1 pb-1 text-[10px] font-bold uppercase tracking-[0.3em] text-[var(--ink-soft)]">{g.label}</p>
                  <NodeList items={items} nodeType="design_node" selectedId={selected?.id} onSelect={setSelected} />
                </div>
              );
            })}
          </div>
          {selected ? (
            <Card>
              <CardHeader className="pb-2">
                <div className="flex items-start justify-between gap-2">
                  <CardTitle className="text-base">{selected.title}</CardTitle>
                  <div className="flex gap-1">
                    <Badge variant="secondary" className="text-[9px]">{selected.node_type.replace(/_/g, " ")}</Badge>
                    <StatusBadge status={selected.status} />
                  </div>
                </div>
              </CardHeader>
              <CardContent className="space-y-4">
                <p className="whitespace-pre-wrap text-sm">{selected.body}</p>
                <TrailLink nodeType="design_node" nodeId={selected.id} title="View full trail"
                  onClick={(type, id) => navigate(`/product/${projectId}/trail/${type}/${id}`)} />
              </CardContent>
            </Card>
          ) : (
            <Card><CardContent className="py-12 text-center text-sm text-[var(--ink-soft)]">Select a node.</CardContent></Card>
          )}
        </div>
      )}
    </div>
  );
}
