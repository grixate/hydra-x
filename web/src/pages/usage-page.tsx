import { useState, useEffect } from "react";
import { useParams } from "react-router-dom";
import { api } from "@/lib/api";
import { Skeleton } from "@/components/ui/skeleton";
import { MetricCard } from "@/components/usage/usage-metric-card";
import { PeriodSelector, type Period, type DateRange } from "@/components/usage/usage-period-selector";
import { SpendChart } from "@/components/usage/usage-spend-chart";
import { AgentBreakdown } from "@/components/usage/usage-agent-breakdown";
import { ModelBreakdown } from "@/components/usage/usage-model-breakdown";
import { TokenLog } from "@/components/usage/usage-token-log";

function formatTokens(t: number): string {
  if (t >= 1_000_000) return `${(t / 1_000_000).toFixed(1)}M`;
  if (t >= 1_000) return `${(t / 1_000).toFixed(0)}K`;
  return String(t);
}

export function UsagePage() {
  const { projectId } = useParams<{ projectId: string }>();
  const pid = Number(projectId);

  const [period, setPeriod] = useState<Period>("30d");
  const [dateRange, setDateRange] = useState<DateRange | undefined>();
  const [summary, setSummary] = useState<{
    month_cost_cents: number;
    month_tokens: number;
    week_cost_cents: number;
    week_tokens: number;
    today_cost_cents: number;
    today_tokens: number;
    budget_cents: number | null;
    budget_percent: number | null;
  } | null>(null);
  const [analytics, setAnalytics] = useState<{
    spend_by_agent: Array<{
      persona: string;
      tokens: number;
      cost_cents: number;
      by_model: Array<{ model: string; tokens_in: number; tokens_out: number; cost_cents: number }>;
    }>;
    spend_by_model: Array<{ model: string; tokens_in: number; tokens_out: number; cost_cents: number }>;
    daily_spend: Array<{ date: string; tokens: number; cost_cents: number }>;
  } | null>(null);
  const [initialLoading, setInitialLoading] = useState(true);

  useEffect(() => {
    if (isNaN(pid)) return;
    const fromStr = period === "custom" && dateRange ? dateRange.from.toISOString().slice(0, 10) : undefined;
    const toStr = period === "custom" && dateRange ? dateRange.to.toISOString().slice(0, 10) : undefined;

    Promise.all([
      api.getSpendSummary(pid).then(setSummary),
      api.getSpendAnalytics(pid, period === "custom" ? "30d" : period, fromStr, toStr).then(setAnalytics),
    ])
      .catch(() => {})
      .finally(() => setInitialLoading(false));
  }, [pid, period, dateRange]);

  if (initialLoading) {
    return (
      <div className="space-y-6 p-6">
        <Skeleton className="h-8 w-48" />
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          {[1, 2, 3, 4].map((i) => (
            <Skeleton key={i} className="h-28 rounded-xl" />
          ))}
        </div>
        <Skeleton className="h-64 rounded-xl" />
      </div>
    );
  }

  const budgetPct = summary?.budget_percent ?? 0;

  return (
    <div className="space-y-6 p-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold">Usage</h1>
          <p className="text-sm text-muted-foreground">
            Token consumption and cost monitoring
          </p>
        </div>
        <PeriodSelector
          period={period}
          dateRange={dateRange}
          onChange={(p, dr) => {
            setPeriod(p);
            setDateRange(dr);
          }}
        />
      </div>

      {/* Top row: 4 metric cards */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <MetricCard
          title="Total spend"
          value={`$${((summary?.month_cost_cents ?? 0) / 100).toFixed(2)}`}
          subtitle="this month"
        />
        <MetricCard
          title="This week"
          value={`$${((summary?.week_cost_cents ?? 0) / 100).toFixed(2)}`}
          subtitle={`${formatTokens(summary?.week_tokens ?? 0)} tokens`}
        />
        <MetricCard
          title="Tokens used"
          value={formatTokens(summary?.month_tokens ?? 0)}
          subtitle="this month"
        />
        <MetricCard
          title="Budget"
          value={summary?.budget_cents ? `${budgetPct}%` : "No limit"}
          subtitle={summary?.budget_cents ? `of $${(summary.budget_cents / 100).toFixed(0)}/mo` : "Set a budget in Settings"}
          progress={summary?.budget_cents ? budgetPct : undefined}
        />
      </div>

      {/* Spend chart */}
      <SpendChart data={analytics?.daily_spend ?? []} />

      {/* Bottom row: two columns */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <AgentBreakdown data={analytics?.spend_by_agent ?? []} />
        <ModelBreakdown data={analytics?.spend_by_model ?? []} />
      </div>

      {/* Token log */}
      <TokenLog projectId={pid} />
    </div>
  );
}
