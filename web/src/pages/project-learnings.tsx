import { useState, useEffect } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { api } from "@/lib/api";
import type { Learning } from "@/types";
import { NodeList } from "@/components/shared/node-list";
import { StatusBadge } from "@/components/shared/status-badge";
import { TrailLink } from "@/components/trail/trail-link";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";

export function LearningsPage() {
  const { projectId } = useParams<{ projectId: string }>();
  const navigate = useNavigate();
  const [learnings, setLearnings] = useState<Learning[]>([]);
  const [selected, setSelected] = useState<Learning | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!projectId) return;
    setSelected(null);
    setLoading(true);
    setError(null);
    api.listLearnings(Number(projectId))
      .then(setLearnings)
      .catch((err) => setError(err.message ?? "Failed to load"))
      .finally(() => setLoading(false));
  }, [projectId]);

  if (error) {
    return <div className="p-6"><Card><CardContent className="py-8 text-center text-sm text-[var(--ink-soft)]">{error}</CardContent></Card></div>;
  }

  if (loading) {
    return <div className="space-y-4 p-6"><Skeleton className="h-8 w-48" /><Skeleton className="h-24 w-full" /></div>;
  }

  return (
    <div className="p-6">
      <h1 className="font-display text-xl font-semibold mb-6">Learnings</h1>
      <div className="grid gap-6 xl:grid-cols-[360px_minmax(0,1fr)]">
        <NodeList
          items={learnings}
          nodeType="learning"
          selectedId={selected?.id}
          onSelect={setSelected}
          emptyMessage="No learnings yet. After you ship, capture what you learned — these feed back into the product graph to improve future decisions."
        />
        {selected ? (
          <Card>
            <CardHeader className="pb-2">
              <div className="flex items-start justify-between gap-2">
                <CardTitle className="text-base">{selected.title}</CardTitle>
                <div className="flex gap-1">
                  <Badge variant="secondary" className="text-[9px]">{selected.learning_type.replace(/_/g, " ")}</Badge>
                  <StatusBadge status={selected.status} />
                </div>
              </div>
            </CardHeader>
            <CardContent className="space-y-4">
              <p className="whitespace-pre-wrap text-sm">{selected.body}</p>
              <TrailLink nodeType="learning" nodeId={selected.id} title="View full trail"
                onClick={(type, id) => navigate(`/product/${projectId}/trail/${type}/${id}`)} />
            </CardContent>
          </Card>
        ) : (
          <Card><CardContent className="py-12 text-center text-sm text-[var(--ink-soft)]">Select a learning.</CardContent></Card>
        )}
      </div>
    </div>
  );
}
