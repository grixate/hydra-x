import { useState, useEffect } from "react";
import { useParams } from "react-router-dom";
import { api } from "@/lib/api";
import { AgentPageHeader } from "@/components/agent/agent-page-header";
import { AgentConversationPane } from "@/components/agent/agent-conversation-pane";
import { AgentWorkFeed } from "@/components/agent/agent-work-feed";
import { ResizablePanes } from "@/components/board/resizable-panes";

const AGENT_CONFIG: Record<string, { label: string; description: string; icon: string }> = {
  researcher: { label: "Researcher", description: "Pattern-finding and evidence-backed synthesis", icon: "🔬" },
  strategist: { label: "Strategist", description: "Decisions, requirements, and strategic direction", icon: "🎯" },
  architect: { label: "Architect", description: "System design and technical architecture", icon: "🏗️" },
  designer: { label: "Designer", description: "User flows, interaction patterns, and UX specs", icon: "🎨" },
  memory_agent: { label: "Memory", description: "Answer questions by traversing the product graph", icon: "🧠" },
};

type AgentStats = {
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
};

export function AgentPage() {
  const { projectId, persona } = useParams<{ projectId: string; persona: string }>();
  const pid = Number(projectId);
  const config = AGENT_CONFIG[persona ?? ""] ?? { label: persona ?? "Agent", description: "", icon: "🤖" };

  const [state, setState] = useState("idle");
  const [stats, setStats] = useState<AgentStats | null>(null);

  useEffect(() => {
    if (!pid || !persona) return;

    // Fetch agent status
    api.getAgentStatuses(pid).then((statuses) => {
      const s = statuses.find((st) => st.persona === persona);
      if (s) setState(s.state);
    }).catch(() => {});

    // Fetch feed stats for header pills
    api.getAgentFeed(pid, persona, 1, 0).then((data) => {
      setStats(data.stats);
    }).catch(() => {});
  }, [pid, persona]);

  if (!persona || !projectId) return null;

  return (
    <div className="flex h-full flex-col">
      <AgentPageHeader
        projectId={pid}
        persona={persona}
        label={config.label}
        description={config.description}
        icon={config.icon}
        state={state}
        stats={stats}
      />

      <ResizablePanes
        storageKey={`agent-${persona}`}
        defaultSplit={0.55}
        left={<AgentConversationPane projectId={pid} persona={persona} />}
        right={<AgentWorkFeed projectId={pid} persona={persona} />}
      />
    </div>
  );
}
