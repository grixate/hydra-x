import { useCallback, useEffect, useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { api } from "@/lib/api";
import type { SimArchetype, SimGraphNode } from "@/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { ArrowLeft, ArrowRight, Play, Plus, X, Pencil, Check } from "lucide-react";
import { cn } from "@/lib/utils";
import { motion, AnimatePresence } from "motion/react";

type SelectedNode = { node_type: string; node_id: number; title: string };

const POPULATION_OPTIONS = [50, 100, 200, 500] as const;

export function SimulationConfigurePage() {
  const { projectId } = useParams<{ projectId: string }>();
  const navigate = useNavigate();
  const pid = Number(projectId);

  const [step, setStep] = useState(1);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);

  // Step 1 state
  const [scenario, setScenario] = useState("");
  const [graphNodes, setGraphNodes] = useState<SimGraphNode[]>([]);
  const [selectedNodes, setSelectedNodes] = useState<SelectedNode[]>([]);

  // Step 2 state
  const [archetypes, setArchetypes] = useState<SimArchetype[]>([]);
  const [editingIdx, setEditingIdx] = useState<number | null>(null);
  const [editDraft, setEditDraft] = useState<SimArchetype | null>(null);

  // Step 3 state
  const [populationSize, setPopulationSize] = useState(200);
  const [maxTicks, setMaxTicks] = useState(50);
  const [comparisonMode, setComparisonMode] = useState(false);
  const [scenarioB, setScenarioB] = useState("");
  const [estimate, setEstimate] = useState<{ cost: number; duration: number } | null>(null);

  // Load graph nodes on mount
  useEffect(() => {
    if (!pid || isNaN(pid)) return;
    api
      .getSimulationGraphNodes(pid)
      .then(setGraphNodes)
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [pid]);

  // Load archetypes when entering step 2
  useEffect(() => {
    if (step === 2 && archetypes.length === 0) {
      api
        .getSimulationArchetypes(pid)
        .then(setArchetypes)
        .catch(() => {});
    }
  }, [step, pid]);

  // Load estimate when entering step 3
  useEffect(() => {
    if (step === 3) {
      api
        .getSimulationEstimate(pid, {
          population_size: populationSize,
          max_ticks: maxTicks,
          comparison_mode: comparisonMode,
        })
        .then((e) => setEstimate({ cost: e.estimated_cost_cents, duration: e.estimated_duration_seconds }))
        .catch(() => {});
    }
  }, [step, pid, populationSize, maxTicks, comparisonMode]);

  const toggleNode = useCallback((node: SimGraphNode) => {
    setSelectedNodes((prev) => {
      const exists = prev.some((n) => n.node_type === node.node_type && n.node_id === node.id);
      if (exists) return prev.filter((n) => !(n.node_type === node.node_type && n.node_id === node.id));
      return [...prev, { node_type: node.node_type, node_id: node.id, title: node.title }];
    });
  }, []);

  const isSelected = (node: SimGraphNode) =>
    selectedNodes.some((n) => n.node_type === node.node_type && n.node_id === node.id);

  const canProceedStep1 = scenario.trim().length > 0 || selectedNodes.length > 0;
  const canProceedStep2 = archetypes.length > 0;

  const handleSubmit = useCallback(async () => {
    if (submitting) return;
    setSubmitting(true);
    try {
      const sim = await api.createSimulation(pid, {
        title: scenario.trim() || selectedNodes.map((n) => n.title).join(", "),
        scenario: scenario.trim() || undefined,
        archetypes,
        selected_node_ids: selectedNodes.map((n) => ({ node_type: n.node_type, node_id: n.node_id })),
        population_size: populationSize,
        max_ticks: maxTicks,
        comparison_mode: comparisonMode,
        scenario_b: comparisonMode ? scenarioB : undefined,
      });
      navigate(`/projects/${projectId}/simulation/${sim.id}`);
    } catch (err) {
      setSubmitError(err instanceof Error ? err.message : "Failed to create simulation");
      setSubmitting(false);
    }
  }, [pid, projectId, scenario, archetypes, selectedNodes, populationSize, maxTicks, comparisonMode, scenarioB, submitting, navigate]);

  const removeArchetype = (idx: number) => {
    setArchetypes((prev) => prev.filter((_, i) => i !== idx));
  };

  const startEdit = (idx: number) => {
    setEditingIdx(idx);
    setEditDraft({ ...archetypes[idx] });
  };

  const saveEdit = () => {
    if (editingIdx !== null && editDraft) {
      setArchetypes((prev) => prev.map((a, i) => (i === editingIdx ? editDraft : a)));
    }
    setEditingIdx(null);
    setEditDraft(null);
  };

  const addArchetype = () => {
    const newArch: SimArchetype = {
      title: "New Archetype",
      description: "Describe this user archetype...",
      traits: { type: "custom", confidence: "medium" },
    };
    setArchetypes((prev) => {
      const updated = [...prev, newArch];
      // Start editing the new archetype (use updated length, not stale closure)
      setEditingIdx(updated.length - 1);
      setEditDraft({ ...newArch });
      return updated;
    });
  };

  if (loading) {
    return (
      <div className="mx-auto max-w-2xl space-y-4 px-4 py-6">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-32 w-full" />
        <Skeleton className="h-32 w-full" />
      </div>
    );
  }

  const nodeTypeLabel: Record<string, string> = {
    decision: "Decision",
    requirement: "Requirement",
    design_node: "Design",
  };

  return (
    <div className="mx-auto max-w-2xl px-4 py-6">
      {/* Header */}
      <div className="mb-8 flex items-center justify-between">
        <div>
          <button
            onClick={() => navigate(`/projects/${projectId}/simulation`)}
            className="mb-2 flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
          >
            <ArrowLeft className="h-3 w-3" /> Back to simulations
          </button>
          <h1 className="text-xl font-semibold">New simulation</h1>
        </div>
        <span className="text-sm text-muted-foreground">Step {step} of 3</span>
      </div>

      {/* Progress bar */}
      <div className="mb-8 flex gap-1">
        {[1, 2, 3].map((s) => (
          <div
            key={s}
            className={cn(
              "h-1 flex-1 rounded-full transition-colors",
              s <= step ? "bg-foreground" : "bg-muted",
            )}
          />
        ))}
      </div>

      <AnimatePresence mode="wait">
        {/* Step 1: What to test */}
        {step === 1 && (
          <motion.div
            key="step1"
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -20 }}
            transition={{ duration: 0.2 }}
          >
            <h2 className="mb-4 text-base font-medium">What do you want to test?</h2>

            <textarea
              value={scenario}
              onChange={(e) => setScenario(e.target.value)}
              placeholder='Describe your simulation scenario... e.g. "Compare our freemium model vs paid-only for solo founders who are price-sensitive"'
              className="mb-6 w-full rounded-lg border bg-background px-4 py-3 text-sm leading-relaxed placeholder:text-muted-foreground/60 focus:outline-none focus:ring-1 focus:ring-ring resize-none"
              rows={4}
            />

            {graphNodes.length > 0 && (
              <>
                <p className="mb-3 text-sm text-muted-foreground">Or select from your product graph:</p>
                <div className="mb-4 grid grid-cols-2 gap-2">
                  {graphNodes.map((node) => (
                    <button
                      key={`${node.node_type}-${node.id}`}
                      onClick={() => toggleNode(node)}
                      className={cn(
                        "flex flex-col items-start rounded-lg border px-3 py-2.5 text-left text-sm transition-colors",
                        isSelected(node)
                          ? "border-foreground bg-foreground/5"
                          : "hover:bg-muted/50",
                      )}
                    >
                      <span className="flex items-center gap-1.5">
                        <span className="text-[10px] font-bold uppercase tracking-wider text-muted-foreground">
                          {nodeTypeLabel[node.node_type] ?? node.node_type}
                        </span>
                        {isSelected(node) && <Check className="h-3 w-3 text-foreground" />}
                      </span>
                      <span className="mt-0.5 font-medium line-clamp-1">{node.title}</span>
                    </button>
                  ))}
                </div>

                {selectedNodes.length > 0 && (
                  <p className="mb-4 text-xs text-muted-foreground">
                    Selected: {selectedNodes.map((n) => n.title).join(", ")}
                  </p>
                )}
              </>
            )}

            <div className="flex justify-end">
              <Button onClick={() => setStep(2)} disabled={!canProceedStep1}>
                Next <ArrowRight className="ml-1.5 h-3.5 w-3.5" />
              </Button>
            </div>
          </motion.div>
        )}

        {/* Step 2: Archetypes */}
        {step === 2 && (
          <motion.div
            key="step2"
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -20 }}
            transition={{ duration: 0.2 }}
          >
            <h2 className="mb-1 text-base font-medium">User archetypes</h2>
            <p className="mb-5 text-sm text-muted-foreground">
              Auto-generated from your research insights:
            </p>

            <div className="space-y-3">
              {archetypes.length === 0 && (
                <Card>
                  <CardContent className="py-8 text-center text-sm text-muted-foreground">
                    No archetypes generated. Add research insights to your project first, or create archetypes manually.
                  </CardContent>
                </Card>
              )}

              {archetypes.map((arch, idx) => (
                <Card key={idx}>
                  <CardContent className="py-3 px-4">
                    {editingIdx === idx && editDraft ? (
                      <div className="space-y-2">
                        <input
                          value={editDraft.title}
                          onChange={(e) => setEditDraft({ ...editDraft, title: e.target.value })}
                          className="w-full rounded border bg-background px-2 py-1 text-sm font-medium focus:outline-none focus:ring-1 focus:ring-ring"
                        />
                        <textarea
                          value={editDraft.description}
                          onChange={(e) => setEditDraft({ ...editDraft, description: e.target.value })}
                          className="w-full rounded border bg-background px-2 py-1 text-sm resize-none focus:outline-none focus:ring-1 focus:ring-ring"
                          rows={2}
                        />
                        <div className="flex justify-end">
                          <Button size="sm" onClick={saveEdit}>
                            <Check className="mr-1 h-3 w-3" /> Save
                          </Button>
                        </div>
                      </div>
                    ) : (
                      <div className="flex items-start justify-between">
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-medium">{arch.title}</p>
                          <p className="mt-0.5 text-sm text-muted-foreground line-clamp-2">
                            {arch.description}
                          </p>
                          {arch.traits && (
                            <div className="mt-1.5 flex flex-wrap gap-1.5">
                              {Object.entries(arch.traits).map(([k, v]) => (
                                <span
                                  key={k}
                                  className="rounded-full bg-muted px-2 py-0.5 text-[10px] text-muted-foreground"
                                >
                                  {k}: {v}
                                </span>
                              ))}
                            </div>
                          )}
                        </div>
                        <div className="ml-3 flex items-center gap-1">
                          <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => startEdit(idx)}>
                            <Pencil className="h-3 w-3" />
                          </Button>
                          <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => removeArchetype(idx)}>
                            <X className="h-3 w-3" />
                          </Button>
                        </div>
                      </div>
                    )}
                  </CardContent>
                </Card>
              ))}
            </div>

            <button
              onClick={addArchetype}
              className="mt-3 flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground transition-colors"
            >
              <Plus className="h-3.5 w-3.5" /> Add archetype
            </button>

            <div className="mt-8 flex justify-between">
              <Button variant="outline" onClick={() => setStep(1)}>
                <ArrowLeft className="mr-1.5 h-3.5 w-3.5" /> Back
              </Button>
              <Button onClick={() => setStep(3)} disabled={!canProceedStep2}>
                Next <ArrowRight className="ml-1.5 h-3.5 w-3.5" />
              </Button>
            </div>
          </motion.div>
        )}

        {/* Step 3: Configure & launch */}
        {step === 3 && (
          <motion.div
            key="step3"
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -20 }}
            transition={{ duration: 0.2 }}
          >
            <h2 className="mb-5 text-base font-medium">Configuration</h2>

            {/* Population size */}
            <div className="mb-6">
              <label className="mb-2 block text-sm font-medium">Population size</label>
              <div className="flex gap-2">
                {POPULATION_OPTIONS.map((size) => (
                  <button
                    key={size}
                    onClick={() => setPopulationSize(size)}
                    className={cn(
                      "rounded-lg border px-4 py-2 text-sm font-medium transition-colors",
                      populationSize === size
                        ? "border-foreground bg-foreground text-background"
                        : "hover:bg-muted/50",
                    )}
                  >
                    {size}
                  </button>
                ))}
                <span className="self-center text-sm text-muted-foreground">agents</span>
              </div>
            </div>

            {/* Simulation ticks */}
            <div className="mb-6">
              <label className="mb-2 block text-sm font-medium">Simulation ticks</label>
              <div className="flex items-center gap-3">
                <input
                  type="range"
                  min={10}
                  max={100}
                  step={10}
                  value={maxTicks}
                  onChange={(e) => setMaxTicks(Number(e.target.value))}
                  className="flex-1"
                />
                <span className="min-w-[80px] text-sm text-muted-foreground">
                  {maxTicks} ticks
                </span>
              </div>
            </div>

            {/* Comparison mode */}
            <div className="mb-6">
              <label className="mb-2 flex items-center gap-2 text-sm font-medium">
                <input
                  type="checkbox"
                  checked={comparisonMode}
                  onChange={(e) => setComparisonMode(e.target.checked)}
                  className="rounded"
                />
                Run scenario A vs B
              </label>
              {comparisonMode && (
                <div className="ml-6 mt-2 space-y-2">
                  <div>
                    <p className="text-xs text-muted-foreground">Scenario A</p>
                    <p className="text-sm">{scenario || selectedNodes.map((n) => n.title).join(", ") || "Primary scenario"}</p>
                  </div>
                  <div>
                    <p className="text-xs text-muted-foreground">Scenario B</p>
                    <input
                      value={scenarioB}
                      onChange={(e) => setScenarioB(e.target.value)}
                      placeholder="Describe the alternative scenario..."
                      className="w-full rounded border bg-background px-3 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-ring"
                    />
                  </div>
                </div>
              )}
            </div>

            {/* Estimate */}
            <div className="mb-8 rounded-lg border border-dashed px-4 py-3">
              {estimate ? (
                <div className="flex items-center gap-6 text-sm">
                  <span className="text-muted-foreground">
                    Estimated cost:{" "}
                    <span className="font-medium text-foreground">
                      ~${(estimate.cost / 100).toFixed(2)}
                    </span>
                  </span>
                  <span className="text-muted-foreground">
                    Estimated duration:{" "}
                    <span className="font-medium text-foreground">
                      ~{Math.ceil(estimate.duration / 60)} min
                    </span>
                  </span>
                </div>
              ) : (
                <Skeleton className="h-5 w-64" />
              )}
            </div>

            {submitError && (
              <p className="mb-4 text-sm text-destructive">{submitError}</p>
            )}

            <div className="flex justify-between">
              <Button variant="outline" onClick={() => setStep(2)}>
                <ArrowLeft className="mr-1.5 h-3.5 w-3.5" /> Back
              </Button>
              <Button onClick={handleSubmit} disabled={submitting}>
                <Play className="mr-1.5 h-3.5 w-3.5" />
                {submitting ? "Starting..." : "Run simulation"}
              </Button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
