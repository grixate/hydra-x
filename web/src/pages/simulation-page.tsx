import { useEffect, useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { api } from "@/lib/api";
import type { Simulation } from "@/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Plus, ArrowRight, FlaskConical } from "lucide-react";
import { cn } from "@/lib/utils";
import { motion } from "motion/react";

const statusConfig: Record<string, { label: string; className: string; dot: string }> = {
  proposed: { label: "Proposed", className: "bg-yellow-100 text-yellow-800", dot: "bg-yellow-500" },
  configuring: { label: "Configuring", className: "bg-slate-100 text-slate-700", dot: "bg-slate-400" },
  running: { label: "Running", className: "bg-blue-100 text-blue-800", dot: "bg-blue-500 animate-pulse" },
  completed: { label: "Completed", className: "bg-green-100 text-green-800", dot: "bg-green-500" },
  failed: { label: "Failed", className: "bg-red-100 text-red-800", dot: "bg-red-500" },
};

export function SimulationPage() {
  const { projectId } = useParams<{ projectId: string }>();
  const navigate = useNavigate();
  const pid = Number(projectId);

  const [simulations, setSimulations] = useState<Simulation[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

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

  if (loading) {
    return (
      <div className="mx-auto max-w-2xl space-y-4 px-4 py-6">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-24 w-full" />
        <Skeleton className="h-24 w-full" />
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-2xl px-4 py-6">
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-xl font-semibold">Simulations</h1>
        <Button
          size="sm"
          onClick={() => navigate(`/projects/${projectId}/simulation/new`)}
        >
          <Plus className="mr-1.5 h-3.5 w-3.5" />
          New simulation
        </Button>
      </div>

      {error && (
        <Card className="mb-4">
          <CardContent className="py-4 text-center text-sm text-destructive">
            {error}
          </CardContent>
        </Card>
      )}

      {simulations.length === 0 && !error && (
        <motion.div
          initial={{ opacity: 0, scale: 0.97 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ duration: 0.4, delay: 0.1 }}
          className="flex flex-col items-center justify-center py-24 text-center"
        >
          <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-muted">
            <FlaskConical className="h-5 w-5 text-muted-foreground" />
          </div>
          <p className="text-base font-medium text-foreground">No simulations yet</p>
          <p className="mt-2 max-w-sm text-sm text-muted-foreground">
            Simulations let you test product decisions against simulated user populations before committing resources.
            Create one to compare strategies, validate designs, or discover hidden risks.
          </p>
          <Button
            className="mt-6"
            onClick={() => navigate(`/projects/${projectId}/simulation/new`)}
          >
            <Plus className="mr-1.5 h-3.5 w-3.5" />
            New simulation
          </Button>
        </motion.div>
      )}

      <div className="space-y-3">
        {simulations.map((sim, i) => {
          const config = statusConfig[sim.status] ?? statusConfig.configuring;
          const meta = sim.metadata || {};
          const title = sim.title ?? (meta.title as string) ?? `Simulation #${sim.id}`;
          const popSize = sim.population_size ?? (meta.population_size as number);
          const maxTicks = sim.max_ticks ?? (meta.max_ticks as number);
          const comparison = sim.comparison_mode ?? (meta.comparison_mode as boolean);
          const results = (meta.results && typeof meta.results === "object" ? meta.results : {}) as Record<string, unknown>;
          const costCents = (meta.cost_cents as number) ?? (results.cost_cents as number | undefined);
          const keyFinding = results.key_finding as string | undefined;
          const tickProgress = (meta.current_tick as number) ?? undefined;

          const detailUrl =
            sim.status === "completed" || sim.status === "failed" || sim.status === "running"
              ? `/projects/${projectId}/simulation/${sim.id}`
              : undefined;

          return (
            <motion.div
              key={sim.id}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.2, delay: i * 0.04 }}
            >
              <Card
                className={cn(
                  "transition-colors",
                  detailUrl && "cursor-pointer hover:bg-muted/30",
                )}
                onClick={() => detailUrl && navigate(detailUrl)}
              >
                <CardContent className="py-4 px-5">
                  <div className="flex items-start justify-between">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <h3 className="text-sm font-medium truncate">{title}</h3>
                        <Badge className={cn("text-[9px] shrink-0", config.className)}>
                          <span className={cn("mr-1 inline-block h-1.5 w-1.5 rounded-full", config.dot)} />
                          {config.label}
                          {sim.status === "running" && tickProgress != null && maxTicks && (
                            <span className="ml-1">{tickProgress}/{maxTicks}</span>
                          )}
                        </Badge>
                      </div>

                      <div className="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-0.5 text-xs text-muted-foreground">
                        {popSize && <span>{popSize} agents</span>}
                        {comparison && <span>A/B comparison</span>}
                        {sim.archetype_summary && Array.isArray(sim.archetype_summary) && (
                          <span>{sim.archetype_summary.length} archetypes</span>
                        )}
                        {costCents != null && <span>${((costCents as number) / 100).toFixed(2)}</span>}
                        {sim.status === "completed" && sim.updated_at && (
                          <span>
                            {new Date(sim.updated_at).toLocaleDateString("en-US", {
                              month: "short",
                              day: "numeric",
                              year: "numeric",
                            })}
                          </span>
                        )}
                      </div>

                      {keyFinding && (
                        <p className="mt-2 text-xs text-muted-foreground line-clamp-1">
                          Key finding: {keyFinding}
                        </p>
                      )}

                      {sim.scenario_summary && !keyFinding && (
                        <p className="mt-2 text-xs text-muted-foreground line-clamp-1">
                          {sim.scenario_summary}
                        </p>
                      )}
                    </div>

                    {detailUrl && (
                      <ArrowRight className="ml-3 mt-1 h-4 w-4 shrink-0 text-muted-foreground/50" />
                    )}
                  </div>
                </CardContent>
              </Card>
            </motion.div>
          );
        })}
      </div>

      {/* New simulation CTA at bottom */}
      {simulations.length > 0 && (
        <button
          onClick={() => navigate(`/projects/${projectId}/simulation/new`)}
          className="mt-3 flex w-full items-center justify-center gap-2 rounded-lg border border-dashed py-4 text-sm text-muted-foreground hover:bg-muted/30 hover:text-foreground transition-colors"
        >
          <Plus className="h-3.5 w-3.5" />
          New simulation
        </button>
      )}
    </div>
  );
}
