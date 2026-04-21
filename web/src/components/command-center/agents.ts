import { Blocks, Brain, Compass, GitCompareArrows, PenTool, Radar, Telescope } from "lucide-react";
import type { LucideIcon } from "lucide-react";

export type AgentDefinition = {
  id: string;
  label: string;
  icon: LucideIcon;
  kind: "conversational" | "background";
};

export const AGENTS: AgentDefinition[] = [
  { id: "researcher", label: "Researcher", icon: Telescope, kind: "conversational" },
  { id: "strategist", label: "Strategist", icon: Compass, kind: "conversational" },
  { id: "architect", label: "Architect", icon: Blocks, kind: "conversational" },
  { id: "designer", label: "Designer", icon: PenTool, kind: "conversational" },
  { id: "memory_agent", label: "Memory", icon: Brain, kind: "conversational" },
  { id: "coherence", label: "Coherence", icon: GitCompareArrows, kind: "background" },
  { id: "continuous_research", label: "Watch", icon: Radar, kind: "background" },
];

export const AGENTS_BY_ID: Record<string, AgentDefinition> = Object.fromEntries(
  AGENTS.map((agent) => [agent.id, agent]),
);

export function agentLabel(id: string): string {
  return AGENTS_BY_ID[id]?.label ?? id;
}
