import { useCallback, useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import { api } from "@/lib/api";
import type { Simulation } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Play, Download, ChevronDown, ChevronUp } from "lucide-react";
import { cn } from "@/lib/utils";

const statusColors: Record<string, string> = {
  pending: "bg-yellow-100 text-yellow-800",
  running: "bg-blue-100 text-blue-800",
  completed: "bg-green-100 text-green-800",
  failed: "bg-red-100 text-red-800",
};

export function SimulationPage() {
  const { projectId } = useParams<{ projectId: string }>();
  const pid = Number(projectId);

  const [simulations, setSimulations] = useState<Simulation[]>([]);
  const [loading, setLoading] = useState(true);
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [expandedId, setExpandedId] = useState<number | null>(null);
  const [importingId, setImportingId] = useState<number | null>(null);

  useEffect(() => {
    if (!projectId || isNaN(pid)) return;
    setLoading(true);
    setError(null);
    api
      .listSimulations(pid)
      .then(setSimulations)
      .catch((err) => setError(err.message ?? "Failed to load simulations"))
      .finally(() => setLoading(false));
  }, [projectId]);

  const handleCreate = useCallback(async () => {
    if (creating) return;
    setCreating(true);
    try {
      const sim = await api.createSimulation(pid);
      setSimulations((prev) => [sim, ...prev]);
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "Failed to create simulation",
      );
    } finally {
      setCreating(false);
    }
  }, [pid, creating]);

  const handleImportResults = useCallback(
    async (simId: number) => {
      setImportingId(simId);
      try {
        const updated = await api.importSimulationResults(pid, simId);
        setSimulations((prev) =>
          prev.map((s) => (s.id === simId ? updated : s)),
        );
      } catch (err) {
        setError(
          err instanceof Error ? err.message : "Failed to import results",
        );
      } finally {
        setImportingId(null);
      }
    },
    [pid],
  );

  const handleExpand = useCallback(
    async (simId: number) => {
      if (expandedId === simId) {
        setExpandedId(null);
        return;
      }
      try {
        const detail = await api.getSimulation(pid, simId);
        setSimulations((prev) =>
          prev.map((s) => (s.id === simId ? detail : s)),
        );
        setExpandedId(simId);
      } catch {
        setExpandedId(simId);
      }
    },
    [pid, expandedId],
  );

  if (loading) {
    return (
      <div className="space-y-4 p-6">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-24 w-full" />
        <Skeleton className="h-24 w-full" />
      </div>
    );
  }

  return (
    <div className="space-y-6 p-6">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold">Simulations</h1>
        <Button onClick={handleCreate} disabled={creating} size="sm">
          <Play className="mr-1.5 h-3.5 w-3.5" />
          {creating ? "Starting..." : "New Simulation"}
        </Button>
      </div>

      {error && (
        <Card>
          <CardContent className="py-4 text-center text-sm text-destructive">
            {error}
          </CardContent>
        </Card>
      )}

      {simulations.length === 0 && !error && (
        <Card>
          <CardContent className="py-12 text-center text-sm text-muted-foreground">
            No simulations yet. Run one to test your product assumptions against
            generated user archetypes.
          </CardContent>
        </Card>
      )}

      <div className="space-y-3">
        {simulations.map((sim) => (
          <Card key={sim.id}>
            <CardHeader className="pb-3">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <CardTitle className="text-sm">
                    Simulation #{sim.id}
                  </CardTitle>
                  <Badge
                    className={cn(
                      "text-[9px]",
                      statusColors[sim.status] ?? "bg-muted text-muted-foreground",
                    )}
                  >
                    {sim.status}
                  </Badge>
                  {sim.results_imported && (
                    <Badge variant="outline" className="text-[9px]">
                      results imported
                    </Badge>
                  )}
                </div>
                <div className="flex items-center gap-1">
                  {sim.status === "completed" && !sim.results_imported && (
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => handleImportResults(sim.id)}
                      disabled={importingId === sim.id}
                    >
                      <Download className="mr-1.5 h-3 w-3" />
                      {importingId === sim.id ? "Importing..." : "Import Results"}
                    </Button>
                  )}
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-8 w-8"
                    onClick={() => handleExpand(sim.id)}
                  >
                    {expandedId === sim.id ? (
                      <ChevronUp className="h-4 w-4" />
                    ) : (
                      <ChevronDown className="h-4 w-4" />
                    )}
                  </Button>
                </div>
              </div>
            </CardHeader>

            {sim.scenario_summary && (
              <CardContent className="pt-0 pb-3">
                <p className="text-sm text-muted-foreground line-clamp-2">
                  {sim.scenario_summary}
                </p>
              </CardContent>
            )}

            {expandedId === sim.id && (
              <CardContent className="border-t pt-4 space-y-3">
                {sim.archetype_summary && (
                  <div>
                    <p className="text-[10px] font-bold uppercase tracking-[0.3em] text-muted-foreground mb-1">
                      Archetypes
                    </p>
                    <p className="text-sm">{sim.archetype_summary}</p>
                  </div>
                )}
                {sim.inserted_at && (
                  <p className="text-[10px] text-muted-foreground">
                    Created{" "}
                    {new Date(sim.inserted_at).toLocaleString([], {
                      dateStyle: "medium",
                      timeStyle: "short",
                    })}
                  </p>
                )}
              </CardContent>
            )}
          </Card>
        ))}
      </div>
    </div>
  );
}
