import { AGENTS } from "./agents";
import { AgentStatusCard, type AgentStatus } from "./agent-status-card";

export function AgentStatusStrip({
  statuses,
  selectedAgentId,
  onSelectAgent,
}: {
  statuses: AgentStatus[];
  selectedAgentId: string | null;
  onSelectAgent: (agentId: string | null) => void;
}) {
  const byId = new Map(statuses.map((s) => [s.persona, s]));

  return (
    <div className="flex gap-2 overflow-x-auto pb-1">
      {AGENTS.map((agent) => (
        <AgentStatusCard
          key={agent.id}
          agent={agent}
          status={byId.get(agent.id)}
          selected={selectedAgentId === agent.id}
          onSelect={() => onSelectAgent(selectedAgentId === agent.id ? null : agent.id)}
        />
      ))}
    </div>
  );
}
