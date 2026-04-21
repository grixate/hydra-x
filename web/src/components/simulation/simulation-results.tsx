import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Download, MessageSquare, Check } from "lucide-react";
import { cn } from "@/lib/utils";
import type { Simulation } from "@/types";

interface SimulationResultsProps {
  simulation: Simulation;
  onImportToGraph?: (selectedIds: string[]) => void;
  onStartBoardSession?: () => void;
}

type Finding = {
  id: string;
  type: "insight" | "signal";
  title: string;
  description: string;
};

export function SimulationResults({
  simulation,
  onImportToGraph,
  onStartBoardSession,
}: SimulationResultsProps) {
  const metadata = simulation.metadata || {};
  const results = (metadata.results ?? {}) as Record<string, unknown>;
  const report = (results.report ?? metadata.report ?? {}) as Record<string, unknown>;

  const title = (metadata.title as string) ?? `Simulation #${simulation.id}`;
  const populationSize = (metadata.population_size as number) ?? 200;
  const maxTicks = (metadata.max_ticks as number) ?? 50;
  const comparisonMode = (metadata.comparison_mode as boolean) ?? false;

  const summary = (report.summary as string) ??
    "Simulation completed. Results have been generated and are ready for review.";

  const scenarioA = (report.scenario_a ?? {}) as Record<string, number>;
  const scenarioB = (report.scenario_b ?? {}) as Record<string, number>;

  const archetypeResults = (report.archetype_results ?? []) as Array<{
    name: string;
    retention: number;
    description: string;
  }>;

  const frictionPoints = (report.friction_points ?? []) as Array<{
    title: string;
    description: string;
    agents_affected: number;
  }>;

  const opportunities = (report.opportunities ?? []) as Array<{
    title: string;
    description: string;
  }>;

  // Build findings for import
  const findings: Finding[] = [
    ...opportunities.map((o, i) => ({
      id: `insight-${i}`,
      type: "insight" as const,
      title: o.title,
      description: o.description,
    })),
    ...frictionPoints.map((f, i) => ({
      id: `signal-${i}`,
      type: "signal" as const,
      title: f.title,
      description: f.description,
    })),
  ];

  const [selectedFindings, setSelectedFindings] = useState<Set<string>>(
    () => new Set(findings.filter((f) => f.type === "insight").map((f) => f.id)),
  );

  const toggleFinding = (id: string) => {
    setSelectedFindings((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const completedDate = simulation.updated_at
    ? new Date(simulation.updated_at).toLocaleDateString("en-US", {
        year: "numeric",
        month: "long",
        day: "numeric",
      })
    : "";

  return (
    <div className="mx-auto max-w-2xl px-4 py-6 space-y-6">
      {/* Executive Summary */}
      <Card>
        <CardContent className="py-5 px-5">
          <h1 className="text-lg font-semibold">{title}</h1>
          <p className="mt-1 text-xs text-muted-foreground">
            {populationSize} agents &middot; {maxTicks} ticks &middot; {completedDate}
          </p>
          <p className="mt-4 text-sm leading-relaxed text-foreground/90">{summary}</p>
        </CardContent>
      </Card>

      {/* Key Metrics Comparison */}
      {comparisonMode && (Object.keys(scenarioA).length > 0 || Object.keys(scenarioB).length > 0) && (
        <div className="grid grid-cols-2 gap-3">
          <MetricsCard title={`Scenario A: ${(metadata.scenario_a_label as string) ?? "Primary"}`} metrics={scenarioA} />
          <MetricsCard title={`Scenario B: ${(metadata.scenario_b as string) ?? "Alternative"}`} metrics={scenarioB} />
        </div>
      )}

      {/* Archetype Breakdown */}
      {archetypeResults.length > 0 && (
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm">Archetype performance</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            {archetypeResults.map((arch, i) => (
              <div key={i}>
                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium">{arch.name}</span>
                  <span className="text-sm text-muted-foreground">{arch.retention}% retained</span>
                </div>
                <div className="mt-1.5 h-2 w-full rounded-full bg-muted">
                  <div
                    className="h-2 rounded-full bg-foreground transition-all"
                    style={{ width: `${Math.min(100, arch.retention)}%` }}
                  />
                </div>
                <p className="mt-1 text-xs text-muted-foreground">{arch.description}</p>
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      {/* Friction Points */}
      {frictionPoints.length > 0 && (
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm">Top friction points</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            {frictionPoints.map((fp, i) => (
              <div key={i} className="flex gap-3">
                <span className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-muted text-[10px] font-bold text-muted-foreground">
                  {i + 1}
                </span>
                <div>
                  <p className="text-sm font-medium">
                    {fp.title}
                    {fp.agents_affected > 0 && (
                      <span className="ml-2 text-xs text-muted-foreground">
                        {fp.agents_affected} agents affected
                      </span>
                    )}
                  </p>
                  <p className="mt-0.5 text-xs text-muted-foreground">{fp.description}</p>
                </div>
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      {/* Opportunities */}
      {opportunities.length > 0 && (
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm">Discovered opportunities</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {opportunities.map((opp, i) => (
              <div key={i}>
                <p className="text-sm font-medium">{opp.title}</p>
                <p className="mt-0.5 text-xs text-muted-foreground">{opp.description}</p>
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      {/* Import Findings */}
      {findings.length > 0 && (
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm">Import findings to your product graph</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {findings.map((f) => (
              <button
                key={f.id}
                onClick={() => toggleFinding(f.id)}
                className="flex w-full items-center gap-2.5 rounded-md px-2 py-1.5 text-left text-sm hover:bg-muted/50 transition-colors"
              >
                <span
                  className={cn(
                    "flex h-4 w-4 shrink-0 items-center justify-center rounded border transition-colors",
                    selectedFindings.has(f.id)
                      ? "border-foreground bg-foreground text-background"
                      : "border-muted-foreground/30",
                  )}
                >
                  {selectedFindings.has(f.id) && <Check className="h-3 w-3" />}
                </span>
                <span className="text-[10px] font-bold uppercase tracking-wider text-muted-foreground min-w-[50px]">
                  {f.type === "insight" ? "Insight" : "Signal"}
                </span>
                <span className="flex-1 truncate">{f.title}</span>
              </button>
            ))}

            <div className="mt-4 flex gap-2 pt-2">
              <Button
                size="sm"
                onClick={() => onImportToGraph?.([...selectedFindings])}
                disabled={selectedFindings.size === 0}
              >
                <Download className="mr-1.5 h-3 w-3" />
                Import {selectedFindings.size} selected to graph
              </Button>
              <Button size="sm" variant="outline" onClick={onStartBoardSession}>
                <MessageSquare className="mr-1.5 h-3 w-3" />
                Start Board session with all
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* No findings fallback */}
      {findings.length === 0 && !comparisonMode && archetypeResults.length === 0 && frictionPoints.length === 0 && (
        <Card>
          <CardContent className="py-8 text-center text-sm text-muted-foreground">
            Detailed results will appear here once the simulation report is analyzed.
          </CardContent>
        </Card>
      )}
    </div>
  );
}

function MetricsCard({ title, metrics }: { title: string; metrics: Record<string, number> }) {
  const metricLabels: Record<string, string> = {
    retention: "Retention",
    conversion: "Conversion",
    avg_engagement: "Avg engagement",
    churn_point: "Churn point",
    revenue_per_user: "Revenue/user",
  };

  return (
    <Card>
      <CardContent className="py-4 px-4">
        <p className="mb-3 text-xs font-medium text-muted-foreground">{title}</p>
        <div className="space-y-1.5">
          {Object.entries(metrics).map(([key, value]) => (
            <div key={key} className="flex items-center justify-between text-sm">
              <span className="text-muted-foreground">{metricLabels[key] ?? key}</span>
              <span className="font-medium">
                {typeof value === "number" && key.includes("revenue")
                  ? `$${value.toFixed(2)}`
                  : typeof value === "number" && key.includes("day")
                    ? `Day ${value}`
                    : typeof value === "number" && value <= 1
                      ? `${(value * 100).toFixed(0)}%`
                      : typeof value === "number" && value <= 100
                        ? `${value}%`
                        : value}
              </span>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}
