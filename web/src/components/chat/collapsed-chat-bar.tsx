import { useMemo } from "react";
import { useLocation } from "react-router-dom";

import { AgentAvatarStack } from "./agent-avatar-stack";
import { SURFACE_CONFIG, classifySurface, type ChatSurface } from "./agent-chat-pane";
import { AGENTS } from "./universal-input";
import { useChatDockSignals } from "@/hooks/use-chat-dock-signals";

function surfaceAgentLabel(surface: ChatSurface): string {
  const slug = SURFACE_CONFIG[surface]?.defaultAgent ?? "strategist";
  return AGENTS.find((a) => a.slug === slug)?.label ?? "Chat";
}

interface CollapsedChatBarProps {
  projectId: number;
  onExpand: () => void;
}

export function CollapsedChatBar({ projectId, onExpand }: CollapsedChatBarProps) {
  const location = useLocation();
  const surface = useMemo(
    () => classifySurface(location.pathname, String(projectId)),
    [location.pathname, projectId],
  );
  const agentLabel = surfaceAgentLabel(surface);

  const { workingAgents, proposalCount, anyWorking } = useChatDockSignals(projectId);

  return (
    <button
      type="button"
      onClick={onExpand}
      title="Open chat (⌘J)"
      className={`pointer-events-auto flex h-10 items-center gap-2.5 rounded-full border bg-background/95 px-3 shadow-md backdrop-blur-sm transition-colors hover:bg-muted/60 ${
        anyWorking ? "agent-working-border" : ""
      }`}
    >
      {workingAgents.length > 0 ? (
        <AgentAvatarStack agents={workingAgents} max={3} size={20} />
      ) : (
        <span className="h-5 w-5 rounded-full border border-dashed border-muted-foreground/40" />
      )}

      <span className="text-xs font-medium text-foreground/90">{agentLabel}</span>

      {proposalCount > 0 && (
        <span className="ml-0.5 flex min-w-[18px] items-center justify-center rounded-full bg-primary px-1.5 text-[10px] font-semibold text-primary-foreground">
          {proposalCount}
        </span>
      )}

      <span className="ml-2 flex items-center">
        <kbd className="rounded border bg-muted/60 px-1 py-0.5 text-[9px] font-medium text-muted-foreground">
          ⌘J
        </kbd>
      </span>
    </button>
  );
}
