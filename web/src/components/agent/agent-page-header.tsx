import { useNavigate } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Settings } from "lucide-react";
import { StatusPill, NodesPill, AcceptancePill, SpendPill, TokensPill } from "./agent-stat-pills";

interface AgentStats {
  nodes_created: number;
  nodes_accepted: number;
  nodes_rejected?: number;
  nodes_pending?: number;
  acceptance_rate: number;
  by_node_type?: Record<string, number>;
  spend_cents: number;
  tokens: number;
  tokens_in?: number;
  tokens_out?: number;
  call_count?: number;
  activity_heatmap?: number[][];
  last_active_at?: string | null;
}

interface AgentPageHeaderProps {
  projectId: number;
  persona: string;
  label: string;
  description: string;
  icon: string;
  state: string;
  stats: AgentStats | null;
}

export function AgentPageHeader({
  projectId,
  persona,
  label,
  description,
  icon,
  state,
  stats,
}: AgentPageHeaderProps) {
  const navigate = useNavigate();

  return (
    <div className="space-y-3 border-b px-5 py-4 shrink-0">
      {/* Top row: identity + configure */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <span className="text-lg">{icon}</span>
          <div>
            <h1 className="text-sm font-semibold">{label}</h1>
            <p className="text-xs text-muted-foreground">{description}</p>
          </div>
        </div>
        <Button
          variant="ghost"
          size="sm"
          className="text-xs"
          onClick={() => navigate(`/projects/${projectId}/settings`)}
        >
          <Settings className="mr-1.5 h-3.5 w-3.5" />
          Configure
        </Button>
      </div>

      {/* Bottom row: stat pills */}
      <div className="flex items-center gap-2 flex-wrap">
        <StatusPill
          state={state}
          lastActiveAt={stats?.last_active_at}
          heatmap={stats?.activity_heatmap}
        />
        {stats && (
          <>
            <NodesPill
              created={stats.nodes_created}
              accepted={stats.nodes_accepted}
              rejected={stats.nodes_rejected}
              pending={stats.nodes_pending}
              byNodeType={stats.by_node_type}
            />
            <AcceptancePill rate={stats.acceptance_rate} />
            <SpendPill cents={stats.spend_cents} />
            <TokensPill
              tokens={stats.tokens}
              tokensIn={stats.tokens_in}
              tokensOut={stats.tokens_out}
              callCount={stats.call_count}
            />
          </>
        )}
      </div>
    </div>
  );
}
