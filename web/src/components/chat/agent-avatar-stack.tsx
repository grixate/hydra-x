import { Brain, Search, Compass, Paintbrush, Database, GitCompareArrows, Radar, type LucideIcon } from "lucide-react";

const ICON_MAP: Record<string, LucideIcon> = {
  memory: Database,
  researcher: Search,
  strategist: Compass,
  architect: Brain,
  designer: Paintbrush,
  coherence: GitCompareArrows,
  continuous_research: Radar,
};

export interface StackedAgent {
  persona: string;
  state?: "idle" | "working" | "waiting" | "blocked" | "proposing";
}

interface AgentAvatarStackProps {
  agents: StackedAgent[];
  max?: number;
  size?: number;
}

export function AgentAvatarStack({ agents, max = 3, size = 20 }: AgentAvatarStackProps) {
  const visible = agents.slice(0, max);
  const overflow = Math.max(0, agents.length - max);

  if (agents.length === 0) return null;

  return (
    <div className="flex items-center -space-x-1.5">
      {visible.map((agent, i) => {
        const Icon = ICON_MAP[agent.persona] ?? Database;
        return (
          <div
            key={`${agent.persona}-${i}`}
            className="flex items-center justify-center rounded-full border border-background bg-card shadow-sm"
            style={{ width: size, height: size, zIndex: visible.length - i }}
            title={agent.persona}
          >
            <Icon className="text-foreground/80" style={{ width: size * 0.55, height: size * 0.55 }} />
          </div>
        );
      })}
      {overflow > 0 && (
        <div
          className="flex items-center justify-center rounded-full border border-background bg-muted text-[9px] font-medium text-muted-foreground"
          style={{ width: size, height: size, zIndex: 0 }}
        >
          +{overflow}
        </div>
      )}
    </div>
  );
}
