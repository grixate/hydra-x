import { useState, useEffect, useMemo } from "react";
import { useParams } from "react-router-dom";
import { api } from "@/lib/api";
import type { ProductTask } from "@/types";
import { StatusBadge, PriorityBadge } from "@/components/shared/status-badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";

const columns = [
  { key: "backlog", label: "Backlog" },
  { key: "ready", label: "Ready" },
  { key: "in_progress", label: "In Progress" },
  { key: "review", label: "Review" },
  { key: "done", label: "Done" },
];

export function TasksPage() {
  const { projectId } = useParams<{ projectId: string }>();
  const [tasks, setTasks] = useState<ProductTask[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!projectId) return;
    setLoading(true);
    setError(null);
    api.listTasks(Number(projectId))
      .then(setTasks)
      .catch((err) => setError(err.message ?? "Failed to load tasks"))
      .finally(() => setLoading(false));
  }, [projectId]);

  const columnKeys = new Set(columns.map((c) => c.key));
  const grouped = useMemo(() => {
    const map: Record<string, ProductTask[]> = {};
    for (const col of columns) map[col.key] = [];
    map["_other"] = [];
    for (const t of tasks) {
      if (columnKeys.has(t.status)) {
        map[t.status].push(t);
      } else {
        map["_other"].push(t);
      }
    }
    return map;
  }, [tasks]);

  if (loading) {
    return (
      <div className="space-y-4 p-6">
        <Skeleton className="h-8 w-48" />
        <div className="flex gap-4">
          {columns.map((c) => <Skeleton key={c.key} className="h-64 w-48" />)}
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="p-6">
        <h1 className="font-display text-xl font-semibold mb-6">Tasks</h1>
        <Card><CardContent className="py-8 text-center text-sm text-[var(--ink-soft)]">{error}</CardContent></Card>
      </div>
    );
  }

  if (tasks.length === 0) {
    return (
      <div className="p-6">
        <h1 className="font-display text-xl font-semibold mb-6">Tasks</h1>
        <Card>
          <CardContent className="py-12 text-center text-sm text-[var(--ink-soft)]">
            No tasks yet. Talk to the strategist or architect to generate tasks from requirements. Or create one manually.
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="p-6">
      <h1 className="font-display text-xl font-semibold mb-6">Tasks</h1>
      <div className="flex gap-4 overflow-x-auto pb-4">
        {columns.map((col) => (
          <TaskColumn
            key={col.key}
            label={col.label}
            tasks={grouped[col.key] ?? []}
          />
        ))}
        {(grouped["_other"]?.length ?? 0) > 0 && (
          <TaskColumn label="Other" tasks={grouped["_other"]} />
        )}
      </div>
    </div>
  );
}

function TaskColumn({ label, tasks }: { label: string; tasks: ProductTask[] }) {
  return (
    <div className="w-[260px] shrink-0">
      <div className="mb-2 flex items-center gap-2">
        <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-[var(--ink-soft)]">{label}</p>
        <Badge variant="secondary" className="text-[9px]">{tasks.length}</Badge>
      </div>
      <ScrollArea className="max-h-[65vh]">
        <div className="space-y-2">
          {tasks.map((task) => (
            <TaskCard key={task.id} task={task} />
          ))}
        </div>
      </ScrollArea>
    </div>
  );
}

function TaskCard({ task }: { task: ProductTask }) {
  return (
    <Card className={cn(
      "transition-colors hover:border-[var(--accent)]",
    )}>
      <CardContent className="p-3">
        <div className="flex items-start justify-between gap-2">
          <p className="text-sm font-medium leading-tight">{task.title}</p>
          {task.priority && <PriorityBadge priority={task.priority} />}
        </div>
        {task.assignee && (
          <p className="mt-1 text-[10px] text-[var(--ink-soft)]">{task.assignee}</p>
        )}
        {task.body && (
          <p className="mt-1 text-xs text-[var(--ink-soft)] line-clamp-2">{task.body.slice(0, 100)}</p>
        )}
      </CardContent>
    </Card>
  );
}
