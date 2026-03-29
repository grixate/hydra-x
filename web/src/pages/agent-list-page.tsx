import { useParams, useNavigate } from "react-router-dom";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Telescope, Compass, Blocks, PenTool, Brain } from "lucide-react";
import type { LucideIcon } from "lucide-react";

const agents: Array<{
  persona: string;
  label: string;
  description: string;
  icon: LucideIcon;
}> = [
  { persona: "researcher", label: "Researcher", description: "Pattern-finding and evidence-backed synthesis", icon: Telescope },
  { persona: "strategist", label: "Strategist", description: "Decisions, requirements, and strategic direction", icon: Compass },
  { persona: "architect", label: "Architect", description: "System design and technical architecture", icon: Blocks },
  { persona: "designer", label: "Designer", description: "User flows, interaction patterns, and UX specs", icon: PenTool },
  { persona: "memory_agent", label: "Memory", description: "Answer questions by traversing the product graph", icon: Brain },
];

export function AgentListPage() {
  const { projectId } = useParams<{ projectId: string }>();
  const navigate = useNavigate();

  return (
    <div className="p-6 space-y-6">
      <h1 className="text-xl font-semibold">Agents</h1>
      <p className="text-sm text-muted-foreground">
        Click an agent to start a conversation. Each agent has specialized tools and context.
      </p>
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {agents.map((agent) => (
          <Card
            key={agent.persona}
            className="cursor-pointer transition-colors hover:border-primary/50"
            onClick={() => navigate(`/projects/${projectId}/chat/${agent.persona}`)}
          >
            <CardContent className="p-5">
              <div className="flex items-start gap-3">
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-muted">
                  <agent.icon className="h-5 w-5" />
                </div>
                <div>
                  <div className="flex items-center gap-2">
                    <p className="text-sm font-medium">{agent.label}</p>
                    <Badge variant="outline" className="text-[9px]">idle</Badge>
                  </div>
                  <p className="mt-1 text-xs text-muted-foreground">{agent.description}</p>
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}
