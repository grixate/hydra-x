import { useCallback, useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import { Plus, Trash2 } from "lucide-react";

import { api } from "@/lib/api";
import type { StreamEntry, WatchTarget } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { RulesPanel } from "@/components/background/rules-panel";

export function WatchPage() {
  const { projectId } = useParams<{ projectId: string }>();
  const pid = Number(projectId);

  return (
    <div className="space-y-6 p-6">
      <header>
        <h1 className="text-xl font-semibold">Watch</h1>
        <p className="text-xs text-muted-foreground">
          Targets the agent monitors and the findings it surfaces from the stream.
        </p>
      </header>

      <FindingsList projectId={pid} />
      <WatchTargetsSection projectId={pid} />
      <RulesPanel projectId={pid} agentId="continuous_research" />
    </div>
  );
}

function FindingsList({ projectId }: { projectId: number }) {
  const [entries, setEntries] = useState<StreamEntry[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!Number.isFinite(projectId)) return;
    setLoading(true);
    api
      .listStreamEntries(projectId)
      .then((all) =>
        setEntries(all.filter((e) => e.source_agent_id === "continuous_research")),
      )
      .catch(() => setEntries([]))
      .finally(() => setLoading(false));
  }, [projectId]);

  return (
    <section className="space-y-2">
      <h2 className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
        Recent findings
      </h2>
      {loading ? (
        <div className="space-y-2">
          <Skeleton className="h-12 w-full" />
          <Skeleton className="h-12 w-full" />
        </div>
      ) : entries.length === 0 ? (
        <div className="rounded-lg border bg-card p-6 text-center text-sm text-muted-foreground">
          No findings yet. The agent will post here when it spots something on a watch target.
        </div>
      ) : (
        entries.slice(0, 50).map((entry) => (
          <div key={entry.id} className="rounded-lg border bg-card px-3 py-2">
            <div className="flex items-baseline justify-between gap-2">
              <p className="truncate text-sm font-medium">{entry.title}</p>
              <span className="shrink-0 text-[10px] text-muted-foreground">
                {new Date(entry.inserted_at).toLocaleString()}
              </span>
            </div>
            {entry.summary && (
              <p className="mt-0.5 text-xs text-muted-foreground line-clamp-2">
                {entry.summary}
              </p>
            )}
          </div>
        ))
      )}
    </section>
  );
}

function WatchTargetsSection({ projectId }: { projectId: number }) {
  const [targets, setTargets] = useState<WatchTarget[]>([]);
  const [loading, setLoading] = useState(true);
  const [targetType, setTargetType] = useState("competitor");
  const [value, setValue] = useState("");
  const [adding, setAdding] = useState(false);

  useEffect(() => {
    if (!Number.isFinite(projectId)) return;
    api
      .listWatchTargets(projectId)
      .then(setTargets)
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [projectId]);

  const handleAdd = useCallback(async () => {
    const v = value.trim();
    if (!v || adding) return;
    setAdding(true);
    try {
      const wt = await api.createWatchTarget(projectId, {
        target_type: targetType,
        value: v,
      });
      setTargets((prev) => [...prev, wt]);
      setValue("");
    } catch {}
    setAdding(false);
  }, [projectId, targetType, value, adding]);

  const handleDelete = useCallback(
    async (id: number) => {
      try {
        await api.deleteWatchTarget(projectId, id);
        setTargets((prev) => prev.filter((t) => t.id !== id));
      } catch {}
    },
    [projectId],
  );

  return (
    <section className="space-y-2">
      <h2 className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
        Watch targets
      </h2>
      <div className="rounded-lg border bg-card p-4 space-y-3">
        <div className="flex gap-2">
          <Select value={targetType} onValueChange={setTargetType}>
            <SelectTrigger className="w-36">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="competitor">Competitor</SelectItem>
              <SelectItem value="keyword">Keyword</SelectItem>
              <SelectItem value="url">URL</SelectItem>
            </SelectContent>
          </Select>
          <Input
            value={value}
            onChange={(e) => setValue(e.target.value)}
            placeholder="e.g. acme.com or 'product-led growth'"
            className="flex-1"
            onKeyDown={(e) => {
              if (e.key === "Enter") handleAdd();
            }}
          />
          <Button size="sm" onClick={handleAdd} disabled={!value.trim() || adding}>
            <Plus className="h-3.5 w-3.5" />
          </Button>
        </div>

        {loading ? (
          <Skeleton className="h-8 w-full" />
        ) : targets.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            No watch targets yet. Add competitors, keywords, or URLs to monitor.
          </p>
        ) : (
          targets.map((wt) => (
            <div
              key={wt.id}
              className="flex items-center justify-between rounded-lg border px-3 py-2"
            >
              <div className="flex items-center gap-2">
                <Badge variant="secondary" className="text-[9px]">
                  {wt.target_type}
                </Badge>
                <span className="text-sm">{wt.value}</span>
              </div>
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7 text-muted-foreground hover:text-destructive"
                onClick={() => handleDelete(wt.id)}
              >
                <Trash2 className="h-3.5 w-3.5" />
              </Button>
            </div>
          ))
        )}
      </div>
    </section>
  );
}
