import { useEffect, useMemo, useState } from "react";
import { useParams } from "react-router-dom";

import { api } from "@/lib/api";
import type { Contradiction } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { RulesPanel } from "@/components/background/rules-panel";
import { cn } from "@/lib/utils";

type StatusFilter = "all" | "open" | "resolved" | "dismissed" | "acknowledged_tension";
type SeverityFilter = "all" | "low" | "medium" | "high";

export function CoherencePage() {
  const { projectId } = useParams<{ projectId: string }>();
  const pid = Number(projectId);
  const [items, setItems] = useState<Contradiction[]>([]);
  const [loading, setLoading] = useState(true);
  const [status, setStatus] = useState<StatusFilter>("open");
  const [severity, setSeverity] = useState<SeverityFilter>("all");

  useEffect(() => {
    if (!Number.isFinite(pid)) return;
    setLoading(true);
    api
      .listContradictions(pid, {
        status: status === "all" ? undefined : status,
        min_severity: severity === "all" ? undefined : severity,
        limit: 200,
      })
      .then(setItems)
      .catch(() => setItems([]))
      .finally(() => setLoading(false));
  }, [pid, status, severity]);

  const filtered = useMemo(() => {
    if (severity === "all") return items;
    const rank = { low: 0, medium: 1, high: 2 } as const;
    return items.filter((c) => rank[c.severity] >= rank[severity]);
  }, [items, severity]);

  async function dismiss(id: number) {
    await api.dismissContradiction(pid, id).catch(() => {});
    setItems((prev) => prev.filter((c) => c.id !== id));
  }

  async function resolve(id: number) {
    await api.resolveContradiction(pid, id).catch(() => {});
    setItems((prev) => prev.filter((c) => c.id !== id));
  }

  return (
    <div className="space-y-6 p-6">
      <header className="flex flex-wrap items-baseline justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold">Coherence</h1>
          <p className="text-xs text-muted-foreground">
            Contradictions the agent has surfaced across your project graph.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Select value={status} onValueChange={(v) => setStatus(v as StatusFilter)}>
            <SelectTrigger className="h-8 w-36 text-xs">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="open">Open</SelectItem>
              <SelectItem value="acknowledged_tension">Tension</SelectItem>
              <SelectItem value="resolved">Resolved</SelectItem>
              <SelectItem value="dismissed">Dismissed</SelectItem>
              <SelectItem value="all">All</SelectItem>
            </SelectContent>
          </Select>
          <Select value={severity} onValueChange={(v) => setSeverity(v as SeverityFilter)}>
            <SelectTrigger className="h-8 w-36 text-xs">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Any severity</SelectItem>
              <SelectItem value="low">Low+</SelectItem>
              <SelectItem value="medium">Medium+</SelectItem>
              <SelectItem value="high">High only</SelectItem>
            </SelectContent>
          </Select>
        </div>
      </header>

      <section className="space-y-2">
        {loading ? (
          <div className="space-y-2">
            <Skeleton className="h-14 w-full" />
            <Skeleton className="h-14 w-full" />
            <Skeleton className="h-14 w-full" />
          </div>
        ) : filtered.length === 0 ? (
          <div className="rounded-lg border bg-card p-6 text-center text-sm text-muted-foreground">
            No findings match these filters.
          </div>
        ) : (
          filtered.map((c) => (
            <ContradictionRow
              key={c.id}
              contradiction={c}
              onDismiss={() => dismiss(c.id)}
              onResolve={() => resolve(c.id)}
            />
          ))
        )}
      </section>

      <RulesPanel projectId={pid} agentId="coherence" />
    </div>
  );
}

function ContradictionRow({
  contradiction,
  onDismiss,
  onResolve,
}: {
  contradiction: Contradiction;
  onDismiss: () => void;
  onResolve: () => void;
}) {
  const severityColor =
    contradiction.severity === "high"
      ? "bg-red-100 text-red-800"
      : contradiction.severity === "medium"
      ? "bg-yellow-100 text-yellow-800"
      : "bg-muted text-muted-foreground";

  return (
    <div className="rounded-lg border bg-card p-3">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0 flex-1 space-y-1">
          <div className="flex flex-wrap items-center gap-2">
            <Badge className={cn("text-[10px]", severityColor)}>{contradiction.severity}</Badge>
            <Badge variant="outline" className="text-[10px]">
              {contradiction.mode}
            </Badge>
            <Badge variant="secondary" className="text-[10px]">
              {contradiction.status}
            </Badge>
            <span className="text-[11px] text-muted-foreground">
              {contradiction.node_a.type} ↔ {contradiction.node_b.type}
            </span>
          </div>
          {contradiction.explanation && (
            <p className="text-sm text-foreground/90">{contradiction.explanation}</p>
          )}
          {contradiction.detected_at && (
            <p className="text-[10px] text-muted-foreground">
              Detected {new Date(contradiction.detected_at).toLocaleString()}
            </p>
          )}
        </div>
        {contradiction.status === "open" && (
          <div className="flex shrink-0 items-center gap-1">
            <Button size="sm" variant="ghost" className="h-7 text-xs" onClick={onDismiss}>
              Dismiss
            </Button>
            <Button size="sm" variant="outline" className="h-7 text-xs" onClick={onResolve}>
              Resolve
            </Button>
          </div>
        )}
      </div>
    </div>
  );
}
