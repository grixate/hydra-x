import { useState, useEffect } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { api } from "@/lib/api";
import type { Strategy } from "@/types";
import { NodeList } from "@/components/shared/node-list";
import { StatusBadge } from "@/components/shared/status-badge";
import { TrailLink } from "@/components/trail/trail-link";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

export function StrategiesPage() {
  const { projectId } = useParams<{ projectId: string }>();
  const navigate = useNavigate();
  const [strategies, setStrategies] = useState<Strategy[]>([]);
  const [selected, setSelected] = useState<Strategy | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!projectId) return;
    setLoading(true);
    api.listStrategies(Number(projectId)).then(setStrategies).finally(() => setLoading(false));
  }, [projectId]);

  if (loading) {
    return <div className="space-y-4 p-6"><Skeleton className="h-8 w-48" /><Skeleton className="h-24 w-full" /></div>;
  }

  return (
    <div className="p-6">
      <h1 className="font-display text-xl font-semibold mb-6">Strategies</h1>
      <div className="grid gap-6 xl:grid-cols-[360px_minmax(0,1fr)]">
        <NodeList
          items={strategies}
          nodeType="strategy"
          selectedId={selected?.id}
          onSelect={setSelected}
          emptyMessage="No strategies defined yet. Strategies emerge when you group related decisions into a coherent direction."
        />
        {selected ? (
          <Card>
            <CardHeader className="pb-2">
              <div className="flex items-start justify-between gap-2">
                <CardTitle className="text-base">{selected.title}</CardTitle>
                <StatusBadge status={selected.status} />
              </div>
            </CardHeader>
            <CardContent className="space-y-4">
              <p className="whitespace-pre-wrap text-sm">{selected.body}</p>
              <TrailLink nodeType="strategy" nodeId={selected.id} title="View full trail"
                onClick={(type, id) => navigate(`/product/${projectId}/trail/${type}/${id}`)} />
            </CardContent>
          </Card>
        ) : (
          <Card><CardContent className="py-12 text-center text-sm text-[var(--ink-soft)]">Select a strategy.</CardContent></Card>
        )}
      </div>
    </div>
  );
}
