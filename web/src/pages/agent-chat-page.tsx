import { useParams } from "react-router-dom";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Send } from "lucide-react";

const personaLabels: Record<string, string> = {
  researcher: "Researcher",
  strategist: "Strategist",
  architect: "Architect",
  designer: "Designer",
  memory_agent: "Memory",
};

const personaTools: Record<string, string[]> = {
  researcher: ["source_search", "insight_create", "insight_update"],
  strategist: ["source_search", "insight_create", "requirement_create", "decision_create", "strategy_create"],
  architect: ["source_search", "architecture_create", "architecture_update", "feasibility_assess", "requirement_create"],
  designer: ["source_search", "design_create", "design_update", "pattern_check", "insight_create"],
  memory_agent: ["source_search", "graph_query", "trail_trace"],
};

export function AgentChatPage() {
  const { projectId, persona } = useParams<{ projectId: string; persona: string }>();
  const label = personaLabels[persona ?? ""] ?? persona;
  const tools = personaTools[persona ?? ""] ?? [];

  return (
    <div className="flex h-full flex-col">
      {/* Header */}
      <div className="shrink-0 border-b px-6 py-3">
        <div className="flex items-center gap-2">
          <h1 className="text-lg font-semibold">{label}</h1>
          <Badge variant="outline" className="text-[9px]">idle</Badge>
        </div>
        <div className="mt-1 flex gap-1 flex-wrap">
          {tools.map((tool) => (
            <Badge key={tool} variant="secondary" className="text-[9px]">{tool}</Badge>
          ))}
        </div>
      </div>

      {/* Messages area */}
      <div className="flex-1 overflow-y-auto p-6">
        <Card>
          <CardContent className="py-12 text-center text-sm text-muted-foreground">
            Start a conversation with the {label}. Messages and agent tool use will appear here.
          </CardContent>
        </Card>
      </div>

      {/* Input */}
      <div className="shrink-0 border-t px-6 py-4">
        <form className="flex gap-2" onSubmit={(e) => e.preventDefault()}>
          <Input placeholder={`Message ${label}...`} className="flex-1" />
          <Button type="submit" size="icon">
            <Send className="h-4 w-4" />
          </Button>
        </form>
      </div>
    </div>
  );
}
