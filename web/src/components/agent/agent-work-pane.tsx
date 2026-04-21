import { useState, useEffect, useMemo } from "react";
import { api } from "@/lib/api";
import { NODE_COLORS } from "@/components/graph/graph-constants";
import { nodeTypeLabel } from "@/components/shared/node-type-icon";
import { relativeLabel } from "@/lib/utils";
import { ActivityHeatmap } from "./activity-heatmap";

interface AgentWorkPaneProps {
  projectId: number;
  persona: string;
}

type AgentWork = {
  current: Array<{ type: string; title: string }>;
  completed: Array<{ type: string; title: string; node_id?: number; node_type?: string; status?: string; at?: string }>;
  queued: Array<{ type: string; title: string }>;
};

export function AgentWorkPane({ projectId, persona }: AgentWorkPaneProps) {
  const [work, setWork] = useState<AgentWork | null>(null);
  const [analytics, setAnalytics] = useState<{
    productivity: { nodes_created: number; nodes_accepted: number; acceptance_rate: number };
  } | null>(null);

  useEffect(() => {
    api.getAgentWork(projectId, persona).then(setWork).catch(() => {});
    api.getAnalytics(projectId).then(setAnalytics).catch(() => {});
  }, [projectId, persona]);

  const recentNodes = work?.completed ?? [];

  // Dummy heatmap data — stable per persona (would come from analytics endpoint in production)
  const heatmapData = useMemo(() => {
    // Seed-like approach: use persona string to get consistent random-ish data
    const seed = persona.split("").reduce((acc, c) => acc + c.charCodeAt(0), 0);
    return Array.from({ length: 7 }, (_, di) =>
      Array.from({ length: 24 }, (_, hi) => {
        const v = ((seed * (di + 1) * (hi + 1) * 17) % 100);
        return v < 15 ? Math.floor(v / 4) + 1 : 0;
      }),
    );
  }, [persona]);

  return (
    <div className="flex h-full flex-col">
      <div className="flex items-center gap-2 px-4 py-3 border-b shrink-0">
        <h3 className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
          Work output
        </h3>
      </div>

      <div className="flex-1 overflow-y-auto min-h-0">
        <div className="px-4 py-4 space-y-6">
          {/* Recent output */}
          <section>
            <p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground mb-3">
              Recent output
            </p>
            {recentNodes.length === 0 && (
              <p className="text-xs text-muted-foreground">No recent output from this agent.</p>
            )}
            <div className="space-y-0">
              {recentNodes.slice(0, 20).map((node, i) => {
                const nodeType = node.node_type ?? node.type ?? "unknown";
                const dotColor = NODE_COLORS[nodeType] ?? NODE_COLORS.default;
                return (
                  <div
                    key={`${nodeType}-${node.node_id ?? i}`}
                    className="flex items-start gap-3 py-2.5 cursor-pointer hover:bg-muted/30 rounded-md px-1 -mx-1"
                  >
                    <div
                      className="mt-1.5 h-2 w-2 shrink-0 rounded-full"
                      style={{ backgroundColor: dotColor }}
                    />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium truncate">{node.title}</p>
                      <p className="text-xs text-muted-foreground">
                        {node.status ?? nodeTypeLabel(nodeType)}
                        {node.at && ` · ${relativeLabel(node.at)}`}
                      </p>
                    </div>
                  </div>
                );
              })}
            </div>
          </section>

          {/* Activity heatmap */}
          <section>
            <p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground mb-3">
              Activity
            </p>
            <ActivityHeatmap data={heatmapData} />
          </section>

          {/* Stats */}
          <section>
            <p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground mb-3">
              Stats
            </p>
            {analytics ? (
              <div className="space-y-1 text-xs text-muted-foreground">
                <p>{analytics.productivity.nodes_created} nodes created this month</p>
                <p>{analytics.productivity.nodes_accepted} accepted ({Math.round(analytics.productivity.acceptance_rate * 100)}%)</p>
              </div>
            ) : (
              <p className="text-xs text-muted-foreground">Loading...</p>
            )}
          </section>
        </div>
      </div>
    </div>
  );
}
