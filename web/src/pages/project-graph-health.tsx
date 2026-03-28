import { useState, useEffect } from "react";
import { useParams } from "react-router-dom";
import { api } from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";

export function GraphHealthPage() {
  const { projectId } = useParams<{ projectId: string }>();
  const [health, setHealth] = useState<Record<string, unknown> | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!projectId) return;
    setLoading(true);
    setError(null);
    api.getGraphHealth(Number(projectId))
      .then(setHealth)
      .catch((err) => setError(err.message ?? "Failed to load"))
      .finally(() => setLoading(false));
  }, [projectId]);

  if (error) {
    return <div className="p-6"><Card><CardContent className="py-8 text-center text-sm text-[var(--ink-soft)]">{error}</CardContent></Card></div>;
  }

  if (loading || !health) {
    return (
      <div className="space-y-4 p-6">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-32 w-full" />
        <Skeleton className="h-32 w-full" />
      </div>
    );
  }

  const density = (health.density ?? {}) as Record<string, { count: number; outgoing: number; avg_outgoing: number }>;
  const openFlagCount = (health.open_flag_count ?? 0) as number;
  const orphanCount = (health.orphan_count ?? 0) as number;
  const staleCount = (health.stale_count ?? 0) as number;

  const totalNodes = Object.values(density).reduce((sum, d) => sum + (d.count || 0), 0);
  const flagged = openFlagCount;
  const score = totalNodes > 0 ? Math.round(((totalNodes - flagged) / totalNodes) * 100) : 100;
  const scoreColor = score > 80 ? "text-emerald-600" : score > 60 ? "text-yellow-600" : "text-red-600";

  return (
    <div className="p-6 space-y-6">
      <h1 className="font-display text-xl font-semibold">Graph Health</h1>

      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardContent className="py-6 text-center">
            <p className={cn("text-4xl font-bold font-display", scoreColor)}>{score}%</p>
            <p className="text-xs text-[var(--ink-soft)] mt-1">Coherence Score</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="py-6 text-center">
            <p className="text-4xl font-bold font-display">{totalNodes}</p>
            <p className="text-xs text-[var(--ink-soft)] mt-1">Total Nodes</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="py-6 text-center">
            <p className="text-4xl font-bold font-display">{openFlagCount}</p>
            <p className="text-xs text-[var(--ink-soft)] mt-1">Open Flags</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader><CardTitle className="text-sm">Coverage</CardTitle></CardHeader>
        <CardContent className="space-y-3">
          {Object.entries(density).map(([type, data]) => (
            <div key={type} className="flex items-center gap-3">
              <span className="w-36 text-xs text-[var(--ink-soft)] truncate">{type.replace(/_/g, " ")}</span>
              <div className="flex-1 h-3 rounded-full bg-[var(--line)] overflow-hidden">
                <div
                  className="h-full rounded-full bg-[var(--accent)]"
                  style={{ width: `${Math.min(100, (data.count / Math.max(totalNodes, 1)) * 300)}%` }}
                />
              </div>
              <span className="text-xs font-medium w-8 text-right">{data.count}</span>
              <span className="text-[10px] text-[var(--ink-soft)] w-20">avg {data.avg_outgoing ?? 0} edges</span>
            </div>
          ))}
        </CardContent>
      </Card>

      <div className="grid gap-4 md:grid-cols-3">
        <FlagCard label="Orphaned" count={orphanCount} />
        <FlagCard label="Stale" count={staleCount} />
        <FlagCard label="Needs Review" count={openFlagCount} />
      </div>
    </div>
  );
}

function FlagCard({ label, count }: { label: string; count: number }) {
  return (
    <Card>
      <CardContent className="flex items-center justify-between py-4">
        <span className="text-sm">{label}</span>
        <Badge variant={count > 0 ? "default" : "secondary"} className="text-xs">
          {count}
        </Badge>
      </CardContent>
    </Card>
  );
}
